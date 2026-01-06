# OpenWrt Network Telemetry to SQL

A powerful, lightweight telemetry collector for OpenWrt (optimized for GL.iNet Flint 3 & Xiaomi Mesh). It aggregates metrics from multiple Access Points and pushes them to a central MariaDB/MySQL database.

## ✨ Key Features
- **Dual-Stack Inventory**: Tracks IPv4 & IPv6 devices with hostnames and activity time.
- **Deep Roaming Logs**: Monitors client signal strength (dBm) and traffic per AP.
- **NOC Monitoring**: Real-time CPU load, Uptime, and RAM stats for all Mesh nodes.
- **Error Logging**: Captures critical system logs (`logread`) across the mesh.
- **Performance**: Automated hourly speedtests and WAN traffic tracking.
- **Environment Scan**: Full site survey of neighboring WiFis for channel optimization.

## 📁 Repository Files
- `mesh-to-sql.sh`: The main collector script for the router.
- `schema.sql`: Database structure to set up your MariaDB/MySQL server.

## 🚀 Setup
1. **Database**: Run the `schema.sql` file on your MariaDB server to create the database and tables.
2. **SSH Auth**: Ensure the main router can log into mesh nodes via SSH keys (using Dropbear).
3. **Script**: Upload `mesh-to-sql.sh` to `/root/`, configure your database credentials inside the script, and run `chmod +x /root/mesh-to-sql.sh`.
4. **Cron**: Add the following line to your crontab (`crontab -e`) to run every 2 minutes:
   ```bash
   */2 * * * * /root/mesh-to-sql.sh > /dev/null 2>&1

📊 Debug & Manual Usage
Use arguments to trigger specific actions or see what happens:
force-all: Triggers an immediate neighborhood scan and speedtest (otherwise scheduled).
debug: Shows the results and SQL commands directly in the console.

Example command:
/root/mesh-to-sql.sh force-all debug

🔍 SQL Quick-Checks
You can monitor your data directly in the MariaDB console with these commands:

1. System Health of all mesh nodes (latest values)
SELECT ap_ip, uptime, cpu_load, ram_free_mb, timestamp 
FROM ap_system_stats 
WHERE (ap_ip, timestamp) IN (SELECT ap_ip, MAX(timestamp) FROM ap_system_stats GROUP BY ap_ip);

2. WAN & Internet Status (Current IP and traffic)
SELECT timestamp, wan_ip, wan_proto, cpu_temp, wan_rx_bytes, wan_tx_bytes 
FROM gateway_stats 
ORDER BY timestamp DESC LIMIT 1;

3. Active WiFi Clients (Combined Inventory & Roaming)
SELECT i.hostname, r.ap_ip AS 'AP', r.signal_dbm AS 'Signal', i.ip_address, r.timestamp
FROM wifi_roaming_log r
JOIN client_inventory i ON r.mac_address = i.mac_address
WHERE r.timestamp > NOW() - INTERVAL 10 MINUTE
ORDER BY r.signal_dbm DESC;

4. Recent Speedtests
SELECT timestamp, download_mbit, upload_mbit, ping_ms 
FROM speedtests 
ORDER BY timestamp DESC LIMIT 3;

5. Last 5 Critical Errors
SELECT timestamp, ap_ip, log_message 
FROM ap_error_logs 
ORDER BY timestamp DESC LIMIT 5;
