#!/bin/sh
# =================================================================
# OPENWRT NETWORK TELEMETRY - v4
# Features: ARP, Inventory, Roaming, AP Stats, WAN IP, Speedtest
# =================================================================

# --- DATABASE CONFIGURATION ---
TARGET_IP="192.168.XX.XX"
TARGET_PORT="3306"
DB_USER="your_user"
DB_PASS="your_password"
DB_NAME="router"

# --- NETWORK CONFIGURATION ---
# List all your Mesh Access Points IPs here
APS="192.168.31.1 192.168.31.2 192.168.31.3 192.168.31.4"
LOCAL_SUBNET="192.168.31.0/24"
LEASES="/tmp/dhcp.leases"
SSH_KEY="/root/.ssh/id_rsa"

# --- INTERVAL CONFIGURATION ---
# At which minute of the hour should these tasks run?
SCAN_MIN="05"      # Neighborhood WiFi scan (once per hour)
SPEED_MIN="02"     # Speedtest (once per hour)

# --- SYSTEM SETUP ---
RTIME=$(date +'%Y-%m-%d %H:%M:%S')
CUR_MIN=$(date +'%M')

# Mode Handling
MODE_FORCE=0; MODE_DEBUG=0
for arg in "$@"; do
    [ "$arg" = "force-all" ] && MODE_FORCE=1
    [ "$arg" = "debug" ] && MODE_DEBUG=1
done

push_sql() {
    CLEAN_SQL=$(echo "$1" | tr -d '\n' | tr -d '\r' | sed 's/  */ /g')
    [ $MODE_DEBUG -eq 1 ] && echo -e "\033[1;32m[SQL]\033[0m $CLEAN_SQL"
    /usr/bin/mariadb -h $TARGET_IP -P $TARGET_PORT -u$DB_USER -p$DB_PASS $DB_NAME -e "$CLEAN_SQL" 2>/dev/null
}

# --- 1. ARP-SCAN & VENDOR LOGGING ---
echo "Step 1: ARP-Scan..."
arp-scan --interface=br-lan $LOCAL_SUBNET | awk -v rtime="$RTIME" '
    /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ { 
        ip=$1; mac=tolower($2); $1=$2=""; vendor=$0; 
        gsub(/^[ \t]+|[ \t]+$/, "", vendor);
        gsub(/\(DUP: [0-9]+\)/, "", vendor);
        if(vendor == "" || vendor == " ") vendor="Unknown Device";
        gsub(/"/, "", vendor);
        printf "INSERT INTO arpscan_results (timestamp, ip_address, mac_address, vendor) VALUES (\"%s\", \"%s\", \"%s\", \"%s\");\n", rtime, ip, mac, vendor;
    }' | while read -r sql; do push_sql "$sql"; done
# Wake neighbors for kernel table
arp-scan -q --interface=br-lan $LOCAL_SUBNET | awk '{print $1}' | xargs -n1 fping -q -c1 2>/dev/null

# --- 2. CLIENT INVENTORY ---
echo "Step 2: Inventory Register..."
NEIGHBORS=$(ip neigh show dev br-lan | grep -E "lladdr|REACHABLE|STALE" | awk '{ip=$1; mac=""; for(i=1;i<=NF;i++) if($i=="lladdr") mac=$(i+1); if(mac ~ /:/) print ip"|"mac}')
for entry in $NEIGHBORS; do
    IP=$(echo "$entry" | cut -d'|' -f1); MAC=$(echo "$entry" | cut -d'|' -f2 | tr '[:upper:]' '[:lower:]')
    [ -z "$MAC" ] && continue
    NAME=$(grep -i "$MAC" $LEASES | awk '{print $4}' | head -n 1)
    [ -z "$NAME" ] || [ "$NAME" = "*" ] && NAME="Unknown"
    COL="ip_address"; echo "$IP" | grep -q ":" && COL="ipv6_address"
    push_sql "INSERT INTO client_inventory (mac_address, hostname, $COL, first_seen, last_seen, total_active_minutes) VALUES ('$MAC', '$NAME', '$IP', '$RTIME', '$RTIME', 2) ON DUPLICATE KEY UPDATE last_seen='$RTIME', hostname='$NAME', $COL='$IP', total_active_minutes=total_active_minutes+2;"
done

# --- 3. ROAMING & AP STATS ---
echo "Step 3: Polling Mesh Nodes..."
for ap in $APS; do
    CMD="for if in \$(iwinfo | grep 'ESSID' | awk '{print \$1}'); do echo \"IFACE:\$if\"; iwinfo \$if assoclist; done; echo '---'; cat /proc/uptime; echo '---'; free -m | grep Mem; echo '---'; cat /proc/loadavg; echo '---'; logread | grep -E 'err|crit|alert|emerg' | tail -n 5; echo '---'; df -m / | tail -n 1"
    if [ "$ap" = "192.168.31.1" ]; then DATA=$(sh -c "$CMD" 2>/dev/null); else DATA=$(timeout 15 ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$ap "$CMD" 2>/dev/null); fi
    [ -z "$DATA" ] && continue

    WIFI=$(echo "$DATA" | awk 'BEGIN{RS="---"} NR==1 {print}'); UPTIME=$(echo "$DATA" | awk 'BEGIN{RS="---"} NR==2 {print int($1)}'); RAM_L=$(echo "$DATA" | awk 'BEGIN{RS="---"} NR==3 {print}'); FREE_M=$(echo "$RAM_L" | awk '{print $4}'); BUFF_M=$(echo "$RAM_L" | awk '{print $6}'); CACHE_M=$(echo "$RAM_L" | awk '{print $7}'); LOAD_L=$(echo "$DATA" | awk 'BEGIN{RS="---"} NR==4 {print}'); L1=$(echo "$LOAD_L" | awk '{print $1}'); ERRORS=$(echo "$DATA" | awk 'BEGIN{RS="---"} NR==5 {print}'); DISK_L=$(echo "$DATA" | awk 'BEGIN{RS="---"} NR==6 {print}'); D_TOT=$(echo "$DISK_L" | awk '{print $2}'); D_USD=$(echo "$DISK_L" | awk '{print $3}')

    echo "$WIFI" | awk -v ap="$ap" -v rtime="$RTIME" -v lease_file="$LEASES" '
        BEGIN { while ((getline < lease_file) > 0) { leases[tolower($2)] = $4 } }
        /IFACE:/ { split($0, a, ":"); current_if=a[2]; next }
        /^[0-9A-F:]+/ { mac=tolower($1); sig=$2; tx_r="0"; rx_r="0"; for(i=1;i<NF;i++){if($(i+1)~/MBit/){if(tx_r=="0")tx_r=$i;else rx_r=$i;}}
            name=(mac in leases)?leases[mac]:"Unknown";
            if(sig < 0) printf "INSERT INTO wifi_roaming_log (hostname, mac_address, ap_ip, interface, signal_dbm, tx_rate, rx_rate, timestamp) VALUES (\"%s\", \"%s\", \"%s\", \"%s\", %d, \"%s\", \"%s\", \"%s\");\n", name, mac, ap, current_if, sig, tx_r, rx_r, rtime;
        }' | while read -r sql; do push_sql "$sql"; done
    [ -n "$UPTIME" ] && push_sql "INSERT INTO ap_system_stats (ap_ip, uptime, cpu_load, ram_free_mb, mem_buffered_mb, mem_cached_mb, disk_total_mb, disk_used_mb, timestamp) VALUES ('$ap', $UPTIME, '$L1', $FREE_M, $BUFF_M, $CACHE_M, $D_TOT, $D_USD, '$RTIME');"
    echo "$ERRORS" | while read -r line; do [ -n "$line" ] && push_sql "INSERT INTO ap_error_logs (ap_ip, log_message, priority, timestamp) VALUES ('$ap', \"$(echo $line | sed 's/"/\\"/g')\", 'CRITICAL', '$RTIME');"; done
done

# --- 4. WIFI SCAN ---
if [ $MODE_FORCE -eq 1 ] || [ "$CUR_MIN" = "$SCAN_MIN" ]; then
    echo "Step 4: Neighborhood Scan..."
    for ap in $APS; do
        SCAN_CMD="for r in \$(iwinfo | grep 'ESSID' | awk '{print \$1}'); do echo \"IFACE:\$r\"; iwinfo \"\$r\" scan; done"
        if [ "$ap" = "192.168.31.1" ]; then RAW=$(sh -c "$SCAN_CMD" 2>/dev/null); else RAW=$(timeout 45 ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$ap "$SCAN_CMD" 2>/dev/null); fi
        [ -z "$RAW" ] && continue
        echo "$RAW" | awk -v ap_ip="$ap" -v rtime="$RTIME" '
            function p() { if(bssid ~ /:/ && chan > 0) { gsub(/[\\"'\'']/, "", ssid); printf "INSERT INTO wifi_scan_results (ap_ip, interface, ssid, bssid, channel, frequency_mhz, signal_dbm, encryption, timestamp) VALUES (\"%s\", \"%s\", \"%s\", \"%s\", %d, %d, %d, \"%s\", \"%s\");\n", ap_ip, iface, ssid, bssid, chan, freq, sig, enc, rtime; }}
            /IFACE:/ { split($0, a, ":"); iface=a[2]; next }
            /Cell/ { p(); bssid=$NF; ssid="Unknown"; chan=0; freq=0; sig=0; enc="Unknown" }
            /ESSID:/ { split($0, a, "\""); ssid=a[2] }
            /Encryption:/ { split($0, a, ": "); enc=a[2]; if(enc=="") enc="Open" }
            /Channel:/ && !/Width/ { for(i=1; i<NF; i++) if($i ~ /Channel/) { v=$(i+1); gsub(/[^0-9]/, "", v); chan=v; }
                if (match($0, /[0-9.]+[ ]*[GM]Hz/)) { f_raw = substr($0, RSTART, RLENGTH); if (f_raw ~ /GHz/) { gsub(/[^0-9.]/,"",f_raw); freq=f_raw*1000 } else { gsub(/[^0-9.]/,"",f_raw); freq=f_raw } } }
            /Signal:/ { sig=$2; sig=int(sig) } END { p() }' | while read -r single_sql; do push_sql "$single_sql"; done
    done
fi

# --- 5. GATEWAY STATS ---
echo "Step 5: Gateway Status..."
WAN_IFACE=$(ip route | awk '/default/ {print $5}' | head -n 1)
if [ -n "$WAN_IFACE" ]; then
    RX=$(cat /sys/class/net/$WAN_IFACE/statistics/rx_bytes 2>/dev/null || echo 0); TX=$(cat /sys/class/net/$WAN_IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print $1/1000}'); LOADAVG=$(cat /proc/loadavg)
    L1=$(echo $LOADAVG | awk '{print $1}'); L5=$(echo $LOADAVG | awk '{print $2}'); L15=$(echo $LOADAVG | awk '{print $3}')
    WIP=$(wget -qO- http://icanhazip.com 2>/dev/null || echo "0.0.0.0")
    GW=$(ip route | awk '/default/ {print $3}' | head -n 1); PROTO=$(uci get network.wan.proto 2>/dev/null || echo "unknown")
    DDNS=$(pgrep ddns-scripts >/dev/null && echo "Running" || echo "Stopped")
    STATUS="Connected"; [ "$WIP" = "0.0.0.0" ] && STATUS="Offline"
    push_sql "INSERT INTO gateway_stats (wan_iface, wan_rx_bytes, wan_tx_bytes, cpu_temp, load_1min, load_5min, load_15min, wan_ip, wan_status, ddns_status, wan_proto, wan_gateway, timestamp) VALUES ('$WAN_IFACE', $RX, $TX, '$TEMP', '$L1', '$L5', '$L15', '$WIP', '$STATUS', '$DDNS', '$PROTO', '$GW', '$RTIME');"
fi

# --- 6. SPEEDTEST ---
if [ $MODE_FORCE -eq 1 ] || [ "$CUR_MIN" = "$SPEED_MIN" ]; then
    echo "Step 6: Speedtest..."
    TEST=$(speedtest-cli --simple 2>/dev/null)
    [ -n "$TEST" ] && push_sql "INSERT INTO speedtests (ping_ms, download_mbit, upload_mbit, timestamp) VALUES ($(echo "$TEST" | awk '/Ping/ {print $2}'), $(echo "$TEST" | awk '/Download/ {print $2}'), $(echo "$TEST" | awk '/Upload/ {print $2}'), '$RTIME');"
fi

push_sql "DELETE FROM client_inventory WHERE mac_address NOT LIKE '%:%';"
echo "Done. Finish time: $RTIME"
