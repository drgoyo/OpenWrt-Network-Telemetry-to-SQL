cat << 'EOF' > /root/mesh-to-sql.sh
#!/bin/sh
# =================================================================
# OPENWRT NETWORK TELEMETRY - v3.0 (Tri-Band & Frequency Support)
# =================================================================

# --- CONFIGURATION ---
TARGET_IP="YOUR_DB_IP"
TARGET_PORT="3306"
DB_USER="YOUR_DB_USER"
DB_PASS="YOUR_DB_PASSWORD"
DB_NAME="router"
APS="192.168.31.1 192.168.31.2 192.168.31.3 192.168.31.4"
LEASES="/tmp/dhcp.leases"
SSH_KEY="/root/.ssh/id_rsa"

MODE_FORCE=0
MODE_DEBUG=0
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

# --- 1. NETWORK INVENTORY ---
log "Step 1: Inventory Update..."
NEIGHBORS=$(ip neigh show dev br-lan | grep "lladdr" | awk '{ip=$1; mac=""; for(i=1;i<=NF;i++) if($i=="lladdr") mac=$(i+1); if(mac ~ /:/) print ip"|"mac}')
for entry in $NEIGHBORS; do
    IP=$(echo "$entry" | cut -d'|' -f1); MAC=$(echo "$entry" | cut -d'|' -f2 | tr '[:upper:]' '[:lower:]')
    [ -z "$MAC" ] && continue
    NAME=$(grep -i "$MAC" $LEASES | awk '{print $4}' | head -n 1)
    [ -z "$NAME" ] || [ "$NAME" = "*" ] && NAME="Unknown"
    COL="ip_address"; echo "$IP" | grep -q ":" && COL="ipv6_address"
    push_sql "INSERT INTO client_inventory (mac_address, hostname, $COL, last_seen, total_active_minutes) VALUES ('$MAC', '$NAME', '$IP', NOW(), 2) ON DUPLICATE KEY UPDATE last_seen=NOW(), hostname='$NAME', $COL='$IP', total_active_minutes=total_active_minutes+2;"
done

# --- 2. AP DIAGNOSTICS & DEEP ROAMING ---
log "Step 2: AP Diagnostics & System Health..."
for ap in $APS; do
    log "Checking AP: $ap"
    if [ "$ap" = "192.168.31.1" ]; then
        WIFI_DATA=$(for iface in $(iwinfo | grep "ESSID" | awk '{print $1}'); do iwinfo "$iface" assoclist 2>/dev/null; done)
        UPTIME=$(cat /proc/uptime | awk '{print int($1)}'); RAM=$(free -m | grep Mem | awk '{print $4}'); LOAD=$(cat /proc/loadavg | awk '{print $1}')
        ERRORS=$(logread | grep -E "err|crit|alert|emerg" | tail -n 5)
    else
        CMD="for if in \$(iwinfo | grep 'ESSID' | awk '{print \$1}'); do iwinfo \$if assoclist; done; echo '---'; cat /proc/uptime; echo '---'; free -m | grep Mem | awk '{print \$4}'; echo '---'; cat /proc/loadavg; echo '---'; logread | grep -E 'err|crit|alert|emerg' | tail -n 5"
        REMOTE_DATA=$(ssh -i $SSH_KEY -T -y root@$ap "$CMD" 2>/dev/null)
        [ -z "$REMOTE_DATA" ] && continue
        WIFI_DATA=$(echo "$REMOTE_DATA" | awk 'BEGIN{RS="---"} NR==1 {print}')
        UPTIME=$(echo "$REMOTE_DATA" | awk 'BEGIN{RS="---"} NR==2 {print int($1)}'); RAM=$(echo "$REMOTE_DATA" | awk 'BEGIN{RS="---"} NR==3 {print $1}'); LOAD=$(echo "$REMOTE_DATA" | awk 'BEGIN{RS="---"} NR==4 {print $1}'); ERRORS=$(echo "$REMOTE_DATA" | awk 'BEGIN{RS="---"} NR==5 {print}')
    fi

    echo "$WIFI_DATA" | awk -v ap="$ap" -v lease_file="$LEASES" '
        BEGIN { while ((getline < lease_file) > 0) { leases[tolower($2)] = $4 } }
        /^[0-9A-F:]+/ { 
            mac=tolower($1); sig=$2; tx_b=($3 ~ /^[0-9]+$/)?$3:0; rx_b=($4 ~ /^[0-9]+$/)?$4:0;
            name=(mac in leases)?leases[mac]:"Unknown";
            if(mac ~ /:/) printf "INSERT INTO wifi_roaming_log (hostname, mac_address, ap_ip, signal_dbm, tx_bytes, rx_bytes) VALUES (\"%s\", \"%s\", \"%s\", %d, %d, %d);\n", name, mac, ap, sig, tx_b, rx_b;
        }' | while read -r sql; do push_sql "$sql"; done

    [ -n "$UPTIME" ] && push_sql "INSERT INTO ap_system_stats (ap_ip, uptime, ram_free_mb, cpu_load) VALUES ('$ap', $UPTIME, $RAM, $LOAD);"

    echo "$ERRORS" | while read -r line; do
        [ -z "$line" ] && continue
        CLEAN_LOG=$(echo "$line" | sed "s/['\"]//g")
        push_sql "INSERT INTO ap_error_logs (ap_ip, log_message, priority) VALUES ('$ap', '$CLEAN_LOG', 'CRITICAL');"
    done
done

# --- 3. WIFI ENVIRONMENT SCAN (REVISED) ---
if [ $MODE_FORCE -eq 1 ] || [ "$(date +%H%M)" = "0400" ]; then
    log "Step 3: WiFi Environment Scan..."
    for ap in $APS; do
        log "Scanning Environment from $ap..."
        # Wir erfassen das Interface im CMD, um es an AWK zu übergeben
        if [ "$ap" = "192.168.31.1" ]; then
             SCAN_RAW=$(for r in $(iwinfo | grep "ESSID" | awk '{print $1}'); do echo "IFACE:$r"; iwinfo $r scan; done)
        else
             SCAN_RAW=$(ssh -i $SSH_KEY -T -y root@$ap "for r in \$(iwinfo | grep 'ESSID' | awk '{print \$1}'); do echo \"IFACE:\$r\"; iwinfo \$r scan; done" 2>/dev/null)
        fi
        
        [ -z "$SCAN_RAW" ] && continue

        echo "$SCAN_RAW" | awk -v ap_ip="$ap" '
            function p() { 
                if (chan > 0 && bssid ~ /:/) { 
                    gsub(/[\\"'\'']/, "", ssid); 
                    printf "INSERT INTO wifi_scan_results (ap_ip, interface, ssid, bssid, channel, frequency_mhz, signal_dbm, encryption) VALUES (\"%s\", \"%s\", \"%s\", \"%s\", %d, %d, %d, \"%s\");\n", ap_ip, iface, ssid, bssid, chan, freq, sig, enc; 
                } 
            }
            /^IFACE:/ { split($0, a, ":"); iface=a[2]; next; }
            /Cell/ { p(); bssid=$NF; ssid="Unknown"; chan=0; sig=0; freq=0; enc="Open"; }
            /ESSID:/ { split($0, a, "\""); ssid=a[2]; if(ssid=="") ssid="Hidden"; }
            /Channel:|Primary Channel:/ { 
                for(i=1;i<=NF;i++) {
                    if($i ~ /^[0-9]+$/) chan=$i;
                    if($i ~ /^\([0-9.]+\)$/) { freq=substr($i, 2, length($i)-2) * 1000; }
                }
            }
            /Signal:/ { sig=$2; sig=int(sig); }
            /Encryption:/ { split($0, a, ": "); enc=a[2]; }
            END { p(); }' | while read -r single_sql; do push_sql "$single_sql"; done
    done
fi

# --- 4. WAN & HEALTH ---
log "Step 4: WAN Metrics..."
WAN_IFACE=$(ip route | awk '/default/ {print $5}' | head -n 1)
if [ -n "$WAN_IFACE" ]; then
    RX=$(cat /sys/class/net/$WAN_IFACE/statistics/rx_bytes 2>/dev/null || echo 0); TX=$(cat /sys/class/net/$WAN_IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print $1/1000}')
    W_DATA=$(ifstatus wan); W_IP=$(echo "$W_DATA" | jsonfilter -e '@["ipv4-address"][0].address'); W_PROTO=$(echo "$W_DATA" | jsonfilter -e '@.proto')
    push_sql "INSERT INTO gateway_stats (wan_rx_bytes, wan_tx_bytes, cpu_temp, wan_ip, wan_proto) VALUES ($RX, $TX, '$TEMP', '$W_IP', '$W_PROTO');"
fi

# --- 5. SPEEDTEST ---
if [ $MODE_FORCE -eq 1 ] || [ "$(date +%M)" -lt 02 ]; then
    log "Step 5: Speedtest..."
    TEST_DATA=$(speedtest-cli --simple 2>/dev/null)
    if [ -n "$TEST_DATA" ]; then
        PING=$(echo "$TEST_DATA" | awk '/Ping/ {print $2}'); DOWN=$(echo "$TEST_DATA" | awk '/Download/ {print $2}'); UP=$(echo "$TEST_DATA" | awk '/Upload/ {print $2}')
        push_sql "INSERT INTO speedtests (ping_ms, download_mbit, upload_mbit) VALUES ($PING, $DOWN, $UP);"
    fi
fi
push_sql "DELETE FROM client_inventory WHERE mac_address NOT LIKE '%:%';"
log "All Steps Completed."
EOF
chmod +x /root/mesh-to-sql.sh
