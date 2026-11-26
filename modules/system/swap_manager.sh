#!/bin/bash
# =========================================================================
# JOIF Cloud v2.0 — Gestor de Memoria SWAP (Asistente en 1 Paso)
# =========================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../core/utils.sh" 2>/dev/null || source /root/joif-core/core/utils.sh 2>/dev/null

SWAP_FILE="/swapfile"

crear_y_activar_swap() {
    local size_gb="$1"
    echo -e "\n${yellow}[*] Configurando SWAP de ${size_gb}GB en ${SWAP_FILE}...${plain}"

    if [ -f "$SWAP_FILE" ]; then
        swapoff "$SWAP_FILE" 2>/dev/null || true
        sed -i "\|${SWAP_FILE}|d" /etc/fstab
        rm -f "$SWAP_FILE"
    fi

    if ! fallocate -l "${size_gb}G" "$SWAP_FILE" 2>/dev/null; then
        dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$((size_gb * 1024))" status=progress
    fi

    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE" >/dev/null 2>&1
    swapon "$SWAP_FILE"

    grep -qF "$SWAP_FILE" /etc/fstab || echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab

    sysctl -w vm.swappiness=20 >/dev/null 2>&1 || true
    echo "vm.swappiness=20" > /etc/sysctl.d/98-joif-swap.conf

    echo -e "  ${green}✔ SWAP de ${size_gb}GB creada, activada de forma permanente y optimizada (swappiness=20).${plain}"
    pause
}

eliminar_swap() {
    echo -e "\n${yellow}[*] Desactivando y eliminando ${SWAP_FILE}...${plain}"
    swapoff "$SWAP_FILE" 2>/dev/null || true
    sed -i "\|${SWAP_FILE}|d" /etc/fstab 2>/dev/null || true
    rm -f "$SWAP_FILE" /etc/sysctl.d/98-joif-swap.conf
    echo -e "  ${green}✔ Memoria SWAP eliminada correctamente.${plain}"
    pause
}

while true; do
    ui_title "GESTOR DE MEMORIA VIRTUAL SWAP"
    local_swap=$(free -h 2>/dev/null | awk '/^Swap:/ {print $3 " / " $2}')
    cur_swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "60")
    echo -e "  ${gray}SWAP actual:${plain} ${white}${local_swap:-N/A}${plain}   ${gray}│   Swappiness:${plain} ${cyan}${cur_swappiness}${plain}"
    ui_subline
    echo -e "  ${green}[1]${plain} Crear y activar SWAP de 2 GB (recomendado para VPS 1–2 GB RAM)"
    echo -e "  ${green}[2]${plain} Crear y activar SWAP de 4 GB"
    echo -e "  ${green}[3]${plain} Crear y activar SWAP de 8 GB"
    echo -e "  ${yellow}[4]${plain} Cambiar prioridad swappiness (actual: ${cur_swappiness})"
    echo -e "  ${red}[5]${plain} Desactivar y eliminar archivo SWAP"
    echo -e "  ${white}[0]${plain} Volver"
    ui_line
    read -r -p "$(echo -e "${white}Selecciona una opción: ${plain}")" opt_sw

    case "$opt_sw" in
        1) crear_y_activar_swap 2 ;;
        2) crear_y_activar_swap 4 ;;
        3) crear_y_activar_swap 8 ;;
        4)
            read -r -p "$(echo -e "${white}Nuevo valor de swappiness [1-100] (recomendado 20): ${plain}")" sw_val
            if [[ "$sw_val" =~ ^[0-9]+$ ]] && (( sw_val >= 1 && sw_val <= 100 )); then
                sysctl -w "vm.swappiness=${sw_val}" >/dev/null 2>&1 || true
                echo "vm.swappiness=${sw_val}" > /etc/sysctl.d/98-joif-swap.conf
                echo -e "  ${green}✔ Swappiness configurado en ${sw_val}.${plain}"
            else
                echo -e "  ${red}✖ Valor inválido.${plain}"
            fi
            pause
            ;;
        5) eliminar_swap ;;
        0|00) break ;;
        *) echo -e "  ${red}Opción inválida.${plain}"; sleep 1 ;;
    esac
done
