#!/bin/bash
# ==============================================================================
#  🇦🇷 JOIF SMART DNS CLIENT — Redirección DNAT Transparente (Puerto 53 TCP/UDP)
#  Script 100% independiente: funciona en joif-script, ChumoGH, SSHPlus o Linux puro
# ==============================================================================

set -u

CONFIG_FILE="/etc/joif-smartdns-client.conf"
SERVICE_FILE="/etc/systemd/system/joif-smartdns-client.service"
WATCHDOG_SERVICE="/etc/systemd/system/joif-smartdns-watchdog.service"
STATE_FILE="/run/joif-smartdns-state"
FAILOVER_LOG="/var/log/joif-smartdns-failover.log"
INSTALL_BIN="/usr/local/bin/joif-smartdns"
CHAIN_NAME="JOIF_SMARTDNS_OUT"
DEFAULT_SMARTDNS_IP="186.122.177.239"
WATCHDOG_INTERVAL=30
FAIL_THRESHOLD=2
RECOVER_THRESHOLD=3

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

# Valida que el proxy SNI (nginx 443/80) en el servidor Smart DNS esté aceptando conexiones TCP
test_smartdns_tcp_proxy() {
    local target_ip="$1"
    if command -v timeout >/dev/null 2>&1; then
        timeout 2 bash -c "exec 3<>/dev/tcp/${target_ip}/443" >/dev/null 2>&1 && return 0
        timeout 2 bash -c "exec 3<>/dev/tcp/${target_ip}/80" >/dev/null 2>&1 && return 0
        return 1
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$target_ip" << 'PYEOF' >/dev/null 2>&1
import socket, sys
ip = sys.argv[1]
for port in (443, 80):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        s.connect((ip, port))
        s.close()
        sys.exit(0)
    except Exception:
        s.close()
sys.exit(1)
PYEOF
        return $?
    fi
    return 0
}

test_smartdns_full_health() {
    local target_ip="$1"
    test_smartdns_reachable "$target_ip" && test_smartdns_tcp_proxy "$target_ip"
}

log_failover_event() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "$FAILOVER_LOG" 2>/dev/null || true
    # Mantener el log liviano (últimas 200 líneas)
    if [ -f "$FAILOVER_LOG" ] && [ "$(wc -l < "$FAILOVER_LOG" 2>/dev/null || echo 0)" -gt 250 ]; then
        tail -n 200 "$FAILOVER_LOG" > "${FAILOVER_LOG}.tmp" 2>/dev/null && mv -f "${FAILOVER_LOG}.tmp" "$FAILOVER_LOG" 2>/dev/null || true
    fi
}

set_runtime_state() {
    echo "$1" > "$STATE_FILE" 2>/dev/null || true
}

get_runtime_state() {
    load_config
    if is_dnat_active; then
        echo "ACTIVE"
    elif [ "${ENABLED:-0}" = "1" ]; then
        echo "FAILOVER"
    else
        echo "OFF"
    fi
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

    cat << EOF > "$WATCHDOG_SERVICE"
[Unit]
Description=JOIF Smart DNS Auto-Failover Watchdog (DNS :53 + SNI :443)
After=network-online.target joif-smartdns-client.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=$INSTALL_BIN --watchdog
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable joif-smartdns-client.service >/dev/null 2>&1 || true
    systemctl enable joif-smartdns-watchdog.service >/dev/null 2>&1 || true
    systemctl restart joif-smartdns-watchdog.service >/dev/null 2>&1 || true
}

stop_watchdog_service() {
    systemctl stop joif-smartdns-watchdog.service >/dev/null 2>&1 || true
    systemctl disable joif-smartdns-watchdog.service >/dev/null 2>&1 || true
}

watchdog_loop() {
    local fail_count=0
    local ok_count=0

    while true; do
        load_config
        if [ "${ENABLED:-0}" != "1" ] || ! is_valid_ipv4 "${SMARTDNS_IP:-}"; then
            set_runtime_state "OFF"
            fail_count=0
            ok_count=0
            sleep "$WATCHDOG_INTERVAL"
            continue
        fi

        if test_smartdns_full_health "$SMARTDNS_IP"; then
            fail_count=0
            if is_dnat_active; then
                ok_count=0
                set_runtime_state "ACTIVE"
            else
                ok_count=$((ok_count + 1))
                if [ "$ok_count" -ge "$RECOVER_THRESHOLD" ]; then
                    if apply_dnat_rules "$SMARTDNS_IP" >/dev/null 2>&1; then
                        set_runtime_state "ACTIVE"
                        ok_count=0
                        log_failover_event "[RECOVERY] Smart DNS ${SMARTDNS_IP} operativo nuevamente — DNAT reactivado."
                    fi
                else
                    set_runtime_state "FAILOVER"
                fi
            fi
        else
            ok_count=0
            fail_count=$((fail_count + 1))
            # Reintento rápido de confirmación antes de disparar failover
            if [ "$fail_count" -eq 1 ]; then
                sleep 3
                if ! test_smartdns_full_health "$SMARTDNS_IP"; then
                    fail_count=$((fail_count + 1))
                else
                    fail_count=0
                fi
            fi

            if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
                if is_dnat_active; then
                    remove_dnat_rules >/dev/null 2>&1 || true
                    log_failover_event "[FAILOVER] Smart DNS ${SMARTDNS_IP} no responde (DNS :53 / SNI :443) — DNAT suspendido, usando DNS local."
                fi
                set_runtime_state "FAILOVER"
            fi
        fi

        sleep "$WATCHDOG_INTERVAL"
    done
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
        set_runtime_state "ACTIVE"
        install_systemd_service
        log_failover_event "[ACTIVADO] Smart DNS configurado hacia ${input_ip} con Watchdog Auto-Failover activo."
        echo -e "${green}✅ Smart DNS ACTIVADO (${input_ip}:53) + Watchdog Auto-Failover activo.${plain}"
    else
        echo -e "${red}✖ Error al aplicar las reglas iptables.${plain}"
    fi
    read -r -p "Presiona Enter para continuar..."
}

action_deactivate() {
    load_config
    echo -e "\n${yellow}[*] Desactivando reglas DNAT y Watchdog de Smart DNS...${plain}"
    stop_watchdog_service
    remove_dnat_rules
    save_config "${SMARTDNS_IP:-$DEFAULT_SMARTDNS_IP}" "0"
    set_runtime_state "OFF"
    if [ -f "$SERVICE_FILE" ]; then
        systemctl disable joif-smartdns-client.service >/dev/null 2>&1 || true
    fi
    log_failover_event "[DESACTIVADO] Smart DNS desactivado manualmente."
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

    echo -e "\n${yellow}[*] Probando consulta DNS (:53) y SNI Proxy (:443/:80) en ${target}...${plain}"
    if test_smartdns_reachable "$target"; then
        echo -e " ${green}✔ DNS (:53) OK: ${target} responde a esta VPS.${plain}"
        if test_smartdns_tcp_proxy "$target"; then
            echo -e " ${green}✔ SNI Proxy (:443/:80) OK: aceptando conexiones.${plain}"
        else
            echo -e " ${red}✖ SNI Proxy (:443/:80) SIN RESPUESTA (nginx caído o bloqueado).${plain}"
        fi
        if command -v dig >/dev/null 2>&1; then
            local ar_test
            ar_test=$(dig +short +time=3 +tries=1 "@${target}" argentina.gob.ar A 2>/dev/null | head -n1 || true)
            echo -e " ${white}Resolución argentina.gob.ar :${plain} ${green}${ar_test:-Sin respuesta}${plain}"
        fi
    else
        echo -e " ${red}✖ Sin respuesta DNS desde ${target}:53 (verifica whitelist o firewall).${plain}"
    fi

    local wd_status="${red}INACTIVO${plain}"
    systemctl is-active --quiet joif-smartdns-watchdog.service 2>/dev/null && wd_status="${green}ACTIVO (cada ${WATCHDOG_INTERVAL}s)${plain}"
    echo -e " ${white}Watchdog Auto-Failover :${plain} ${wd_status}"

    echo -e "\n${yellow}[*] Reglas actuales en nat/${CHAIN_NAME}:${plain}"
    iptables -t nat -S "$CHAIN_NAME" 2>/dev/null || echo " (Cadena no creada / inactiva)"
    echo ""
    read -r -p "Presiona Enter para continuar..."
}

action_view_log() {
    clear
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "   ${yellow}📜 HISTORIAL DE FAILOVER / RECUPERACIÓN SMART DNS${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    if [ -f "$FAILOVER_LOG" ] && [ -s "$FAILOVER_LOG" ]; then
        tail -n 25 "$FAILOVER_LOG"
    else
        echo -e "  ${white}Sin eventos registrados todavía.${plain}"
    fi
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    read -r -p "Presiona Enter para continuar..."
}

show_menu() {
    ensure_installed_binary
    while true; do
        load_config
        local state status_badge wd_badge
        state=$(get_runtime_state)
        case "$state" in
            ACTIVE)   status_badge="${green}[ON -> ${SMARTDNS_IP:-Activo}]${plain}" ;;
            FAILOVER) status_badge="${yellow}[FAILOVER -> DNS local (AR caído)]${plain}" ;;
            *)        status_badge="${red}[OFF]${plain}" ;;
        esac
        wd_badge="${red}OFF${plain}"
        systemctl is-active --quiet joif-smartdns-watchdog.service 2>/dev/null && wd_badge="${green}ON (${WATCHDOG_INTERVAL}s)${plain}"

        clear
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e "   ${yellow}🇦🇷 JOIF SMART DNS CLIENTE (DNAT PUERTO 53 + FAILOVER)${plain}"
        echo -e "   ${white}Estado actual : ${status_badge}${plain}"
        echo -e "   ${white}Watchdog AR   : ${wd_badge}${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e " ${green}[1]${plain} > 🚀 Activar / Cambiar IP Smart DNS (con Auto-Failover)"
        echo -e " ${green}[2]${plain} > 🛑 Desactivar Smart DNS (restaurar DNS normal)"
        echo -e " ${green}[3]${plain} > 🔍 Probar conexión (DNS :53 + SNI :443) y diagnóstico"
        echo -e " ${green}[4]${plain} > 📜 Ver historial de eventos Failover / Recuperación"
        echo -e " ${red}[0]${plain} > 🔙 Salir / Volver"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e " ${white}Acceso rápido por consola: ${cyan}joif-smartdns${plain}"
        echo ""
        read -r -p "$(echo -e "${white}Selecciona una opción: ${plain}")" opt

        case "$opt" in
            1) action_activate ;;
            2) action_deactivate ;;
            3) action_diagnostic ;;
            4) action_view_log ;;
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
            if test_smartdns_full_health "$SMARTDNS_IP"; then
                apply_dnat_rules "$SMARTDNS_IP"
                set_runtime_state "ACTIVE"
            else
                remove_dnat_rules >/dev/null 2>&1 || true
                set_runtime_state "FAILOVER"
                log_failover_event "[BOOT-FAILOVER] Al iniciar, ${SMARTDNS_IP} no respondió — arrancando en DNS local."
            fi
        fi
        ;;
    --watchdog)
        watchdog_loop
        ;;
    --disable|--disable-runtime)
        remove_dnat_rules
        if [ "${1:-}" = "--disable" ]; then
            stop_watchdog_service
            load_config
            save_config "${SMARTDNS_IP:-$DEFAULT_SMARTDNS_IP}" "0"
            set_runtime_state "OFF"
            systemctl disable joif-smartdns-client.service >/dev/null 2>&1 || true
        fi
        ;;
    --status)
        load_config
        st=$(get_runtime_state)
        if [ "$st" = "ACTIVE" ]; then
            echo "ON:${SMARTDNS_IP:-active}"
            exit 0
        elif [ "$st" = "FAILOVER" ]; then
            echo "FAILOVER:${SMARTDNS_IP:-down}"
            exit 2
        else
            echo "OFF"
            exit 1
        fi
        ;;
    *)
        show_menu
        ;;
esac
