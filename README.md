# OpenWrt Network Telemetry to SQL

A lightweight shell script for **OpenWrt routers** (optimized for GL.iNet Flint 3 / Wi-Fi 7) that aggregates network telemetry from multiple Mesh nodes and pushes it to a central **MariaDB/MySQL** database.



## ✨ Features
* **Device Inventory**: Tracks MAC addresses and hostnames with `first_seen` and cumulative `active_minutes`.
* **Roaming Logs**: Real-time tracking of client signal strength (dBm) and AP transitions across the Mesh.
* **Traffic & Health**: Logs total WAN data consumption (RX/TX) and router CPU temperature.
* **Site Survey**: Automates nightly WiFi environment scans to monitor channel congestion and neighboring networks.



## 🛠️ Requirements
* **Primary Router**: OpenWrt with `mariadb-client` and `iwinfo` installed.
* **AP**: SSH access with key-based authentication from the primary router.
* **Database**: A MariaDB or MySQL instance (e.g., Docker on Unraid/NAS).

---

### 1. Database Setup
Execute the following SQL commands to initialize your database schema:

```sql
CREATE DATABASE IF NOT EXISTS router;
USE router;

CREATE TABLE client_inventory (
    mac_address VARCHAR(17) PRIMARY KEY,
    hostname VARCHAR(100),
    first_seen DATETIME,
    last_seen DATETIME,
    total_active_minutes INT DEFAULT 0
);

CREATE TABLE wifi_roaming_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    hostname VARCHAR(100),
    mac_address VARCHAR(17),
    ap_ip VARCHAR(15),
    signal_dbm INT,
    tx_bytes BIGINT,
    rx_bytes BIGINT
);

CREATE TABLE gateway_stats (
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    wan_rx_bytes BIGINT,
    wan_tx_bytes BIGINT,
    cpu_temp DECIMAL(5,2),
    wan_ip VARCHAR(45)
);

CREATE TABLE wifi_scan_results (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ap_ip VARCHAR(15),
    ssid VARCHAR(100),
    bssid VARCHAR(17),
    channel INT,
    signal_dbm INT
);
