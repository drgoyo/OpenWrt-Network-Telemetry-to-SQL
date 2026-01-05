#!/bin/sh
# =================================================================
# ULTIMATE NETWORK GUARD - OpenWrt Mesh Monitoring & Audit
# =================================================================
# Description: Collects Network Inventory, WiFi Roaming Events, 
#              WAN Traffic and Environment Scans across multiple 
#              OpenWrt Access Points and pushes them to MariaDB.
# =================================================================

# --- CONFIGURATION (PLEASE ADAPT) ---
TARGET_IP="YOUR_DATABASE_IP"        # e.g. 192.168.31.10
TARGET_PORT="3306"
DB_USER="YOUR_DB_USER"              # e.g. user
DB_PASS="YOUR_DB_PASSWORD"
DB_NAME="router"
# List all your Access Points (Space separated)
APS="192.168.31.1 192.168.31.2 192.168.31.3 192.168.31.4"
LEASES="/tmp/dhcp.leases"
SSH_KEY="/root/.ssh/id_rsa"
# ------------------------------------

push_sql() {
    [ -z "$1" ] && return
    # Sends SQL queries line-by-line for maximum stability
    echo "$1" | mariadb -h $TARGET_IP -P $TARGET_PORT -u$DB_USER -p$DB_PASS $DB_NAME 2>/dev/null
}

# --- 1. NETWORK INVENTORY & ACTIVITY ---
# Captures every communicating device (LAN/WLAN) via Kernel neighbor table
echo "Step 1: Updating Inventory..."
NEIGHBORS=$(ip neigh show dev br-lan | grep "lladdr" | awk '{ip=$1; mac=""; for(i=1;i<=NF;i++) if($i=="lladdr") mac=$(i+1); if(mac ~ /:/) print ip"|"mac}')

for entry in $NEIGHBORS; do
    IP=$(echo "$entry" | cut -d'|' -f1)
    MAC=$(echo "$entry" | cut -d'|' -f2 | tr '[:upper:]' '[:lower:]')
    [ -z "$MAC" ] && continue
    
    # Resolve hostname from DHCP leases
    NAME=$(grep -i "$MAC" $LEASES | awk '{print $4}' | head -n 1)
    [ -z "$NAME" ] || [ "$NAME" = "*" ] && NAME="Unknown"
    
    # Upsert: Update last seen and increment active time (based on 2-min cron)
    push_sql "INSERT INTO client_inventory (mac_address, hostname, first_seen, last_seen, total_active_minutes) \
              VALUES ('$MAC', '$NAME', NOW(), NOW(), 2) \
              ON DUPLICATE KEY UPDATE last_seen=NOW(), hostname='$NAME', total_active_minutes=total_active_minutes+2;"
    
    # Log ARP history for network auditing
    push_sql "INSERT INTO arp_scan_results (ip_address, mac_address, vendor) VALUES ('$IP', '$MAC', 'Kernel-Detected');"
done

# --- 2. LIVE WIFI ROAMING (iwinfo) ---
# Tracks which client is connected to which AP and logs signal strength
echo "Step 2: Capturing Roaming Events..."
for ap in $APS; do
    STATIONS=""
    if [ "$ap" = "192.168.31.1" ]; then
        # Local AP: Scan all active wireless interfaces
        for iface in $(iwinfo | grep "ESSID" | awk '{print $1}'); do STATIONS="$STATIONS $(iwinfo $iface assoclist)"; done
    else
        # Remote APs via SSH
        STATIONS=$(ssh -i $SSH_KEY -T -y root@$ap "for iface in \$(iwinfo | grep 'ESSID' | awk '{print \$1}'); do iwinfo \$iface assoclist; done" 2>/dev/null)
    fi
    [ -z "$STATIONS" ] && continue

    echo "$STATIONS" | awk -v ap="$ap" -v lease_file="$LEASES" '
        BEGIN { while ((getline < lease_file) > 0) { leases[tolower($2)] = $4 } }
        /^[0-9A-F:]+/ { 
            mac=tolower($1); sig=$2;
            name = (mac in leases) ? leases[mac] : "Unknown";
            if(mac ~ /:/) printf "INSERT INTO wifi_roaming_log (hostname, mac_address, ap_ip, signal_dbm) VALUES (\"%s\", \"%s\", \"%s\", %d);\n", name, mac, ap, sig;
        }' | while read -r sql; do push_sql "$sql"; done
done

# --- 3. WAN TRAFFIC & SYSTEM HEALTH ---
# Monitors bandwidth consumption and hardware temperature
echo "Step 3: Collecting System Metrics..."
WAN_IFACE=$(ip route | awk '/default/ {print $5}' | head -n 1)
if [ -n "$WAN_IFACE" ]; then
    RX=$(cat /sys/class/net/$WAN_IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
    TX=$(cat /sys/class/net/$WAN_IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print $1/1000}')
    push_sql "INSERT INTO gateway_stats (wan_rx_bytes, wan_tx_bytes, cpu_temp) VALUES ($RX, $TX, '$TEMP');"
fi

# --- 4. WIFI ENVIRONMENT SCAN (Heatmap) ---
# Performs a full site survey. Scheduled daily or via 'force-scan' argument.
if [ "$1" = "force-scan" ] || [ "$(date +%H%M)" = "0400" ]; then
    echo "Step 4: Scanning WiFi Environment..."
    for ap in $APS; do
        SCAN_RAW=""
        if [ "$ap" = "192.168.31.1" ]; then
            # Local: Scan all interfaces to capture all bands (2.4/5/6GHz)
            for iface in $(iwinfo | grep "ESSID" | awk '{print $1}'); do 
                SCAN_RAW="$SCAN_RAW $(iwinfo $iface scan 2>/dev/null)"
            done
        else
            # Remote scan
            SCAN_RAW=$(ssh -i $SSH_KEY -T -y root@$ap "iwinfo wlan0 scan" 2>/dev/null)
        fi
        [ -z "$SCAN_RAW" ] && continue

        # Robust iwinfo parser
        echo "$SCAN_RAW" | awk -v ap_ip="$ap" '
            function p() {
                if (chan > 0 && bssid ~ /:/) {
                    gsub(/'\''/, "", ssid); # Sanitize SSIDs for SQL
                    printf "INSERT INTO wifi_scan_results (ap_ip, ssid, bssid, channel, signal_dbm) VALUES (\"%s\", \"%s\", \"%s\", %d, %d);\n", ap_ip, ssid, bssid, chan, sig;
                }
            }
            /Cell/ { p(); bssid=$NF; ssid="Unknown"; chan=0; sig=0; }
            /ESSID:/ { split($0, a, "\""); ssid=a[2]; if(ssid=="") ssid="Hidden"; }
            /Channel:|Primary Channel:/ { for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) chan=$i; }
            /Signal:/ { sig=$2; sig=int(sig); }
            END { p(); }
        ' | while read -r single_query; do push_sql "$single_query"; done
    done
fi

# Maintenance: Cleanup IPv6 ghost entries
push_sql "DELETE FROM client_inventory WHERE mac_address NOT LIKE '%:%';"

echo "Done!"
EOF
