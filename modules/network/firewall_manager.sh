#!/bin/bash
# =========================================================================
# JOIF Cloud v2.0 — Escudo Anti-Torrent, Anti-SPAM y Firewall Personalizado
# Cadenas aisladas (OUTPUT + FORWARD, IPv4 + IPv6) — Nunca toca SSH :22
# =========================================================================

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "${SCRIPT_DIR}/../../core/utils.sh" 2>/dev/null || source /root/joif-core/core/utils.sh 2>/dev/null

FW_CONF="/etc/joif-firewall.conf"
FW_SERVICE="/etc/systemd/system/joif-firewall.service"
FW_BIN="/usr/local/bin/joif-firewall"

CHAIN_TORRENT="JOIF_FW_TORRENT"
CHAIN_SPAM="JOIF_FW_SPAM"
CHAIN_CUSTOM="JOIF_FW_CUSTOM"

TORRENT_STRINGS=(
    "BitTorrent"
    "BitTorrent protocol"
    "peer_id="
    "info_hash="
    "get_peers"
    "announce_peer"
    "find_node"
    ".torrent"
    "magnet:?xt=urn:btih:"
)

TORRENT_PORTS=("6881:6889" "6969")
SPAM_PORTS=("25" "465" "587" "2525" "135:139" "445")

# Garantizar valores de colores si se ejecuta standalone
red="${red:-\033[1;31m}"
green="${green:-\033[1;32m}"
yellow="${yellow:-\033[1;33m}"
cyan="${cyan:-\033[1;36m}"
white="${white:-\033[1;37m}"
gray="${gray:-\033[0;90m}"
plain="${plain:-\033[0m}"

load_fw_conf() {
    BLOCK_TORRENT=0
    BLOCK_SPAM=0
    CUSTOM_PORTS=""
    CUSTOM_KEYWORDS=""
    if [ -f "$FW_CONF" ]; then
        # shellcheck disable=SC1090
        source "$FW_CONF" 2>/dev/null || true
    fi
}

save_fw_conf() {
    cat << EOF > "$FW_CONF"
BLOCK_TORRENT=${BLOCK_TORRENT:-0}
BLOCK_SPAM=${BLOCK_SPAM:-0}
CUSTOM_PORTS="${CUSTOM_PORTS:-}"
CUSTOM_KEYWORDS="${CUSTOM_KEYWORDS:-}"
EOF
    chmod 600 "$FW_CONF" 2>/dev/null || true
}

has_xt_string() {
    modprobe xt_string 2>/dev/null || true
    iptables -N JOIF_STR_TEST 2>/dev/null || true
    if iptables -A JOIF_STR_TEST -m string --algo bm --string "test" -j DROP 2>/dev/null; then
        iptables -F JOIF_STR_TEST 2>/dev/null || true
        iptables -X JOIF_STR_TEST 2>/dev/null || true
        return 0
    fi
    iptables -F JOIF_STR_TEST 2>/dev/null || true
    iptables -X JOIF_STR_TEST 2>/dev/null || true
    return 1
}

unlink_and_destroy_chain() {
    local bin="$1" chain="$2"
    command -v "$bin" >/dev/null 2>&1 || return 0
    while "$bin" -D OUTPUT -j "$chain" 2>/dev/null; do :; done
    while "$bin" -D FORWARD -j "$chain" 2>/dev/null; do :; done
    "$bin" -F "$chain" 2>/dev/null || true
    "$bin" -X "$chain" 2>/dev/null || true
}

ensure_chain_linked() {
    local bin="$1" chain="$2"
    "$bin" -N "$chain" 2>/dev/null || true
    "$bin" -F "$chain"
    "$bin" -A "$chain" -o lo -j RETURN 2>/dev/null || true
    "$bin" -C OUTPUT -j "$chain" 2>/dev/null || "$bin" -I OUTPUT 1 -j "$chain" 2>/dev/null || true
    "$bin" -C FORWARD -j "$chain" 2>/dev/null || "$bin" -I FORWARD 1 -j "$chain" 2>/dev/null || true
}

apply_fw_rules() {
    load_fw_conf
    local str_ok=0
    has_xt_string && str_ok=1

    local bins=("iptables")
    if command -v ip6tables >/dev/null 2>&1 && ip6tables -L OUTPUT -n >/dev/null 2>&1; then
        bins+=("ip6tables")
    fi

    for bin in "${bins[@]}"; do
        # 1. Cadena Anti-Torrent / P2P
        if [ "${BLOCK_TORRENT:-0}" = "1" ]; then
            ensure_chain_linked "$bin" "$CHAIN_TORRENT"
            for p in "${TORRENT_PORTS[@]}"; do
                "$bin" -A "$CHAIN_TORRENT" -p tcp --dport "$p" -j DROP 2>/dev/null || true
                "$bin" -A "$CHAIN_TORRENT" -p udp --dport "$p" -j DROP 2>/dev/null || true
            done
            if [ "$str_ok" -eq 1 ]; then
                for sig in "${TORRENT_STRINGS[@]}"; do
                    "$bin" -A "$CHAIN_TORRENT" -m string --algo bm --icase --string "$sig" -j DROP 2>/dev/null || true
                done
            fi
        else
            unlink_and_destroy_chain "$bin" "$CHAIN_TORRENT"
        fi

        # 2. Cadena Anti-SPAM (SMTP / SMB saliente)
        if [ "${BLOCK_SPAM:-0}" = "1" ]; then
            ensure_chain_linked "$bin" "$CHAIN_SPAM"
            for p in "${SPAM_PORTS[@]}"; do
                "$bin" -A "$CHAIN_SPAM" -p tcp --dport "$p" -j DROP 2>/dev/null || true
                "$bin" -A "$CHAIN_SPAM" -p udp --dport "$p" -j DROP 2>/dev/null || true
            done
        else
            unlink_and_destroy_chain "$bin" "$CHAIN_SPAM"
        fi

        # 3. Cadena Personalizada (puertos + palabras clave)
        if [ -n "${CUSTOM_PORTS:-}" ] || [ -n "${CUSTOM_KEYWORDS:-}" ]; then
            ensure_chain_linked "$bin" "$CHAIN_CUSTOM"
            if [ -n "${CUSTOM_PORTS:-}" ]; then
                local IFS=','
                for p in $CUSTOM_PORTS; do
                    [ -z "$p" ] && continue
                    "$bin" -A "$CHAIN_CUSTOM" -p tcp --dport "$p" -j DROP 2>/dev/null || true
                    "$bin" -A "$CHAIN_CUSTOM" -p udp --dport "$p" -j DROP 2>/dev/null || true
                done
            fi
            if [ -n "${CUSTOM_KEYWORDS:-}" ] && [ "$str_ok" -eq 1 ]; then
                local IFS='|'
                for kw in $CUSTOM_KEYWORDS; do
                    [ -z "$kw" ] && continue
                    "$bin" -A "$CHAIN_CUSTOM" -m string --algo bm --icase --string "$kw" -j DROP 2>/dev/null || true
                done
            fi
        else
            unlink_and_destroy_chain "$bin" "$CHAIN_CUSTOM"
        fi
    done

    # Instalar/actualizar servicio systemd para persistencia tras reinicios
    if [ "${BLOCK_TORRENT:-0}" = "1" ] || [ "${BLOCK_SPAM:-0}" = "1" ] || [ -n "${CUSTOM_PORTS:-}" ] || [ -n "${CUSTOM_KEYWORDS:-}" ]; then
        install_fw_service
    fi
}

install_fw_service() {
    ln -sf "$SCRIPT_PATH" "$FW_BIN" 2>/dev/null || true
    cat << EOF > "$FW_SERVICE"
[Unit]
Description=JOIF Cloud Firewall (Anti-Torrent, Anti-SPAM & Custom Filters)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${FW_BIN} --apply
ExecStop=${FW_BIN} --disable-runtime

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable joif-firewall.service >/dev/null 2>&1 || true
}

disable_fw_runtime() {
    local bins=("iptables")
    command -v ip6tables >/dev/null 2>&1 && bins+=("ip6tables")
    for bin in "${bins[@]}"; do
        unlink_and_destroy_chain "$bin" "$CHAIN_TORRENT"
        unlink_and_destroy_chain "$bin" "$CHAIN_SPAM"
        unlink_and_destroy_chain "$bin" "$CHAIN_CUSTOM"
    done
}

is_valid_port_spec() {
    local spec="$1"
    [[ "$spec" =~ ^[0-9]{1,5}(:[0-9]{1,5})?$ ]] || return 1
    local p1="${spec%%:*}" p2="${spec##*:}"
    (( p1 >= 1 && p1 <= 65535 && p2 >= 1 && p2 <= 65535 && p1 <= p2 )) || return 1
    # Nunca permitir bloquear SSH 22 por accidente
    if (( p1 <= 22 && p2 >= 22 )); then
        return 2
    fi
    return 0
}

count_blocked_packets() {
    local chain="$1"
    iptables -L "$chain" -nvx 2>/dev/null | awk 'NR>2 && $3=="DROP" {sum+=$1} END {print sum+0}'
}

show_blocked_list() {
    load_fw_conf
    ui_title "LISTA ACTUAL DE BLOQUEOS Y ESTADÍSTICAS"
    local t_st="${red}INACTIVO${plain}" s_st="${red}INACTIVO${plain}"
    [ "${BLOCK_TORRENT:-0}" = "1" ] && t_st="${green}ACTIVO${plain} (${cyan}$(count_blocked_packets "$CHAIN_TORRENT") pkts bloqueados${plain})"
    [ "${BLOCK_SPAM:-0}" = "1" ] && s_st="${green}ACTIVO${plain} (${cyan}$(count_blocked_packets "$CHAIN_SPAM") pkts bloqueados${plain})"

    echo -e "  ${white}Anti-Torrent / P2P  :${plain} ${t_st}"
    echo -e "  ${white}Anti-SPAM (SMTP)    :${plain} ${s_st}"
    if has_xt_string; then
        echo -e "  ${white}Módulo xt_string    :${plain} ${green}Soportado por Kernel${plain}"
    else
        echo -e "  ${white}Módulo xt_string    :${plain} ${yellow}No disponible (solo bloqueo por puertos)${plain}"
    fi
    ui_subline

    echo -e "  ${yellow}Puertos personalizados bloqueados:${plain}"
    if [ -n "${CUSTOM_PORTS:-}" ]; then
        echo -e "    ${cyan}${CUSTOM_PORTS//,/, }${plain}"
    else
        echo -e "    ${gray}(Ninguno)${plain}"
    fi

    echo -e "\n  ${yellow}Palabras clave / dominios personalizados:${plain}"
    if [ -n "${CUSTOM_KEYWORDS:-}" ]; then
        local IFS='|' i=1
        for kw in $CUSTOM_KEYWORDS; do
            [ -z "$kw" ] && continue
            echo -e "    ${green}[$i]${plain} ${white}${kw}${plain}"
            i=$((i + 1))
        done
    else
        echo -e "    ${gray}(Ninguna)${plain}"
    fi

    if [ -n "${CUSTOM_PORTS:-}" ] || [ -n "${CUSTOM_KEYWORDS:-}" ]; then
        echo -e "\n  ${white}Paquetes bloqueados en reglas personalizadas:${plain} ${cyan}$(count_blocked_packets "$CHAIN_CUSTOM")${plain}"
    fi
    ui_line
    pause
}

add_custom_port() {
    load_fw_conf
    ui_title "BLOQUEAR PUERTO PERSONALIZADO"
    echo -e "  ${gray}Ejemplos: 853 (DoT) o rango 6881:6999. Puerto 22 protegido.${plain}\n"
    read -r -p "$(echo -e "  ${green}► Puerto o rango a bloquear: ${plain}")" port_in
    port_in=$(echo "$port_in" | tr -d '[:space:]')
    [ -z "$port_in" ] && return

    local rc=0
    is_valid_port_spec "$port_in" || rc=$?
    if [ "$rc" -eq 2 ]; then
        echo -e "  ${red}✖ Protección activa: no se permite bloquear el puerto SSH 22.${plain}"
        pause; return
    elif [ "$rc" -ne 0 ]; then
        echo -e "  ${red}✖ Formato inválido. Usa un puerto (1-65535) o rango inicio:fin.${plain}"
        pause; return
    fi

    if [[ ",${CUSTOM_PORTS}," == *",${port_in},"* ]]; then
        echo -e "  ${yellow}⚠ El puerto ${port_in} ya está en la lista.${plain}"
        pause; return
    fi

    CUSTOM_PORTS="${CUSTOM_PORTS:+${CUSTOM_PORTS},}${port_in}"
    save_fw_conf
    apply_fw_rules
    echo -e "  ${green}✔ Puerto ${port_in} (TCP/UDP) bloqueado correctamente.${plain}"
    pause
}

remove_custom_port() {
    load_fw_conf
    ui_title "DESBLOQUEAR PUERTO PERSONALIZADO"
    if [ -z "${CUSTOM_PORTS:-}" ]; then
        echo -e "  ${yellow}No hay puertos personalizados bloqueados.${plain}"
        pause; return
    fi

    local IFS=',' i=1
    local -a arr=()
    for p in $CUSTOM_PORTS; do
        [ -z "$p" ] && continue
        arr+=("$p")
        echo -e "  ${green}[$i]${plain} Puerto ${cyan}${p}${plain}"
        i=$((i + 1))
    done
    ui_subline
    read -r -p "$(echo -e "  ${white}Número a desbloquear (0 cancelar): ${plain}")" idx
    [[ ! "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#arr[@]}" ] && return

    local target="${arr[$((idx - 1))]}"
    local new_list=""
    for p in "${arr[@]}"; do
        [ "$p" = "$target" ] && continue
        new_list="${new_list:+${new_list},}${p}"
    done
    CUSTOM_PORTS="$new_list"
    save_fw_conf
    apply_fw_rules
    echo -e "  ${green}✔ Puerto ${target} desbloqueado.${plain}"
    pause
}

add_custom_keyword() {
    load_fw_conf
    ui_title "BLOQUEAR PALABRA CLAVE / DOMINIO"
    if ! has_xt_string; then
        echo -e "  ${red}✖ Tu kernel no soporta el módulo xt_string para filtrado por texto.${plain}"
        pause; return
    fi
    echo -e "  ${gray}Ejemplo: thepiratebay.org, utorrent, etc. (mínimo 3 caracteres)${plain}\n"
    read -r -p "$(echo -e "  ${green}► Palabra clave o dominio a bloquear: ${plain}")" kw
    kw=$(echo "$kw" | tr -d '|"\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ "${#kw}" -lt 3 ]; then
        echo -e "  ${red}✖ Debe tener al menos 3 caracteres para evitar falsos positivos.${plain}"
        pause; return
    fi

    if [[ "|${CUSTOM_KEYWORDS}|" == *"|${kw}|"* ]]; then
        echo -e "  ${yellow}⚠ '${kw}' ya está bloqueado.${plain}"
        pause; return
    fi

    CUSTOM_KEYWORDS="${CUSTOM_KEYWORDS:+${CUSTOM_KEYWORDS}|}${kw}"
    save_fw_conf
    apply_fw_rules
    echo -e "  ${green}✔ Palabra clave '${kw}' bloqueada correctamente.${plain}"
    pause
}

remove_custom_keyword() {
    load_fw_conf
    ui_title "DESBLOQUEAR PALABRA CLAVE PERSONALIZADA"
    if [ -z "${CUSTOM_KEYWORDS:-}" ]; then
        echo -e "  ${yellow}No hay palabras clave personalizadas bloqueadas.${plain}"
        pause; return
    fi

    local IFS='|' i=1
    local -a arr=()
    for kw in $CUSTOM_KEYWORDS; do
        [ -z "$kw" ] && continue
        arr+=("$kw")
        echo -e "  ${green}[$i]${plain} ${white}${kw}${plain}"
        i=$((i + 1))
    done
    ui_subline
    read -r -p "$(echo -e "  ${white}Número a desbloquear (0 cancelar): ${plain}")" idx
    [[ ! "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#arr[@]}" ] && return

    local target="${arr[$((idx - 1))]}"
    local new_list=""
    for kw in "${arr[@]}"; do
        [ "$kw" = "$target" ] && continue
        new_list="${new_list:+${new_list}|}${kw}"
    done
    CUSTOM_KEYWORDS="$new_list"
    save_fw_conf
    apply_fw_rules
    echo -e "  ${green}✔ Palabra clave '${target}' desbloqueada.${plain}"
    pause
}

show_fw_menu() {
    while true; do
        load_fw_conf
        local b_tor="${red}[OFF]${plain}" b_spm="${red}[OFF]${plain}"
        [ "${BLOCK_TORRENT:-0}" = "1" ] && b_tor="${green}[ON]${plain}"
        [ "${BLOCK_SPAM:-0}" = "1" ] && b_spm="${green}[ON]${plain}"

        draw_header
        echo -e "  ${yellow}ESCUDO ANTI-TORRENT, ANTI-SPAM Y FIREWALL${plain}"
        echo -e "  ${white}Torrent/P2P: ${b_tor}  ${gray}│${plain}  ${white}Puertos SPAM: ${b_spm}"
        ui_subline
        echo -e "  ${cyan}[0]${plain}  Ver lista actual de prohibidos y contadores"
        ui_subline
        echo -e "  ${green}[1]${plain}  Bloquear Torrent y firmas P2P"
        echo -e "  ${green}[2]${plain}  Bloquear Puertos SPAM (SMTP 25/465/587/445)"
        echo -e "  ${green}[3]${plain}  Bloquear Torrent + Puertos SPAM ${gray}(Recomendado)${plain}"
        echo -e "  ${green}[4]${plain}  Bloquear Puerto personalizado"
        echo -e "  ${green}[5]${plain}  Bloquear Palabra Clave / Dominio personalizado"
        ui_subline
        echo -e "  ${yellow}[6]${plain}  Desbloquear Torrent y firmas P2P"
        echo -e "  ${yellow}[7]${plain}  Desbloquear Puertos SPAM"
        echo -e "  ${yellow}[8]${plain}  Desbloquear Torrent + Puertos SPAM"
        echo -e "  ${yellow}[9]${plain}  Desbloquear Puerto personalizado"
        echo -e "  ${yellow}[10]${plain} Desbloquear Palabra Clave personalizada"
        echo -e "  ${red}[11]${plain} Desbloquear TODAS las Palabras Clave personalizadas"
        ui_subline
        echo -e "  ${white}[99]${plain} Volver a Protocolos VPN"
        ui_line
        read -r -p "$(echo -e "${white}Por favor ingrese un número [0-11 / 99]: ${plain}")" opt_fw

        case "$opt_fw" in
            0) show_blocked_list ;;
            1)
                BLOCK_TORRENT=1; save_fw_conf; apply_fw_rules
                echo -e "\n  ${green}✔ Bloqueo Anti-Torrent / P2P activado.${plain}"; sleep 1
                ;;
            2)
                BLOCK_SPAM=1; save_fw_conf; apply_fw_rules
                echo -e "\n  ${green}✔ Bloqueo de Puertos SPAM activado.${plain}"; sleep 1
                ;;
            3)
                BLOCK_TORRENT=1; BLOCK_SPAM=1; save_fw_conf; apply_fw_rules
                echo -e "\n  ${green}✔ Protección completa (Torrent + SPAM) activada.${plain}"; sleep 1
                ;;
            4) add_custom_port ;;
            5) add_custom_keyword ;;
            6)
                BLOCK_TORRENT=0; save_fw_conf; apply_fw_rules
                echo -e "\n  ${yellow}● Bloqueo Anti-Torrent desactivado.${plain}"; sleep 1
                ;;
            7)
                BLOCK_SPAM=0; save_fw_conf; apply_fw_rules
                echo -e "\n  ${yellow}● Bloqueo de Puertos SPAM desactivado.${plain}"; sleep 1
                ;;
            8)
                BLOCK_TORRENT=0; BLOCK_SPAM=0; save_fw_conf; apply_fw_rules
                echo -e "\n  ${yellow}● Bloqueos Torrent y SPAM desactivados.${plain}"; sleep 1
                ;;
            9) remove_custom_port ;;
            10) remove_custom_keyword ;;
            11)
                CUSTOM_KEYWORDS=""; save_fw_conf; apply_fw_rules
                echo -e "\n  ${yellow}● Todas las palabras clave personalizadas eliminadas.${plain}"; sleep 1
                ;;
            99|q|Q|"") break ;;
            *) echo -e "  ${red}Opción inválida.${plain}"; sleep 1 ;;
        esac
    done
}

# =========================================================================
# Punto de entrada CLI / Systemd / Menú Interactivo
# =========================================================================
case "${1:-}" in
    --apply)
        apply_fw_rules
        ;;
    --enable-default)
        load_fw_conf
        BLOCK_TORRENT=1
        BLOCK_SPAM=1
        save_fw_conf
        apply_fw_rules
        ;;
    --disable-runtime)
        disable_fw_runtime
        ;;
    --disable-all)
        disable_fw_runtime
        systemctl stop joif-firewall.service >/dev/null 2>&1 || true
        systemctl disable joif-firewall.service >/dev/null 2>&1 || true
        rm -f "$FW_SERVICE" "$FW_CONF" "$FW_BIN"
        systemctl daemon-reload >/dev/null 2>&1 || true
        ;;
    --status)
        load_fw_conf
        if [ "${BLOCK_TORRENT:-0}" = "1" ] || [ "${BLOCK_SPAM:-0}" = "1" ] || [ -n "${CUSTOM_PORTS:-}" ] || [ -n "${CUSTOM_KEYWORDS:-}" ]; then
            echo "ON"
            exit 0
        else
            echo "OFF"
            exit 1
        fi
        ;;
    *)
        show_fw_menu
        ;;
esac
