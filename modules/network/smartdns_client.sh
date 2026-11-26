#!/bin/bash
# ==============================================================================
#  🇦🇷 JOIF SMART DNS CLIENT — Redirección DNAT Transparente (Puerto 53 TCP/UDP)
#  Script 100% independiente: funciona en joif-script, ChumoGH, SSHPlus o Linux puro
# ==============================================================================

set -u

CONFIG_FILE="/etc/joif-smartdns-client.conf"
SERVICE_FILE="/etc/systemd/system/joif-smartdns-client.service"
INSTALL_BIN="/usr/local/bin/joif-smartdns"
CHAIN_NAME="JOIF_SMARTDNS_OUT"
DEFAULT_SMARTDNS_IP="186.122.177.239"

red='\033[1;31m'
green='\033[1;32m'
yellow='\033[1;33m'
blue='\033[1;34m'
cyan='\033[1;36m'
white='\033[1;37m'
plain='\033[0m'

# Auto-instalarse en /usr/local/bin/joif-smartdns si se ejecuta vía curl|bash o ruta temporal
ensure_installed_binary() {
    local self_path="${BASH_SOURCE[0]:-}"
    local real_self="" real_bin=""
    [ -n "$self_path" ] && real_self="$(readlink -f "$self_path" 2>/dev/null || echo "$self_path")"
    [ -e "$INSTALL_BIN" ] && real_bin="$(readlink -f "$INSTALL_BIN" 2>/dev/null || echo "$INSTALL_BIN")"
    if [ -n "$real_self" ] && [ -f "$real_self" ] && [ "$real_self" != "$real_bin" ]; then
        if [ ! -f "$INSTALL_BIN" ] || ! cmp -s "$real_self" "$INSTALL_BIN" 2>/dev/null; then
            cp -f "$real_self" "$INSTALL_BIN" 2>/dev/null || true
            chmod +x "$INSTALL_BIN" 2>/dev/null || true
        fi
    fi
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${red}✖ Este script debe ejecutarse como root (usa sudo).${plain}"
        exit 1
    fi
}

is_valid_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS='.'
    read -ra octets <<< "$ip"
    for o in "${octets[@]}"; do
        (( o >= 0 && o <= 255 )) || return 1
    done
    return 0
}

load_config() {
    SMARTDNS_IP=""
    ENABLED="0"
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE" 2>/dev/null || true
    fi
}

save_config() {
    local ip="$1"
    local enabled="$2"
    cat << EOF > "$CONFIG_FILE"
SMARTDNS_IP="$ip"
ENABLED="$enabled"
EOF
    chmod 600 "$CONFIG_FILE" 2>/dev/null || true
}

get_public_ip() {
    curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null \
        || curl -fsS --max-time 3 https://ifconfig.me 2>/dev/null \
        || hostname -I 2>/dev/null | awk '{print $1}'
}

# Valida que el servidor Smart DNS responda a esta VPS (confirma que la IP ya está en la whitelist)
test_smartdns_reachable() {
    local target_ip="$1"
    local result=""

    if command -v dig >/dev/null 2>&1; then
        result=$(dig +short +time=3 +tries=1 "@${target_ip}" cloudflare.com A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)
    elif command -v nslookup >/dev/null 2>&1; then
        result=$(nslookup -timeout=3 cloudflare.com "$target_ip" 2>/dev/null | awk '/^Address: / {print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)
    elif command -v python3 >/dev/null 2>&1; then
        result=$(python3 - "$target_ip" << 'PYEOF' 2>/dev/null || true
import socket, sys
ip = sys.argv[1]
# Minimal DNS A query for cloudflare.com
q = b'\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x0acloudflare\x03com\x00\x00\x01\x00\x01'
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(3.0)
try:
    s.sendto(q, (ip, 53))
    data, _ = s.recvfrom(512)
    if len(data) >= 12 and (data[3] & 0x0f) == 0 and int.from_bytes(data[6:8], 'big') > 0:
        print("OK")
finally:
    s.close()
PYEOF
)
    else
        echo -e "${yellow}⚠ No se encontró dig, nslookup ni python3; instalando dnsutils...${plain}"
        DEBIAN_FRONTEND=noninteractive apt-get update -qq && apt-get install -y -qq dnsutils >/dev/null 2>&1 || true
        if command -v dig >/dev/null 2>&1; then
            result=$(dig +short +time=3 +tries=1 "@${target_ip}" cloudflare.com A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)
        fi
    fi

    [ -n "$result" ]
}

is_dnat_active() {
    iptables -t nat -C OUTPUT -j "$CHAIN_NAME" >/dev/null 2>&1 && \
    iptables -t nat -S "$CHAIN_NAME" 2>/dev/null | grep -q -- '--dport 53 -j DNAT'
}

persist_iptables() {
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1 || true
    elif command -v iptables-save >/dev/null 2>&1; then
        mkdir -p /etc/iptables 2>/dev/null || true
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
}

install_systemd_service() {
    ensure_installed_binary
    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=JOIF Smart DNS Client (Transparent DNS DNAT)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$INSTALL_BIN --apply
ExecStop=$INSTALL_BIN --disable-runtime

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable joif-smartdns-client.service >/dev/null 2>&1 || true
}

apply_dnat_rules() {
    local target_ip="$1"
    if ! is_valid_ipv4 "$target_ip"; then
        echo -e "${red}✖ IP inválida: ${target_ip}${plain}"
        return 1
    fi

    # Limpiar posibles reglas sueltas previas en OUTPUT hacia esa misma IP (migración limpia)
    while iptables -t nat -C OUTPUT -p udp --dport 53 ! -o lo ! -d "$target_ip" -j DNAT --to-destination "${target_ip}:53" >/dev/null 2>&1; do
        iptables -t nat -D OUTPUT -p udp --dport 53 ! -o lo ! -d "$target_ip" -j DNAT --to-destination "${target_ip}:53" >/dev/null 2>&1 || break
    done
    while iptables -t nat -C OUTPUT -p tcp --dport 53 ! -o lo ! -d "$target_ip" -j DNAT --to-destination "${target_ip}:53" >/dev/null 2>&1; do
        iptables -t nat -D OUTPUT -p tcp --dport 53 ! -o lo ! -d "$target_ip" -j DNAT --to-destination "${target_ip}:53" >/dev/null 2>&1 || break
    done

    # Crear cadena dedicada si no existe y vaciarla (100% idempotente)
    iptables -t nat -N "$CHAIN_NAME" >/dev/null 2>&1 || true
    iptables -t nat -F "$CHAIN_NAME"

    # No tocar loopback ni tráfico dirigido ya al Smart DNS
    iptables -t nat -A "$CHAIN_NAME" -o lo -j RETURN
    iptables -t nat -A "$CHAIN_NAME" -d "$target_ip" -j RETURN
    iptables -t nat -A "$CHAIN_NAME" -p udp --dport 53 -j DNAT --to-destination "${target_ip}:53"
    iptables -t nat -A "$CHAIN_NAME" -p tcp --dport 53 -j DNAT --to-destination "${target_ip}:53"

    # Enlazar OUTPUT -> JOIF_SMARTDNS_OUT sin duplicar
    if ! iptables -t nat -C OUTPUT -j "$CHAIN_NAME" >/dev/null 2>&1; then
        iptables -t nat -I OUTPUT 1 -j "$CHAIN_NAME"
    fi

    persist_iptables
    return 0
}

remove_dnat_rules() {
    while iptables -t nat -C OUTPUT -j "$CHAIN_NAME" >/dev/null 2>&1; do
        iptables -t nat -D OUTPUT -j "$CHAIN_NAME" >/dev/null 2>&1 || break
    done
    iptables -t nat -F "$CHAIN_NAME" >/dev/null 2>&1 || true
    iptables -t nat -X "$CHAIN_NAME" >/dev/null 2>&1 || true
    persist_iptables
}

action_activate() {
    load_config
    local current_default="${SMARTDNS_IP:-$DEFAULT_SMARTDNS_IP}"
    echo ""
    read -r -p "$(echo -e "${green} ► Ingresa la IP del Smart DNS [${current_default}]: ${plain}")" input_ip
    input_ip="${input_ip:-$current_default}"
    input_ip=$(echo "$input_ip" | tr -d '[:space:]')

    if ! is_valid_ipv4 "$input_ip"; then
        echo -e "${red}✖ Formato de IPv4 inválido: ${input_ip}${plain}"
        read -r -p "Presiona Enter para continuar..."
        return 1
    fi

    echo -e "${yellow}[*] Verificando conectividad y autorización contra ${input_ip}:53...${plain}"
    if ! test_smartdns_reachable "$input_ip"; then
        local my_ip
        my_ip=$(get_public_ip)
        echo -e "${red}✖ El Smart DNS (${input_ip}) NO respondió a esta VPS.${plain}"
        echo -e "${yellow}   Posible causa: esta VPS aún no está autorizada en la whitelist de joif-smartdns.${plain}"
        echo -e "${white}   Ejecuta primero en tu VPS Smart DNS de Argentina:${plain}"
        echo -e "${cyan}   smartdns ip add ${my_ip:-TU_IP_VPS} \"$(hostname)\" 0${plain}"
        echo -e "${yellow}   No se activó el DNAT para evitar dejar esta VPS sin DNS.${plain}"
        read -r -p "Presiona Enter para continuar..."
        return 1
    fi

    echo -e "${green}✔ Smart DNS respondió correctamente. Aplicando reglas DNAT...${plain}"
    if apply_dnat_rules "$input_ip"; then
        save_config "$input_ip" "1"
        install_systemd_service
        echo -e "${green}✅ Smart DNS ACTIVADO y persistente tras reinicios (${input_ip}:53).${plain}"
    else
        echo -e "${red}✖ Error al aplicar las reglas iptables.${plain}"
    fi
    read -r -p "Presiona Enter para continuar..."
}

action_deactivate() {
    load_config
    echo -e "\n${yellow}[*] Desactivando reglas DNAT de Smart DNS...${plain}"
    remove_dnat_rules
    save_config "${SMARTDNS_IP:-$DEFAULT_SMARTDNS_IP}" "0"
    if [ -f "$SERVICE_FILE" ]; then
        systemctl disable joif-smartdns-client.service >/dev/null 2>&1 || true
    fi
    echo -e "${green}✅ Smart DNS DESACTIVADO. El tráfico DNS volvió al comportamiento normal.${plain}"
    read -r -p "Presiona Enter para continuar..."
}

action_diagnostic() {
    load_config
    local target="${SMARTDNS_IP:-$DEFAULT_SMARTDNS_IP}"
    local my_ip
    my_ip=$(get_public_ip)

    echo -e "\n${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${yellow}🔍 DIAGNÓSTICO SMART DNS CLIENTE${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${white}IP Pública de esta VPS :${plain} ${cyan}${my_ip:-Desconocida}${plain}"
    echo -e " ${white}IP Smart DNS objetivo  :${plain} ${cyan}${target}${plain}"
    if is_dnat_active; then
        echo -e " ${white}Estado DNAT (iptables) :${plain} ${green}ACTIVO (${CHAIN_NAME})${plain}"
    else
        echo -e " ${white}Estado DNAT (iptables) :${plain} ${red}INACTIVO${plain}"
    fi

    echo -e "\n${yellow}[*] Probando consulta DNS directa a ${target}...${plain}"
    if test_smartdns_reachable "$target"; then
        echo -e " ${green}✔ Autorización OK: ${target} responde a esta VPS.${plain}"
        if command -v dig >/dev/null 2>&1; then
            local ar_test
            ar_test=$(dig +short +time=3 +tries=1 "@${target}" argentina.gob.ar A 2>/dev/null | head -n1 || true)
            echo -e " ${white}Resolución argentina.gob.ar :${plain} ${green}${ar_test:-Sin respuesta}${plain}"
        fi
    else
        echo -e " ${red}✖ Sin respuesta desde ${target}:53 (verifica whitelist o firewall).${plain}"
    fi

    echo -e "\n${yellow}[*] Reglas actuales en nat/${CHAIN_NAME}:${plain}"
    iptables -t nat -S "$CHAIN_NAME" 2>/dev/null || echo " (Cadena no creada / inactiva)"
    echo ""
    read -r -p "Presiona Enter para continuar..."
}

show_menu() {
    ensure_installed_binary
    while true; do
        load_config
        local status_badge="${red}[OFF]${plain}"
        if is_dnat_active; then
            status_badge="${green}[ON -> ${SMARTDNS_IP:-Activo}]${plain}"
        fi

        clear
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e "   ${yellow}🇦🇷 JOIF SMART DNS CLIENTE (DNAT PUERTO 53)${plain}"
        echo -e "   ${white}Estado actual: ${status_badge}${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e " ${green}[1]${plain} > 🚀 Activar / Cambiar IP Smart DNS"
        echo -e " ${green}[2]${plain} > 🛑 Desactivar Smart DNS (restaurar DNS normal)"
        echo -e " ${green}[3]${plain} > 🔍 Probar conexión y ver diagnóstico"
        echo -e " ${red}[0]${plain} > 🔙 Salir / Volver"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e " ${white}Acceso rápido por consola: ${cyan}joif-smartdns${plain}"
        echo ""
        read -r -p "$(echo -e "${white}Selecciona una opción: ${plain}")" opt

        case "$opt" in
            1) action_activate ;;
            2) action_deactivate ;;
            3) action_diagnostic ;;
            0|00) break ;;
            *) echo -e "${red}Opción inválida.${plain}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# Punto de entrada CLI / Systemd / Menú Interactivo
# ==============================================================================
require_root

case "${1:-}" in
    --apply)
        load_config
        if [ "${ENABLED:-0}" = "1" ] && is_valid_ipv4 "${SMARTDNS_IP:-}"; then
            apply_dnat_rules "$SMARTDNS_IP"
        fi
        ;;
    --disable|--disable-runtime)
        remove_dnat_rules
        if [ "${1:-}" = "--disable" ]; then
            load_config
            save_config "${SMARTDNS_IP:-$DEFAULT_SMARTDNS_IP}" "0"
            systemctl disable joif-smartdns-client.service >/dev/null 2>&1 || true
        fi
        ;;
    --status)
        load_config
        if is_dnat_active; then
            echo "ON:${SMARTDNS_IP:-active}"
            exit 0
        else
            echo "OFF"
            exit 1
        fi
        ;;
    *)
        show_menu
        ;;
esac
