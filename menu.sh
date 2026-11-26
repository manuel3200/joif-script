#!/bin/bash
# =========================================================================
# JOIF Cloud v2.0 — Menú Principal Modular (JOIF TUI v2)
# =========================================================================

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
[ ! -d "${SCRIPT_DIR}/modules" ] && [ -d "/root/joif-core/modules" ] && SCRIPT_DIR="/root/joif-core"
source "${SCRIPT_DIR}/core/utils.sh" 2>/dev/null || source /root/joif-core/core/utils.sh 2>/dev/null

run_module() {
    local target="${SCRIPT_DIR}/$1"
    shift || true
    if [ -f "$target" ]; then
        bash "$target" "$@"
    else
        echo -e "\n  ${red}✖ Módulo no encontrado: ${target}${plain}"
        pause
    fi
}

# Flag CLI autónomo: menu --autolink "<URL>" "<TOKEN>" [NOMBRE]
if [ "${1:-}" = "--autolink" ] || [ "${1:-}" = "-a" ]; then
    run_module "modules/tools/autolink.sh" "${2:-}" "${3:-}" "${4:-}" "cli"
    exit $?
fi

menu_herramientas() {
    while true; do
        draw_header
        local smartdns_badge="${red}[OFF]${plain}"
        if iptables -t nat -C OUTPUT -j JOIF_SMARTDNS_OUT >/dev/null 2>&1; then
            local sd_ip
            sd_ip=$(grep -m1 '^SMARTDNS_IP=' /etc/joif-smartdns-client.conf 2>/dev/null | cut -d'=' -f2- | tr -d '"\r\n')
            smartdns_badge="${green}[ON:${sd_ip:-AR}]${plain}"
        fi
        local bbr_badge="${yellow}[STD]${plain}"
        sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | grep -qx 'bbr' && bbr_badge="${green}[BBR]${plain}"

        echo -e "  ${yellow}HERRAMIENTAS Y OPTIMIZACIÓN DEL SISTEMA${plain}"
        ui_subline
        echo -e "  ${green}[1]${plain} Monitor de puertos en escucha"
        echo -e "  ${green}[2]${plain} Test de velocidad (Speedtest)"
        echo -e "  ${green}[3]${plain} Limpieza de RAM, APT y logs"
        echo -e "  ${green}[4]${plain} Memoria virtual SWAP (1 paso)"
        echo -e "  ${green}[5]${plain} Optimización TCP BBR + OpenSSH      ${bbr_badge}"
        echo -e "  ${green}[6]${plain} Smart DNS Cliente (Bypass AR)       ${smartdns_badge}"
        echo -e "  ${green}[7]${plain} Backup y restauración de cuentas"
        echo -e "  ${red}[0]${plain} Volver al menú principal"
        ui_line
        read -r -p "$(echo -e "${white}Selecciona una opción: ${plain}")" opt_t

        case "$opt_t" in
            1)
                ui_title "PUERTOS ESCUCHANDO EN EL SERVIDOR"
                printf "  ${cyan}%-7s %-9s %s${plain}\n" "PROTO" "PUERTO" "PROCESO"
                ui_subline
                ss -tulpn 2>/dev/null | awk '/LISTEN|UNCONN/ {print $1, $5, $7}' | while read -r proto addr proc; do
                    local p name
                    p="${addr##*:}"
                    name=$(echo "$proc" | awk -F'"' '{print $2}')
                    [ "$name" = "node" ] && name="joif-node"
                    printf "  %-7s %-9s %s\n" "$proto" "$p" "${name:-sistema}"
                done | sort -k2 -n | uniq
                pause
                ;;
            2)
                ui_title "TEST DE VELOCIDAD"
                if ! command -v speedtest-cli >/dev/null 2>&1; then
                    apt-get update -qq && apt-get install -y -qq speedtest-cli >/dev/null 2>&1 || true
                fi
                speedtest-cli --simple 2>/dev/null || echo -e "  ${red}✖ speedtest-cli no disponible.${plain}"
                pause
                ;;
            3) run_module "modules/system/cleaner.sh" ;;
            4) run_module "modules/system/swap_manager.sh" ;;
            5) run_module "modules/system/network_tuning.sh" ;;
            6) run_module "modules/network/smartdns_client.sh" ;;
            7) run_module "modules/tools/backup_manager.sh" ;;
            0|00) break ;;
            *) echo -e "  ${red}Opción inválida.${plain}"; sleep 1 ;;
        esac
    done
}

menu_gestion() {
    while true; do
        ui_title "GESTIÓN Y MANTENIMIENTO DE JOIF CLOUD"
        echo -e "  ${green}[1]${plain} Actualizar script (Git Pull oficial)"
        echo -e "  ${green}[2]${plain} Autoiniciar menú al entrar por SSH"
        echo -e "  ${red}[3]${plain} Desinstalar JOIF Cloud (seguro, sin cortar SSH)"
        echo -e "  ${white}[0]${plain} Volver"
        ui_line
        read -r -p "$(echo -e "${white}Selecciona una opción: ${plain}")" opt_g
        case "$opt_g" in
            1) run_module "update.sh"; pause ;;
            2) run_module "modules/system/autostart_manager.sh" ;;
            3) run_module "modules/system/uninstall.sh"; exit 0 ;;
            0|00) break ;;
            *) echo -e "  ${red}Opción inválida.${plain}"; sleep 1 ;;
        esac
    done
}

# Bucle del Menú Principal
while true; do
    draw_header
    autostart_badge="${red}[OFF]${plain}"
    grep -Fq "[ -f /usr/bin/menu ] && /usr/bin/menu" /root/.bashrc 2>/dev/null && autostart_badge="${green}[ON]${plain}"

    echo -e "  ${yellow}MENÚ PRINCIPAL${plain}"
    ui_subline
    echo -e "  ${green}[1]${plain} Control de Usuarios (SSH / HWID / CheckUser)"
    echo -e "  ${green}[2]${plain} Protocolos VPN (WS-Proxy, BadVPN, SSL Stunnel)"
    echo -e "  ${green}[3]${plain} Herramientas del Sistema (BBR, SmartDNS, SWAP, Backup)"
    echo -e "  ${green}[4]${plain} Vincular con Portal / Tienda Web (Auto-Link)"
    echo -e "  ${green}[5]${plain} Gestión del Script (Actualizar / Autoinicio ${autostart_badge})"
    echo -e "  ${red}[0]${plain} Salir a consola"
    ui_line
    read -r -p "$(echo -e "${white}Selecciona una opción: ${plain}")" opt_main

    case "$opt_main" in
        1|01) run_module "modules/users/user_manager.sh" ;;
        2|02) run_module "modules/network/protocol_manager.sh" ;;
        3|03) menu_herramientas ;;
        4|04) run_module "modules/tools/autolink.sh" ;;
        5|05) menu_gestion ;;
        0|00) clear; exit 0 ;;
        *) echo -e "  ${red}Opción inválida.${plain}"; sleep 1 ;;
    esac
done
