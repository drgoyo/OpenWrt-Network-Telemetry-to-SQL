#!/bin/sh
# =================================================================
# OPENWRT NETWORK TELEMETRY - v3.1
# Supports: Wi-Fi 7, Multi-AP Roaming, ARP-Logging, Speedtest
# =================================================================

# --- CONFIGURATION (Adjust for your environment) ---
TARGET_IP="192.168.31.10"
TARGET_PORT="3306"
DB_USER="david"
DB_PASS="davidoerteladmin"
DB_NAME="router"
APS="192.168.31.1 192.168.31.2 192.168.31.3 192.168.31.4"
LEASES="/tmp/dhcp.leases"
SSH_KEY="/root/.ssh/id_rsa"

# Fixed Router Timestamp (CET)
RTIME=$(date +'%Y-%m-%d %H:%M:%S')

# Execution Modes
MODE_FORCE=0; MODE_DEBUG=0
for arg in "$@"; do
    [ "$arg" = "force-all" ] && MODE_FORCE=1
    [ "$arg" = "debug" ] && MODE_DEBUG=1
done

push_sql() {
    /usr/bin/mariadb -h $TARGET_IP -P $TARGET_PORT -u$DB_USER -p$DB_PASS $DB_NAME -e "$1" 2>/dev/null
}

# 1. ARP-SCAN & LOGGING
arp-scan -qxlN -I br-lan | awk -v rtime="$RTIME" '
    /^[0-9.]+/ { 
        ip=$1; mac=tolower($2); 
        # Correctly isolate the vendor string
        vendor=$0; sub(/^[0-9.]+[ \t]+[0-9a-fA-F:]+[ \t]+/, "", vendor);
        if(vendor == "" || vendor ~ mac) vendor="(Unknown)";
        gsub(/"/, "", vendor);
        printf "INSERT INTO arpscan_results (timestamp, ip_address, mac_address, vendor) VALUES (\"%s\", \"%s\", \"%s\", \"%s\");\n", rtime, ip, mac, vendor;
    }' | while read -r sql; do push_sql "$sql"; done
arp-scan -qxlN -I br-lan | awk '{print $1}' | xargs -n1 fping -q -c1 2>/dev/null

# 2. CLIENT INVENTORY
NEIGHBORS=$(ip neigh show dev br-lan | grep -E "lladdr|REACHABLE|STALE" | awk '{ip=$1; mac=""; for(i=1;i<=NF;i++) if($i=="lladdr") mac=$(i+1); if(mac ~ /:/) print ip"|"mac}')
for entry in $NEIGHBORS; do
    IP=$(echo "$entry" | cut -d'|' -f1); MAC=$(echo "$entry" | cut -d'|' -f2 | tr '[:upper:]' '[:lower:]')
    [ -z "$MAC" ] && continue
    NAME=$(grep -i "$MAC" $LEASES | awk '{print $4}' | head -n 1)
    [ -z "$NAME" ] || [ "$NAME" = "*" ] && NAME="Unknown"
    COL="ip_address"; echo "$IP" | grep -q ":" && COL="ipv6_address"
    push_sql "INSERT INTO client_inventory (mac_address, hostname, $COL, last_seen, total_active_minutes) VALUES ('$MAC', '$NAME', '$IP', '$RTIME', 2) ON DUPLICATE KEY UPDATE last_seen='$RTIME', hostname='$NAME', $COL='$IP', total_active_minutes=total_active_minutes+2;"
done

# 3. REMOTE AP POLLING (Roaming, Health, Logs)
for ap in $APS; do
    CMD="for if in \$(iwinfo | grep 'ESSID' | awk '{print \$1}'); do echo \"IFACE:\$if\"; iwinfo \$if assoclist; done; echo '---'; cat /proc/uptime; echo '---'; free -m | grep Mem | awk '{print \$4}'; echo '---'; cat /proc/loadavg; echo '---'; logread | grep -E 'err|crit|alert|emerg' | tail -n 5"
    if [ "$ap" = "192.168.31.1" ]; then DATA=$(sh -c "$CMD" 2>/dev/null); else DATA=$(timeout 15 ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$ap "$CMD" 2>/dev/null); fi
    [ -z "$DATA" ] && continue

    WIFI=$(echo "$DATA" | awk 'BEGIN{RS="---"} NR==1 {print}')
    UPTIME=$(echo "$DATA" | awk 'BEGIN{RS="---"} NR==2 {print int($1)}'); RAM=$(echo "$DATA" | awk 'BEGIN{RS="---"} NR==3 {print $1}'); LOAD=$(echo "$DATA" | awk 'BEGIN{RS="---"} NR==4 {print $1}'); ERRORS=$(echo "$DATA" | awk 'BEGIN{RS="---"} NR==5 {print}')

    echo "$WIFI" | awk -v ap="$ap" -v rtime="$RTIME" -v lease_file="$LEASES" '
        BEGIN { while ((getline < lease_file) > 0) { leases[tolower($2)] = $4 } }
        /IFACE:/ { split($0, a, ":"); current_if=a[2]; next }
        /^[0-9A-F:]+/ { mac=tolower($1); sig=$2; name=(mac in leases)?leases[mac]:"Unknown";
            if(sig < 0) printf "INSERT INTO wifi_roaming_log (hostname, mac_address, ap_ip, interface, signal_dbm, timestamp) VALUES (\"%s\", \"%s\", \"%s\", \"%s\", %d, \"%s\");\n", name, mac, ap, current_if, sig, rtime;
        }' | while read -r sql; do push_sql "$sql"; done
    [ -n "$UPTIME" ] && push_sql "INSERT INTO ap_system_stats (ap_ip, uptime, ram_free_mb, cpu_load, timestamp) VALUES ('$ap', $UPTIME, $RAM, $LOAD, '$RTIME');"
    echo "$ERRORS" | while read -r line; do
        [ -n "$line" ] && push_sql "INSERT INTO ap_error_logs (ap_ip, log_message, priority, timestamp) VALUES ('$ap', \"$(echo $line | sed 's/"/\\"/g')\", 'CRITICAL', '$RTIME');"
    done
done

# 4. ENVIRONMENT SCAN
if [ $MODE_FORCE -eq 1 ] || [ "$(date +%M)" = "05" ]; then
    for ap in $APS; do
        SCAN_CMD="for r in \$(iwinfo | grep 'ESSID' | awk '{print \$1}'); do echo \"IFACE:\$r\"; iwinfo \"\$r\" scan; done"
        if [ "$ap" = "192.168.31.1" ]; then RAW=$(sh -c "$SCAN_CMD" 2>/dev/null); else RAW=$(timeout 40 ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$ap "$SCAN_CMD" 2>/dev/null); fi
        [ -z "$RAW" ] && continue
        echo "$RAW" | awk -v ap_ip="$ap" -v rtime="$RTIME" '
            function p() { if(bssid ~ /:/ && chan > 0) { gsub(/[\\"'\'']/, "", ssid);
                printf "INSERT INTO wifi_scan_results (ap_ip, interface, ssid, bssid, channel, frequency_mhz, signal_dbm, encryption, timestamp) VALUES (\"%s\", \"%s\", \"%s\", \"%s\", %d, %d, %d, \"%s\", \"%s\");\n", ap_ip, iface, ssid, bssid, chan, freq, sig, enc, rtime;
            }}
            /IFACE:/ { split($0, a, ":"); iface=a[2]; next }
            /Cell/ { p(); bssid=$NF; ssid="Unknown"; chan=0; freq=0; sig=0; enc="Unknown" }
            /ESSID:/ { split($0, a, "\""); ssid=a[2] }
            /Encryption:/ { split($0, a, ": "); enc=a[2]; if(enc=="") enc="Open" }
            /Channel:/ && !/Width/ { 
                for(i=1; i<NF; i++) if($i ~ /Channel/) { v=$(i+1); gsub(/[^0-9]/, "", v); chan=v; }
                if (match($0, /[0-9.]+[ ]*[GM]Hz/)) { f_raw = substr($0, RSTART, RLENGTH);
                    if (f_raw ~ /GHz/) { gsub(/[^0-9.]/,"",f_raw); freq=f_raw*1000 } else { gsub(/[^0-9.]/,"",f_raw); freq=f_raw }
                }
            }
            /Signal:/ { sig=$2; sig=int(sig) } END { p() }' | while read -r single_sql; do push_sql "$single_sql"; done
    done
fi

# 5. GATEWAY & SPEEDTEST
WAN_IFACE=$(ip route | awk '/default/ {print $5}' | head -n 1)
if [ -n "$WAN_IFACE" ]; then
    RX=$(cat /sys/class/net/$WAN_IFACE/statistics/rx_bytes 2>/dev/null || echo 0); TX=$(cat /sys/class/net/$WAN_IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print $1/1000}')
    push_sql "INSERT INTO gateway_stats (wan_rx_bytes, wan_tx_bytes, cpu_temp, timestamp) VALUES ($RX, $TX, '$TEMP', '$RTIME');"
fi
if [ $MODE_FORCE -eq 1 ] || [ "$(date +%M)" -lt 02 ]; then
    TEST=$(speedtest-cli --simple 2>/dev/null)
    [ -n "$TEST" ] && push_sql "INSERT INTO speedtests (ping_ms, download_mbit, upload_mbit, timestamp) VALUES ($(echo "$TEST" | awk '/Ping/ {print $2}'), $(echo "$TEST" | awk '/Download/ {print $2}'), $(echo "$TEST" | awk '/Upload/ {print $2}'), '$RTIME');"
fi
push_sql "DELETE FROM client_inventory WHERE mac_address NOT LIKE '%:%';"
