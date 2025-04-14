#!/bin/bash

[ "$UID" -eq 0 ] || exec sudo "$0" "$@"

# Función de log
log_msg() {
    local type="$1"
    local msg="$2"
    local reset="\033[0m"
    local timestamp=$(date '+%H:%M:%S')

    case "$type" in
        log)    color="\033[1;37m[LOG]";;
        info)   color="\033[1;34m[INFO]";;
        success)color="\033[1;32m[SUCCESS]";;
        warning)color="\033[1;33m[WARNING]";;
        error)  color="\033[1;31m[ERROR]";;
        *)      color="\033[0m[UNKNOWN]";;
    esac

    echo -e "${color} ${timestamp} - ${msg}${reset}"
}

# Función de ayuda
function help() {
    echo "Uso: $0 [opciones]"
    echo ""
    echo "Opciones:"
    echo "  --interface=IFACE        Interfaz inalámbrica (por defecto: wlan0)"
    echo "  --portal-name=NOMBRE     Nombre del portal/SSID (por defecto: PortalCautivo)"
    echo "  --ip-address=IP          Dirección IP del punto de acceso (por defecto: 192.168.10.1)"
    echo "  --dhcp-range=RANGO       Rango DHCP (por defecto: 192.168.10.10,192.168.10.50)"
    echo "  --help                   Muestra esta ayuda y termina"
    exit 0
}

# Comprobación de root
if [ "$EUID" -ne 0 ]; then
    log_msg error "Este script debe ejecutarse como root."
    help
    exit 1
fi

# Valores por defecto
interface="wlan0"
portal_name="PortalCautivo"
ip_address="192.168.10.1"
dhcp_range="192.168.10.10,192.168.10.50"

# Parseo de argumentos tipo --arg=valor
for arg in "$@"; do
    case $arg in
        --interface=*)
            interface="${arg#*=}"
            ;;
        --portal-name=*)
            portal_name="${arg#*=}"
            ;;
        --ip-address=*)
            ip_address="${arg#*=}"
            ;;
        --dhcp-range=*)
            dhcp_range="${arg#*=}"
            ;;
        --help)
            help
            ;;
        *)
            log_msg error "Opción desconocida: $arg"
            echo "Usa --help para ver las opciones disponibles."
            exit 1
            ;;
    esac
done

log_msg info "Interfaz: $interface"
log_msg info "Portal: $portal_name"
log_msg info "IP del portal: $ip_address"
log_msg info "Rango DHCP: $dhcp_range"

# Comprobaciones previas
if ! command -v nmcli &> /dev/null; then
    log_msg error "nmcli no está instalado. Ejecuta: sudo apt install network-manager"
    exit 1
fi

# Instalación de paquetes necesarios
log_msg info "Instalando paquetes necesarios..."
apt update -qq && apt install -y hostapd dnsmasq apache2 php php-cgi iptables openssl > /dev/null 2>&1 || {
    log_msg error "Error durante la instalación de paquetes."
    exit 1
}
log_msg success "Paquetes instalados correctamente."

# Configuración de hostapd
log_msg info "Generando configuración de hostapd..."
cat <<EOF > hostapd.conf
interface=$interface
driver=nl80211
ssid=$portal_name
hw_mode=g
channel=6
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
EOF

# Configuración de dnsmasq
log_msg info "Generando configuración de dnsmasq..."
cat <<EOF > dnsmasq.conf
interface=$interface
dhcp-range=$dhcp_range,12h
dhcp-option=3,$ip_address
dhcp-option=6,$ip_address
address=/#/$ip_address
EOF

# Configuración de red y NAT
log_msg info "Configurando red y NAT..."
nmcli dev set $interface managed no > /dev/null 2>&1
echo "net.ipv4.ip_forward=1" > /etc/sysctl.conf
sysctl -p > /dev/null

ip addr flush dev $interface > /dev/null 2>&1
ip addr add $ip_address/24 dev $interface > /dev/null 2>&1

iptables -F
iptables -t nat -F
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -t nat -A PREROUTING -i $interface -p tcp --dport 80 -j DNAT --to-destination $ip_address:80
iptables -A FORWARD -i $interface -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o $interface -m state --state ESTABLISHED,RELATED -j ACCEPT
echo 1 > /proc/sys/net/ipv4/ip_forward

log_msg success "Red y NAT configuradas."

# Configuración de Apache
log_msg info "Preparando servidor web..."
systemctl enable apache2 > /dev/null 2>&1
systemctl start apache2 > /dev/null 2>&1

backup_dir="html_backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup_dir"
cp -r /var/www/html/* "$backup_dir/" 2>/dev/null

rm -rf /var/www/html/*
mkdir -p /var/www/html

cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>$portal_name</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { background: #f0f2f5; font-family: Arial, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; }
        .login-box { background: white; padding: 40px; border-radius: 12px; box-shadow: 0 0 15px rgba(0,0,0,0.1); text-align: center; width: 100%; max-width: 360px; }
        .login-box h2 { margin-bottom: 20px; color: #333; }
        .login-box input { width: 100%; padding: 12px; margin-bottom: 15px; border: 1px solid #ccc; border-radius: 6px; font-size: 16px; }
        .login-box input[type="submit"] { background: #0066cc; color: white; border: none; cursor: pointer; }
        .login-box input[type="submit"]:hover { background: #0055aa; }
        .footer { margin-top: 20px; font-size: 12px; color: #888; }
    </style>
</head>
<body>
    <div class="login-box">
        <h2>Acceso a Internet</h2>
        <form>
            <input type="text" placeholder="Usuario" disabled>
            <input type="password" placeholder="Contraseña" disabled>
            <input type="submit" value="Conectar" disabled>
        </form>
        <div class="footer">Wi-Fi proporcionado por <strong>$portal_name</strong></div>
    </div>
</body>
</html>
EOF

log_msg success "Contenido web creado correctamente."

# Inicio de servicios
log_msg info "Iniciando servicios dnsmasq y hostapd..."
dnsmasq -C dnsmasq.conf > /dev/null 2>&1 && log_msg success "dnsmasq iniciado." || log_msg error "Error iniciando dnsmasq."
hostapd hostapd.conf > /dev/null 2>&1 || log_msg error "Error iniciando hostpd."
