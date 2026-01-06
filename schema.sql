CREATE DATABASE IF NOT EXISTS network_stats;
USE network_stats;

-- 1. Geräte-Inventar
CREATE TABLE client_inventory (
    mac_address VARCHAR(17) PRIMARY KEY,
    hostname VARCHAR(100),
    ip_address VARCHAR(45),
    ipv6_address VARCHAR(45),
    last_seen DATETIME,
    total_active_minutes INT DEFAULT 0
);

-- 2. WLAN Roaming & Signal-Log
CREATE TABLE wifi_roaming_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    hostname VARCHAR(100),
    mac_address VARCHAR(17),
    ap_ip VARCHAR(15),
    signal_dbm INT,
    tx_bytes BIGINT DEFAULT 0,
    rx_bytes BIGINT DEFAULT 0
);

-- 3. AP System-Status (CPU/RAM)
CREATE TABLE ap_system_stats (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ap_ip VARCHAR(15),
    uptime INT,
    ram_free_mb INT,
    cpu_load FLOAT
);

-- 4. AP Fehler-Logs
CREATE TABLE ap_error_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ap_ip VARCHAR(15),
    log_message TEXT,
    priority VARCHAR(20)
);

-- 5. WLAN Umgebungsscan (Nachbarn)
CREATE TABLE wifi_scan_results (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ap_ip VARCHAR(15),
    interface VARCHAR(20),
    ssid VARCHAR(100),
    bssid VARCHAR(17),
    channel INT,
    frequency_mhz INT,
    signal_dbm INT,
    encryption VARCHAR(100)
);

-- 6. WAN Metrics
CREATE TABLE gateway_stats (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    wan_rx_bytes BIGINT,
    wan_tx_bytes BIGINT,
    cpu_temp FLOAT
);

-- 7. Speedtests
CREATE TABLE speedtests (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ping_ms FLOAT,
    download_mbit FLOAT,
    upload_mbit FLOAT
);

-- Indizes für schnellere Abfragen
CREATE INDEX idx_roaming_mac ON wifi_roaming_log(mac_address);
CREATE INDEX idx_scan_freq ON wifi_scan_results(frequency_mhz);
CREATE INDEX idx_error_ap ON ap_error_logs(ap_ip);
