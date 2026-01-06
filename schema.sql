CREATE DATABASE IF NOT EXISTS `router`;
USE `router`;

CREATE TABLE IF NOT EXISTS `arpscan_results` ( `id` INT AUTO_INCREMENT PRIMARY KEY, `timestamp` DATETIME, `ip_address` VARCHAR(45), `mac_address` VARCHAR(17), `vendor` VARCHAR(100) ) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS `client_inventory` ( `mac_address` VARCHAR(17) PRIMARY KEY, `first_seen` DATETIME, `last_seen` DATETIME, `hostname` VARCHAR(100), `ip_address` VARCHAR(45), `ipv6_address` VARCHAR(45), `total_active_minutes` INT DEFAULT 0 ) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS `wifi_roaming_log` ( `id` INT AUTO_INCREMENT PRIMARY KEY, `timestamp` DATETIME, `hostname` VARCHAR(100), `mac_address` VARCHAR(17), `ap_ip` VARCHAR(15), `signal_dbm` INT, `interface` VARCHAR(20), `tx_rate` VARCHAR(20), `rx_rate` VARCHAR(20) ) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS `wifi_scan_results` ( `id` INT AUTO_INCREMENT PRIMARY KEY, `timestamp` DATETIME, `ap_ip` VARCHAR(15), `interface` VARCHAR(20), `ssid` VARCHAR(100), `bssid` VARCHAR(17), `channel` INT, `frequency_mhz` INT, `signal_dbm` INT, `encryption` VARCHAR(100) ) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS `ap_system_stats` ( `id` INT AUTO_INCREMENT PRIMARY KEY, `timestamp` DATETIME, `ap_ip` VARCHAR(15), `uptime` INT, `cpu_load` FLOAT, `ram_free_mb` INT, `mem_buffered_mb` INT, `mem_cached_mb` INT, `disk_total_mb` INT, `disk_used_mb` INT, `arch` VARCHAR(20), `updates_available` INT ) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS `ap_error_logs` ( `id` INT AUTO_INCREMENT PRIMARY KEY, `timestamp` DATETIME, `ap_ip` VARCHAR(15), `priority` VARCHAR(20), `log_message` TEXT ) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS `gateway_stats` ( `id` INT AUTO_INCREMENT PRIMARY KEY, `timestamp` DATETIME, `wan_iface` VARCHAR(20), `wan_rx_bytes` BIGINT, `wan_tx_bytes` BIGINT, `cpu_temp` FLOAT, `load_1min` FLOAT, `load_5min` FLOAT, `load_15min` FLOAT, `wan_ip` VARCHAR(45), `wan_status` VARCHAR(20), `ddns_status` VARCHAR(20), `wan_proto` VARCHAR(20), `wan_gateway` VARCHAR(45) ) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS `speedtests` ( `id` INT AUTO_INCREMENT PRIMARY KEY, `timestamp` DATETIME, `ping_ms` FLOAT, `download_mbit` FLOAT, `upload_mbit` FLOAT ) ENGINE=InnoDB;
