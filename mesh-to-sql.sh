#!/bin/sh
# =================================================================
# OPENWRT NETWORK TELEMETRY - v3.0 band seperation
# =================================================================
# --- CONFIGURATION (Adjust these) ---
TARGET_IP="192.168.31.10"       # Your SQL Server IP
TARGET_PORT="3306"
DB_USER="david"
DB_PASS="YOUR_PASSWORD"
DB_NAME="router"
APS="192.168.31.1 192.168.31.2 192.168.31.3 192.168.31.4"
LEASES="/tmp/dhcp.leases"
SSH_KEY="/root/.ssh/id_rsa"

# --- INTERNAL LOGIC ---
MODE_FORCE=0; MODE_DEBUG=0
for arg in "$@"; do
    [ "$arg" = "force-all" ] && MODE_FORCE=1
    [ "$arg" = "debug" ] && MODE_DEBUG=1
done

log() { [ $MODE_DEBUG -eq 1 ] && echo -e "\033[1;34m[DEBUG]\033[0m $1"; }

push_sql() {
    if [ $MODE_DEBUG -eq 1 ]; then
        echo -e "\033[1;32m[SQL]\033[0m $1"
        echo "$1" | mariadb -h $TARGET_IP -P $TARGET_PORT -u$DB_USER -p$DB_PASS $DB_NAME
    else
        echo "$1" | mariadb -h $TARGET_IP -P $TARGET_PORT -u$DB_USER -p$DB_PASS $DB_NAME 2>/dev/null
    fi
}

# --- 1. INVENTORY ---
log "Updating Client Inventory..."
NEIGHBORS=$(ip neigh show dev br-lan | grep "lladdr" | awk '{ip=$1; mac=""; for(i=1;i<=NF;i++) if($i=="lladdr") mac=$(i+1); if(mac ~ /:/) print ip"|"mac}')
for entry in $NEIGHBORS; do
    IP=$(echo "$entry" | cut -d'|' -f1); MAC=$(echo "$entry" | cut -d'|' -f2 | tr '[:upper:]' '[:lower:]')
    [ -z "$MAC" ] && continue
    NAME=$(grep -i "$MAC" $LEASES | awk '{print $4}' | head -n 1)
    [ -z "$NAME" ] || [ "$NAME" = "*" ] && NAME="Unknown"
    COL="ip_address"; echo "$IP" | grep -q ":" && COL="ipv6_address"
    push_sql "INSERT INTO client_inventory (mac_address, hostname, $COL, last_seen, total_active_minutes) VALUES ('$MAC', '$NAME', '$IP', NOW(), 2) ON DUPLICATE KEY UPDATE last_seen=NOW(), hostname='$NAME', $COL='$IP', total_active_minutes=total_active_minutes+2;"
done

# --- 2. AP HEALTH & ROAMING ---
for ap in $APS; do
    log "Polling AP Stats: $ap"
    CMD="for if in \$(iwinfo | grep 'ESSID' | awk '{print \$1}'); do iwinfo \$if assoclist; done; echo '---'; cat /proc/uptime; echo '---'; free -m | grep Mem | awk '{print \$4}'; echo '---'; cat /proc/loadavg; echo '---'; logread | grep -E 'err|crit|alert|emerg' | tail -n 5"
    if [ "$ap" = "192.168.31.1" ]; then
        REMOTE_DATA=$(sh -c "$CMD" 2>/dev/null)
    else
        REMOTE_DATA=$(ssh -i $SSH_KEY -o StrictHostKeyChecking=no -T root@$ap "$CMD" 2>/dev/null)
    fi
    [ -z "$REMOTE_DATA" ] && continue

    WIFI_DATA=$(echo "$REMOTE_DATA" | awk 'BEGIN{RS="---"} NR==1 {print}')
    UPTIME=$(echo "$REMOTE_DATA" | awk 'BEGIN{RS="---"} NR==2 {print int($1)}'); RAM=$(echo "$REMOTE_DATA" | awk 'BEGIN{RS="---"} NR==3 {print $1}'); LOAD=$(echo "$REMOTE_DATA" | awk 'BEGIN{RS="---"} NR==4 {print $1}'); ERRORS=$(echo "$REMOTE_DATA" | awk 'BEGIN{RS="---"} NR==5 {print}')

    echo "$WIFI_DATA" | awk -v ap="$ap" -v lease_file="$LEASES" '
        BEGIN { while ((getline < lease_file) > 0) { leases[tolower($2)] = $4 } }
        /^[0-9A-F:]+/ { mac=tolower($1); sig=$2; name=(mac in leases)?leases[mac]:"Unknown";
            printf "INSERT INTO wifi_roaming_log (hostname, mac_address, ap_ip, signal_dbm) VALUES (\"%s\", \"%s\", \"%s\", %d);\n", name, mac, ap, sig;
        }' | while read -r sql; do push_sql "$sql"; done

    [ -n "$UPTIME" ] && push_sql "INSERT INTO ap_system_stats (ap_ip, uptime, ram_free_mb, cpu_load) VALUES ('$ap', $UPTIME, $RAM, $LOAD);"
    echo "$ERRORS" | while read -r line; do
        [ -z "$line" ] && continue
        push_sql "INSERT INTO ap_error_logs (ap_ip, log_message, priority) VALUES ('$ap', \"$(echo $line | sed 's/"/\\"/g')\", 'CRITICAL');"
    done
done

# --- 3. WIFI SCAN (Robust Parsing) ---
if [ $MODE_FORCE -eq 1 ] || [ "$(date +%H%M)" = "0400" ]; then
    log "Running Environment Scan..."
    for ap in $APS; do
        SCAN_CMD="for r in \$(iwinfo | grep 'ESSID' | awk '{print \$1}'); do echo \"IFACE:\$r\"; iwinfo \"\$r\" scan; done"
        if [ "$ap" = "192.168.31.1" ]; then SCAN_RAW=$(sh -c "$SCAN_CMD" 2>/dev/null); else SCAN_RAW=$(ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$ap "$SCAN_CMD" 2>/dev/null); fi
        [ -z "$SCAN_RAW" ] && continue
        echo "$SCAN_RAW" | awk -v ap_ip="$ap" '
            /IFACE:/ { split($0, a, ":"); iface=a[2]; next }
            /Cell/ { p(); bssid=$NF; ssid="Unknown"; chan="N/A"; freq=0; sig=0; enc="Unknown" }
            /ESSID:/ { split($0, a, "\""); ssid=a[2] }
            /Encryption:/ { split($0, a, ": "); enc=a[2]; if(enc=="") enc="Open" }
            /Channel/ && !/Width/ { 
                for(i=1; i<=NF; i++) if($i ~ /Channel/) chan=$(i+1);
                if($0 ~ /GHz/) { match($0, /[0-9.]+/); f=substr($0, RSTART, RLENGTH); freq=f*1000 }
                else if($0 ~ /MHz/) { match($0, /[0-9.]+/); freq=substr($0, RSTART, RLENGTH) }
            }
            /Signal:/ { sig=$2; sig=int(sig) }
            function p() { if(bssid ~ /:/ && chan != "N/A") { gsub(/[\\"'\'']/, "", ssid);
                printf "INSERT INTO wifi_scan_results (ap_ip, interface, ssid, bssid, channel, frequency_mhz, signal_dbm, encryption) VALUES (\"%s\", \"%s\", \"%s\", \"%s\", %s, %d, %d, \"%s\");\n", ap_ip, iface, ssid, bssid, chan, freq, sig, enc;
            }} END { p() }' | while read -r single_sql; do push_sql "$single_sql"; done
    done
fi

# --- 4. WAN & SPEEDTEST ---
log "Finalizing WAN stats..."
WAN_IFACE=$(ip route | awk '/default/ {print $5}' | head -n 1)
if [ -n "$WAN_IFACE" ]; then
    RX=$(cat /sys/class/net/$WAN_IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
    TX=$(cat /sys/class/net/$WAN_IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print $1/1000}')
    push_sql "INSERT INTO gateway_stats (wan_rx_bytes, wan_tx_bytes, cpu_temp) VALUES ($RX, $TX, '$TEMP');"
fi

if [ $MODE_FORCE -eq 1 ] || [ "$(date +%M)" -lt 02 ]; then
    TEST_DATA=$(speedtest-cli --simple 2>/dev/null)
    if [ -n "$TEST_DATA" ]; then
        PING=$(echo "$TEST_DATA" | awk '/Ping/ {print $2}'); DOWN=$(echo "$TEST_DATA" | awk '/Download/ {print $2}'); UP=$(echo "$TEST_DATA" | awk '/Upload/ {print $2}')
        push_sql "INSERT INTO speedtests (ping_ms, download_mbit, upload_mbit) VALUES ($PING, $DOWN, $UP);"
    fi
fi
push_sql "DELETE FROM client_inventory WHERE mac_address NOT LIKE '%:%';"
log "Done."
