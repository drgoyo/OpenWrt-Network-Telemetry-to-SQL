#!/bin/sh
# =================================================================
# OPENWRT HOST SYNC - Generic Version (Supports up to 4+ APs)
# =================================================================
# Dieses Script sammelt Hostnamen vom Haupt-Router und verteilt sie 
# an die Access Points im Mesh, damit das gesamte Netzwerk die 
# gleichen Namen für alle Geräte verwendet.
# =================================================================

# --- KONFIGURATION ---
# Liste der IP-Adressen deiner Access Points (durch Leerzeichen getrennt)
APS="192.168.1.2 192.168.1.3 192.168.1.4 192.168.1.5" 

# Pfad zu deinem privaten SSH-Schlüssel (Standard für OpenWrt)
KEY="/root/.ssh/id_rsa"

# Speicherort der temporären Datei
TEMP_HOSTS="/tmp/shared_hosts"

# --- ARGUMENT PARSING ---
MODE_DEBUG=0
for arg in "$@"; do
    [ "$arg" = "debug" ] && MODE_DEBUG=1
done

log() { [ $MODE_DEBUG -eq 1 ] && echo -e "\033[1;34m[DEBUG]\033[0m $1"; }
error_log() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

# --- 1. HOSTNAMEN SAMMELN & VALIDIEREN ---
log "Sammle Hostnamen von DHCP-Leases und UCI-Config..."
echo "# Zentral generierte Hosts - $(date)" > $TEMP_HOSTS.raw

# A. Dynamische Leases (aus dem RAM)
if [ -f /tmp/dhcp.leases ]; then
    awk '{if($3 != "" && $4 != "*" && $4 != "") print $3, $4}' /tmp/dhcp.leases >> $TEMP_HOSTS.raw
fi

# B. Statische Leases (aus der permanenten UCI-Konfiguration)
uci -q show dhcp | grep "=host" | cut -d. -f2 | while read -r section; do
    name=$(uci -q get dhcp.$section.name)
    ip=$(uci -q get dhcp.$section.ip)
    [ -n "$ip" ] && [ -n "$name" ] && echo "$ip $name" >> $TEMP_HOSTS.raw
done

# C. VALIDIERUNG: Nur saubere IP-Hostname Paare zulassen
# Filtert IPv4, IPv6 und verhindert, dass Fehlermeldungen in die Datei gelangen.
log "Filtere ungültige Einträge und Error-Logs aus..."
grep -E '^([0-9\.]+|[0-9a-fA-F:]+) [a-zA-Z0-9_-]+$' $TEMP_HOSTS.raw | sort -u > $TEMP_HOSTS
rm $TEMP_HOSTS.raw

if [ $MODE_DEBUG -eq 1 ]; then
    log "Finaler Inhalt der Hosts-Datei:"
    cat $TEMP_HOSTS
fi

# --- 2. VERTEILEN AN MESH-NODES ---
for ap in $APS; do
    log "Synchronisiere AP $ap..."
    
    # SCP Kopie (nutzt -y um Host-Keys automatisch zu akzeptieren - Dropbear kompatibel)
    if scp -i $KEY -q -y $TEMP_HOSTS root@$ap:/etc/hosts.shared; then
        log "Datei erfolgreich nach $ap kopiert."
    else
        error_log "Konnte Datei nicht nach $ap kopieren (Node offline oder Key-Problem)."
        continue
    fi

    # Remote-Konfiguration auf dem AP:
    # Registriert die Datei über das native 'addnhosts' Feature von OpenWrt/DNSMasq
    ssh -i $KEY -T -y root@$ap << 'SSH_EOF' >/dev/null 2>&1
        if ! uci get dhcp.@dnsmasq[0].addnhosts | grep -q "/etc/hosts.shared"; then
            uci add_list dhcp.@dnsmasq[0].addnhosts='/etc/hosts.shared'
            uci commit dhcp
        fi
        /etc/init.d/dnsmasq restart
SSH_EOF
    
    [ $? -eq 0 ] && log "\033[1;32mAP $ap erfolgreich aktualisiert.\033[0m" || error_log "Fehler beim Neustart von DNSMasq auf $ap."
done

log "Sync-Vorgang beendet."
