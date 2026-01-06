CREATE DATABASE IF NOT EXISTS router;
USE router;

-- 1. Geräte-Inventar (Dual-Stack IPv4 & IPv6)
CREATE TABLE client_inventory (
    mac_address VARCHAR(17) PRIMARY KEY,
    hostname VARCHAR(100),
    ip_address VARCHAR(45),
    ipv6_address VARCHAR(45),
    first_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_seen DATETIME,
    total_active_minutes INT DEFAULT 0
);

-- 2. Roaming & Performance Log (Echtzeit-Verbindungen)
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

-- 3. System-Statistiken der Mesh-Knoten (Wichtig: uptime als INT!)
CREATE TABLE ap_system_stats (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ap_ip VARCHAR(15),
    uptime INT, -- Sekunden als Ganzzahl für Berechnungen
    cpu_load FLOAT,
    ram_free_mb INT
);

-- 4. Zentrale Fehler-Logs
CREATE TABLE ap_error_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ap_ip VARCHAR(15),
    log_message TEXT,
    priority VARCHAR(20) DEFAULT 'CRITICAL'
);

-- 5. Gateway Metriken (WAN Status & IP)
CREATE TABLE gateway_stats (
    id INT AUTO_INCREMENT PRIMARY KEY, -- ID hinzugefügt für bessere DB-Pflege
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    wan_rx_bytes BIGINT,
    wan_tx_bytes BIGINT,
    cpu_temp DECIMAL(5,2),
    wan_ip VARCHAR(45),
    wan_proto VARCHAR(20)
);

-- 6. Internet Speedtests (ping_ms statt nur ping)
CREATE TABLE speedtests (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ping_ms DECIMAL(10,2),
    download_mbit DECIMAL(10,2),
    upload_mbit DECIMAL(10,2)
);

-- 7. WLAN Umgebungs-Scan (Nachbarnetze)
CREATE TABLE wifi_scan_results (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ap_ip VARCHAR(15),
    ssid VARCHAR(100),
    bssid VARCHAR(17),
    channel INT,
    signal_dbm INT
);
