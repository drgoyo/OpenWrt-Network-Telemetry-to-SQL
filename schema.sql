-- OpenWrt Network Telemetry - MariaDB Schema
CREATE DATABASE IF NOT EXISTS `router`;
USE `router`;

-- 1. Raw ARP Scan Results
CREATE TABLE IF NOT EXISTS `arpscan_results` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `timestamp` DATETIME,
    `ip_address` VARCHAR(45),
    `mac_address` VARCHAR(17),
    `vendor` VARCHAR(100) DEFAULT '(Unknown)'
) ENGINE=InnoDB;

-- 2. Persistent Client Inventory
CREATE TABLE IF NOT EXISTS `client_inventory` (
    `mac_address` VARCHAR(17) PRIMARY KEY,
    `hostname` VARCHAR(100),
    `ip_address` VARCHAR(45),
    `ipv6_address` VARCHAR(45),
    `last_seen` DATETIME,
    `total_active_minutes` INT DEFAULT 0
) ENGINE=InnoDB;

-- 3. WiFi Roaming and Signal Log
CREATE TABLE IF NOT EXISTS `wifi_roaming_log` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `timestamp` DATETIME,
    `hostname` VARCHAR(100),
    `mac_address` VARCHAR(17),
    `ap_ip` VARCHAR(15),
    `interface` VARCHAR(10),
    `signal_dbm` INT,
    INDEX (`timestamp`),
    INDEX (`mac_address`)
) ENGINE=InnoDB;

-- 4. WiFi Environment Scan (Neighboring Networks)
CREATE TABLE IF NOT EXISTS `wifi_scan_results` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `timestamp` DATETIME,
    `ap_ip` VARCHAR(15),
    `interface` VARCHAR(20),
    `ssid` VARCHAR(100),
    `bssid` VARCHAR(17),
    `channel` INT,
    `frequency_mhz` INT,
    `signal_dbm` INT,
    `encryption` VARCHAR(100)
) ENGINE=InnoDB;

-- 5. Access Point System Health
CREATE TABLE IF NOT EXISTS `ap_system_stats` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `timestamp` DATETIME,
    `ap_ip` VARCHAR(15),
    `uptime` INT,
    `ram_free_mb` INT,
    `cpu_load` FLOAT
) ENGINE=InnoDB;

-- 6. Access Point Error Logs
CREATE TABLE IF NOT EXISTS `ap_error_logs` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `timestamp` DATETIME,
    `ap_ip` VARCHAR(15),
    `log_message` TEXT,
    `priority` VARCHAR(20)
) ENGINE=InnoDB;

-- 7. Gateway WAN Metrics
CREATE TABLE IF NOT EXISTS `gateway_stats` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `timestamp` DATETIME,
    `wan_rx_bytes` BIGINT,
    `wan_tx_bytes` BIGINT,
    `cpu_temp` FLOAT
) ENGINE=InnoDB;

-- 8. Internet Speedtests
CREATE TABLE IF NOT EXISTS `speedtests` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `timestamp` DATETIME,
    `ping_ms` FLOAT,
    `download_mbit` FLOAT,
    `upload_mbit` FLOAT
) ENGINE=InnoDB;
