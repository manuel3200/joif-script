#!/bin/bash

# =========================================================================
# JOIF Cloud - Utilidades Base
# =========================================================================

# Colores globales
export red="\e[1;31m"
export green="\e[1;32m"
export yellow="\e[1;33m"
export blue="\e[1;34m"
export magenta="\e[1;35m"
export cyan="\e[1;36m"
export white="\e[1;37m"
export plain="\e[0m"

# Función común para limpiar pantalla y mostrar un separador rojo
print_separator() {
    echo -e "${red}============================================================${plain}"
}
# Funciones de sistema
get_sys_info() {
    if [ -f /etc/os-release ]; then
        OS=$(grep -E '^(PRETTY_NAME)=' /etc/os-release | cut -d'"' -f2 | cut -d' ' -f1,2)
    else
        OS="Linux"
    fi
    IP=$(curl -s ifconfig.me || echo "Local")
    
    RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    RAM_USED=$(free -m | awk 'NR==2{print $3}')
    RAM_FREE=$(free -m | awk 'NR==2{if($7!="") print $7; else print $4}')
    RAM_BUFF=$(free -m | awk 'NR==2{print $6}')
    if [ "$RAM_TOTAL" -gt 0 ]; then
        RAM_PERCENT=$(awk "BEGIN {printf \"%.2f\", ($RAM_USED/$RAM_TOTAL)*100}")
    else
        RAM_PERCENT="0.00"
    fi
    
    CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print $1}')
    if [ -n "$CPU_IDLE" ]; then
        CPU_USAGE=$(awk "BEGIN {printf \"%.0f\", 100 - $CPU_IDLE}")
    else
        CPU_USAGE="0"
    fi
    
    BASE_ARCH=$(uname -m)
    CPUS=$(nproc)
    DATE_STR=$(date +"%d/%m/%Y-%H:%M")
    ONLINE_USERS=$(get_online_users)
}

get_online_users() {
    local count=0
    if command -v ps &>/dev/null; then
        count=$(ps -eo command 2>/dev/null | awk '/sshd:|dropbear/ && !/root/ && !/grep/ && !/\[priv\]/ && !/listener/ {print $0}' | wc -l)
    fi
    echo "$count"
}

draw_active_ports() {
    local -a items=()
    local raw=""
    if command -v ss &>/dev/null; then
        raw=$(ss -tulpn 2>/dev/null | grep -E 'LISTEN|UNCONN')
    elif command -v lsof &>/dev/null; then
        raw=$(lsof -V -i -P -n 2>/dev/null | grep -E 'LISTEN|UDP')
    fi

    # 1. SSH
    if echo "$raw" | grep -E '(:22[[:space:]]|:22$|sshd|/ssh)' &>/dev/null; then
        local p=$(echo "$raw" | grep -E 'sshd|/ssh' | grep -oE ':[0-9]+' | tr -d ':' | sort -nu | head -n1)
        [[ -z "$p" ]] && p=22
        items+=("SSH: ${p}")
    fi

    # 2. Dropbear
    if echo "$raw" | grep -i 'dropbear' &>/dev/null; then
        local p=$(echo "$raw" | grep -i 'dropbear' | grep -oE ':[0-9]+' | tr -d ':' | sort -nu | head -n1)
        items+=("Dropbear: ${p}")
    fi

    # 3. WS-Proxy / Python SOCKS / Web (Port 80)
    if echo "$raw" | grep -E '(:80[[:space:]]|:80$)' &>/dev/null; then
        if echo "$raw" | grep -E '(:80[[:space:]]|:80$)' | grep -E 'node|proxy' &>/dev/null; then
            items+=("WS-Epro: 80")
        elif echo "$raw" | grep -E '(:80[[:space:]]|:80$)' | grep -E 'python' &>/dev/null; then
            items+=("SOCKS/PYTHON: 80")
        elif echo "$raw" | grep -E '(:80[[:space:]]|:80$)' | grep -i 'nginx' &>/dev/null; then
            items+=("WEB-NGinx: 80")
        elif echo "$raw" | grep -E '(:80[[:space:]]|:80$)' | grep -i 'apache' &>/dev/null; then
            items+=("APACHE: 80")
        else
            items+=("Proxy(WS): 80")
        fi
    fi

    # 4. CheckUser API (Port 3000)
    if echo "$raw" | grep -E '(:3000[[:space:]]|:3000$)' &>/dev/null; then
        items+=("CheckUser API: 3000")
    fi

    # 5. SSL / TLS / Stunnel (Port 443)
    if echo "$raw" | grep -E '(:443[[:space:]]|:443$)' &>/dev/null; then
        items+=("SSL/TLS: 443")
    fi

    # 6. WEB Nginx / Apache (Port 81)
    if echo "$raw" | grep -E '(:81[[:space:]]|:81$)' &>/dev/null; then
        items+=("WEB-NGinx: 81")
    fi

    # 7. BadVPN UDPGW (7200 / 7300)
    if echo "$raw" | grep -E '(:7200[[:space:]]|:7200$)' &>/dev/null; then
        items+=("BadVPN: 7200")
    fi
    if echo "$raw" | grep -E '(:7300[[:space:]]|:7300$)' &>/dev/null; then
        items+=("BadVPN: 7300")
    fi

    # 8. System-DNS (Port 53)
    if echo "$raw" | grep -E '(:53[[:space:]]|:53$)' &>/dev/null; then
        items+=("System-DNS: 53")
    fi

    # 9. SlowDNS (Port 5300)
    if echo "$raw" | grep -E '(:5300[[:space:]]|:5300$)' &>/dev/null; then
        items+=("SlowDNS: 5300")
    fi

    # 10. OpenVPN (Port 1194 u otros)
    if echo "$raw" | grep -i 'openvpn' &>/dev/null; then
        local p=$(echo "$raw" | grep -i 'openvpn' | grep -oE ':[0-9]+' | tr -d ':' | sort -nu | head -n1)
        [[ -z "$p" ]] && p=1194
        items+=("OpenVPN: ${p}")
    fi

    # 11. XRay / V2Ray
    if echo "$raw" | grep -E 'xray|v2ray' &>/dev/null; then
        local p=$(echo "$raw" | grep -E 'xray|v2ray' | grep -oE ':[0-9]+' | tr -d ':' | sort -nu | head -n1)
        items+=("XRay/V2Ray: ${p}")
    fi

    local total=${#items[@]}
    if [ "$total" -eq 0 ]; then
        echo -e " ${yellow}∘ Ningún puerto activo detectado${plain}"
        return
    fi

    for ((i=0; i<total; i+=2)); do
        local col1="${items[i]}"
        local col2=""
        if [ $((i+1)) -lt "$total" ]; then
            col2="${items[i+1]}"
            printf " ∘ %-23s ∘ %-23s\n" "$col1" "$col2"
        else
            printf " ∘ %-23s\n" "$col1"
        fi
    done
}

draw_header() {
    clear
    get_sys_info
    echo -e "${cyan}      =====>>►► ${green}🐲 JOIF 💥 Cloud 🐲${cyan} ◄◄<<=====${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ∘ S.O: ${white}$OS${plain}  ∘ Base:${white}$BASE_ARCH${plain} ∘ CPU's:${white}$CPUS${plain}"
    echo -e " ∘ IP: ${white}$IP${plain}  ∘ FECHA: ${white}$DATE_STR${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " Key: Verified【 ${yellow}TheJOIF ©${plain} 】(V1.5.0) "
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    draw_active_ports
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ∘ TOTAL: ${white}${RAM_TOTAL}M${plain} ∘  M|LIBRE: ${white}${RAM_FREE}M${plain}  ∘  EN USO: ${white}${RAM_USED}M${plain}"
    echo -e " ∘ U/RAM: ${white}${RAM_PERCENT}%${plain}  ∘ U/CPU: ${white}${CPU_USAGE}%${plain}  ∘ CLIENTES ONLINE: ${green}${ONLINE_USERS}${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
}

pause() {
    echo -e "\n${cyan}Presiona [Enter] para continuar...${plain}"
    read -r
}
