#!/bin/bash
# =========================================================================
# JOIF Cloud v2.0 — Core UI, Telemetría Rápida y Utilidades Seguras
# =========================================================================

# Paleta visual unificada (JOIF TUI v2 — 60 columnas)
export red="\e[1;31m"
export green="\e[1;32m"
export yellow="\e[1;33m"
export blue="\e[1;34m"
export magenta="\e[1;35m"
export cyan="\e[1;36m"
export white="\e[1;37m"
export gray="\e[0;90m"
export plain="\e[0m"

export JOIF_DIR="/root/joif-core"
export JOIF_ENV="${JOIF_DIR}/.env"
export JOIF_DB="${JOIF_DIR}/database.sqlite"
export JOIF_IP_CACHE="/run/joif_public_ip"

# =========================================================================
# Helpers de UI (60 columnas consistentes)
# =========================================================================
ui_line() {
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
}

ui_subline() {
    echo -e "${gray}────────────────────────────────────────────────────────────${plain}"
}

print_separator() {
    ui_line
}

ui_title() {
    local title="$1"
    clear
    ui_line
    echo -e "  ${cyan}JOIF CLOUD${plain} ${gray}│${plain} ${yellow}${title}${plain}"
    ui_line
}

pause() {
    echo ""
    read -r -p "$(echo -e "${gray}Presiona [Enter] para continuar...${plain}")"
}

ui_bar() {
    local pct="${1:-0}"
    pct="${pct%%.*}"
    [[ ! "$pct" =~ ^[0-9]+$ ]] && pct=0
    (( pct > 100 )) && pct=100
    local filled=$(( pct / 10 ))
    local empty=$(( 10 - filled ))
    local color="$green"
    (( pct >= 70 )) && color="$yellow"
    (( pct >= 90 )) && color="$red"
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo -e "${color}[${bar}]${plain} ${white}${pct}%${plain}"
}

# =========================================================================
# Telemetría rápida (< 15 ms, sin llamadas bloqueantes por cada pantalla)
# =========================================================================
get_cached_public_ip() {
    local now_ts
    now_ts=$(date +%s)
    if [ -f "$JOIF_IP_CACHE" ]; then
        local mtime
        mtime=$(stat -c %Y "$JOIF_IP_CACHE" 2>/dev/null || echo 0)
        if (( now_ts - mtime < 3600 )); then
            local cached
            cached=$(tr -d '[:space:]' < "$JOIF_IP_CACHE" 2>/dev/null || true)
            if [ -n "$cached" ]; then
                echo "$cached"
                return
            fi
        fi
    fi
    local ip
    ip=$(curl -fsS --connect-timeout 2 --max-time 2 https://api.ipify.org 2>/dev/null \
        || curl -fsS --connect-timeout 2 --max-time 2 https://ifconfig.me 2>/dev/null \
        || hostname -I 2>/dev/null | awk '{print $1}')
    ip="${ip:-127.0.0.1}"
    echo "$ip" > "$JOIF_IP_CACHE" 2>/dev/null || true
    echo "$ip"
}

get_online_users() {
    if command -v ps >/dev/null 2>&1; then
        ps -eo user:32,args 2>/dev/null | awk '
            $1 != "root" && $1 != "USER" && ($0 ~ /sshd|dropbear/) && $0 !~ /\[(priv|net|accepted)\]|listener|awk/ { c++ }
            END { print c + 0 }
        '
    else
        echo "0"
    fi
}

get_sys_info() {
    if [ -f /etc/os-release ]; then
        OS=$(grep -m1 '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2 | awk '{print $1, $2}')
    else
        OS="Linux"
    fi

    IP=$(get_cached_public_ip)
    DOMAIN=$(cat /root/.JOIF_domain 2>/dev/null | tr -d '\r\n ')
    [ -z "$DOMAIN" ] && DOMAIN="$IP"

    if [ -r /proc/meminfo ]; then
        read -r RAM_TOTAL RAM_FREE RAM_USED RAM_PERCENT < <(awk '
            /^MemTotal:/     { t = $2 }
            /^MemAvailable:/ { a = $2 }
            /^MemFree:/      { f = $2 }
            END {
                if (a == 0) a = f
                tm = int(t / 1024); fm = int(a / 1024); um = tm - fm; if (um < 0) um = 0
                pct = (tm > 0) ? int((um * 100) / tm) : 0
                printf "%d %d %d %d\n", tm, fm, um, pct
            }
        ' /proc/meminfo)
    else
        RAM_TOTAL=0; RAM_FREE=0; RAM_USED=0; RAM_PERCENT=0
    fi

    CPUS=$(nproc 2>/dev/null || echo 1)
    if [ -r /proc/loadavg ]; then
        local load1
        load1=$(awk '{print $1}' /proc/loadavg)
        CPU_USAGE=$(awk -v l="$load1" -v c="$CPUS" 'BEGIN { p = int((l / (c > 0 ? c : 1)) * 100); if (p > 100) p = 100; print p }')
    else
        CPU_USAGE=0
    fi

    BASE_ARCH=$(uname -m)
    DATE_STR=$(date +"%d/%m/%Y %H:%M")
    ONLINE_USERS=$(get_online_users)
}

get_api_port() {
    local p
    p=$(grep -m1 '^PORT=' "$JOIF_ENV" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r\n ')
    echo "${p:-3000}"
}

get_api_key() {
    grep -m1 '^API_KEY=' "$JOIF_ENV" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r\n '
}

generate_random_api_key() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 24
    else
        head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

# =========================================================================
# Helpers de Seguridad: OpenSSH, Firewall Idempotente y API Local
# =========================================================================
safe_reload_ssh() {
    mkdir -p /run/sshd 2>/dev/null || true
    chmod 0755 /run/sshd 2>/dev/null || true
    if ! sshd -t 2>/dev/null; then
        echo -e " ${red}✖ Error: sshd -t falló. No se reinició SSH para proteger el acceso.${plain}"
        return 1
    fi
    systemctl reload ssh 2>/dev/null \
        || systemctl reload sshd 2>/dev/null \
        || systemctl restart ssh 2>/dev/null \
        || systemctl restart sshd 2>/dev/null
}

ensure_firewall_port() {
    local port="$1"
    local proto="${2:-tcp}"
    if command -v iptables >/dev/null 2>&1; then
        iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT >/dev/null 2>&1 \
            || iptables -I INPUT 1 -p "$proto" --dport "$port" -j ACCEPT >/dev/null 2>&1 \
            || true
    fi
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${port}/${proto}" >/dev/null 2>&1 || true
    fi
}

persist_firewall() {
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1 || true
    elif command -v iptables-save >/dev/null 2>&1; then
        mkdir -p /etc/iptables 2>/dev/null || true
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
}

# Llama a la API local (única fuente de verdad). Exporta API_HTTP_CODE y API_BODY.
joif_api_call() {
    local method="$1"
    local route="$2"
    local data="${3:-}"
    local port key resp
    port=$(get_api_port)
    key=$(get_api_key)

    if [ -n "$data" ]; then
        resp=$(curl -sS --max-time 8 -w "\n%{http_code}" -X "$method" \
            "http://127.0.0.1:${port}${route}" \
            -H "Content-Type: application/json" \
            -H "x-api-key: ${key}" \
            -d "$data" 2>/dev/null || printf '\n000')
    else
        resp=$(curl -sS --max-time 8 -w "\n%{http_code}" -X "$method" \
            "http://127.0.0.1:${port}${route}" \
            -H "x-api-key: ${key}" 2>/dev/null || printf '\n000')
    fi

    API_HTTP_CODE=$(printf '%s' "$resp" | tail -n1)
    API_BODY=$(printf '%s' "$resp" | sed '$d')
}

# =========================================================================
# Dashboard y Puertos Activos
# =========================================================================
draw_active_ports() {
    local -a items=()
    local raw=""
    if command -v ss >/dev/null 2>&1; then
        raw=$(ss -tulpn 2>/dev/null | grep -E 'LISTEN|UNCONN' || true)
    fi

    if echo "$raw" | grep -qE '(:22[[:space:]]|:22$|sshd)'; then
        items+=("${green}●${plain} SSH :22")
    fi
    if echo "$raw" | grep -qi 'dropbear'; then
        local dp
        dp=$(echo "$raw" | grep -i 'dropbear' | grep -oE ':[0-9]+' | tr -d ':' | head -n1)
        items+=("${green}●${plain} Dropbear :${dp:-143}")
    fi
    if echo "$raw" | grep -qE '(:80[[:space:]]|:80$)'; then
        items+=("${green}●${plain} WS-Proxy :80")
    fi
    if echo "$raw" | grep -qE '(:443[[:space:]]|:443$)'; then
        items+=("${green}●${plain} SSL/TLS :443")
    fi
    local api_port
    api_port=$(get_api_port)
    if echo "$raw" | grep -qE "(:${api_port}[[:space:]]|:${api_port}\$)"; then
        items+=("${green}●${plain} CheckUser :${api_port}")
    fi
    if echo "$raw" | grep -qE '(:7300[[:space:]]|:7300$)'; then
        items+=("${green}●${plain} BadVPN :7300")
    fi
    if echo "$raw" | grep -qE '(:7200[[:space:]]|:7200$)'; then
        items+=("${green}●${plain} BadVPN :7200")
    fi
    if iptables -t nat -C OUTPUT -j JOIF_SMARTDNS_OUT >/dev/null 2>&1; then
        items+=("${cyan}●${plain} SmartDNS AR")
    fi
    if sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | grep -qx 'bbr'; then
        items+=("${cyan}●${plain} TCP BBR")
    fi

    local total=${#items[@]}
    if [ "$total" -eq 0 ]; then
        echo -e "  ${yellow}○ Sin servicios activos detectados${plain}"
        return
    fi
    for ((i=0; i<total; i+=2)); do
        local c1="${items[i]}"
        if (( i + 1 < total )); then
            local c2="${items[i+1]}"
            printf "  %-36b  %b\n" "$c1" "$c2"
        else
            printf "  %b\n" "$c1"
        fi
    done
}

draw_header() {
    clear
    get_sys_info
    local ram_bar
    ram_bar=$(ui_bar "$RAM_PERCENT")
    local total_accounts="0"
    if [ -f "$JOIF_DB" ] && command -v sqlite3 >/dev/null 2>&1; then
        total_accounts=$(sqlite3 "$JOIF_DB" "SELECT COUNT(*) FROM users WHERE status='active';" 2>/dev/null || echo "0")
    fi

    ui_line
    echo -e "  ${cyan}JOIF CLOUD${plain} ${white}v2.0${plain}  ${gray}│${plain}  ${white}${DOMAIN}${plain} ${gray}(${IP})${plain}"
    ui_subline
    echo -e "  ${gray}SO:${plain} ${white}${OS}${plain} ${gray}(${BASE_ARCH})${plain}   ${gray}CPU:${plain} ${white}${CPUS}c (${CPU_USAGE}%)${plain}   ${gray}${DATE_STR}${plain}"
    echo -e "  ${gray}RAM:${plain} ${ram_bar} ${gray}(${RAM_USED}M/${RAM_TOTAL}M)${plain}  ${gray}│${plain}  ${gray}Online:${plain} ${green}${ONLINE_USERS}${plain} ${gray}/${plain} ${white}${total_accounts}${plain}"
    ui_subline
    draw_active_ports
    ui_line
}
