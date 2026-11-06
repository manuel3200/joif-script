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
    echo -e " ∘ SSH: 22             ∘ System-DNS: 53"
    echo -e " ∘ SOCKS/PYTHON3: 80   ∘ WEB-NGinx: 81"
    echo -e " ∘ BadVPN: 7200        ∘ BadVPN: 7300"
    echo -e " ∘ CheckUser API: 3000"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ∘ TOTAL: ${white}${RAM_TOTAL}M${plain} ∘  M|LIBRE: ${white}${RAM_FREE}M${plain}  ∘  EN USO: ${white}${RAM_USED}M${plain}"
    echo -e " ∘ U/RAM: ${white}${RAM_PERCENT}%${plain}  ∘ U/CPU: ${white}${CPU_USAGE}%${plain}  ∘ CLIENTES ONLINE: ${green}${ONLINE_USERS}${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
}

pause() {
    echo -e "\n${cyan}Presiona [Enter] para continuar...${plain}"
    read -r
}
