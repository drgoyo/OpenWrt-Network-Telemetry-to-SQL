## OpenWrt Network Telemetry & AP sync
SyncSimple shell scripts for OpenWrt (tested on GL.iNet Flint 3 and openwrt dumb AP) to collect network data into a MariaDB/MySQL database and keep hostnames synchronized across access points.

### ✨ Features📊 

#### TelemetryClient Tracking:Collects client list (IPv4/IPv6) and hostnames.
- Signal Monitoring: Logs client signal strength (dBm) and traffic stats.
- Hardware Health: Records CPU load, RAM usage, and Uptime of all mesh nodes.
- Logs: Aggregates system error logs in a central database.
- Performance: Performs automated speedtests and WAN traffic tracking.WiFi
- Environment: Periodic scans for neighboring networks.

#### 🔄 Hostname Sync
- Centralized Data: Collects hostnames from the primary router (DHCP/UCI).
- Distribution: Syncs a clean host list to all secondary mesh nodes.
- Clean DNS: Validates data to prevent invalid entries in the DNS list.
- Native Integration: Uses OpenWrt's native addnhosts feature.

#### 📂 Repository Files
mesh-to-sql.sh: Main script for data collection.
sync-hosts.sh: Script for hostname distribution.
schema.sql: Database structure.

#### 🛠 Setup

#### 1. Database
Import the schema.sql file into your MariaDB/MySQL server to create the necessary tables.

#### 2. SSH AuthenticationGenerate a key on your main router and copy it to each mesh node for passwordless access:
```bash
#Generate key
ssh-keygen -t rsa -b 2048

#Copy to nodes (replace with your IPs)
cat ~/.ssh/id_rsa.pub | ssh root@192.168.31.2 "mkdir -p /etc/dropbear && cat >> /etc/dropbear/authorized_keys"
cat ~/.ssh/id_rsa.pub | ssh root@192.168.31.3 "mkdir -p /etc/dropbear && cat >> /etc/dropbear/authorized_keys"
cat ~/.ssh/id_rsa.pub | ssh root@192.168.31.4 "mkdir -p /etc/dropbear && cat >> /etc/dropbear/authorized_keys"
```

#### 3. Installation via CurlRun these commands on your primary router to download the scripts and set up symlinks:
```bash
#Download scripts from GitHub
curl -L [https://raw.githubusercontent.com/drgoyo/OpenWrt-Network-Telemetry-to-SQL/main/mesh-to-sql.sh](https://raw.githubusercontent.com/drgoyo/OpenWrt-Network-Telemetry-to-SQL/main/mesh-to-sql.sh) -o /root/mesh-to-sql.sh
curl -L [https://raw.githubusercontent.com/drgoyo/OpenWrt-Network-Telemetry-to-SQL/main/sync-hosts.sh](https://raw.githubusercontent.com/drgoyo/OpenWrt-Network-Telemetry-to-SQL/main/sync-hosts.sh) -o /root/sync-hosts.sh

#Make them executable
chmod +x /root/*.sh

#Create symlinks for easy global access from any directory
ln -s /root/mesh-to-sql.sh /usr/bin/mesh-telemetry
ln -s /root/sync-hosts.sh /usr/bin/mesh-sync
```

#### 4. ConfigurationOpen the scripts and enter your Database Credentials, your AP IP addresses, and verify the SSH Key path:
```bash
nano /root/mesh-to-sql.sh
```
```bash
nano /root/sync-hosts.sh
```
#### 5. Automation (Cron)Add these lines to your crontab via crontab -e to automate the suite:
```bash
#Sync hostnames every hour
0 * * * * /usr/bin/mesh-sync > /dev/null 2>&1
#Collect telemetry every 2 minutes
*/2 * * * * /usr/bin/mesh-telemetry > /dev/null 2>&1
```

#### 6. 📊 Debug & Manual UsageRun the scripts manually to see live output or force specific tasks:
```bash
#Trigger immediate neighborhood scan/speedtest and show SQL commands
mesh-telemetry force-all debug
#Debug hostname synchronization
mesh-sync debug
```

#### 7. 🔍 SQL Quick-ChecksMonitor your data directly in the MariaDB console:

##### System Health (Latest values)
```bash
SELECT ap_ip, uptime, cpu_load, ram_free_mb, timestamp 
FROM ap_system_stats 
WHERE (ap_ip, timestamp) IN (
    SELECT ap_ip, MAX(timestamp) 
    FROM ap_system_stats 
    GROUP BY ap_ip
);
```

##### WAN Status
```bash
SELECT timestamp, wan_ip, wan_proto, cpu_temp, wan_rx_bytes, wan_tx_bytes 
FROM gateway_stats 
ORDER BY timestamp DESC 
LIMIT 1;
```

##### Active WiFi Clients
```bash
SELECT i.hostname, r.ap_ip AS 'AP', r.signal_dbm AS 'Signal', i.ip_address, r.timestamp
FROM wifi_roaming_log r
JOIN client_inventory i ON r.mac_address = i.mac_address
WHERE r.timestamp > NOW() - INTERVAL 10 MINUTE
ORDER BY r.signal_dbm DESC;
```
##### Recent Speedtests
```bash
SELECT timestamp, download_mbit, upload_mbit, ping_ms 
FROM speedtests 
ORDER BY timestamp DESC 
LIMIT 3;
```
