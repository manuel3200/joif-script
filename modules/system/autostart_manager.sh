#!/bin/bash
# =========================================================
# JOIF Cloud - Gestor de Autoinicio de Menú al Entrar por SSH
# =========================================================

source /root/joif-core/core/utils.sh 2>/dev/null

BASHRC="/root/.bashrc"
AUTOSTART_LINE="[ -f /usr/bin/menu ] && /usr/bin/menu"

is_autostart_enabled() {
    grep -Fq "$AUTOSTART_LINE" "$BASHRC" 2>/dev/null
}

toggle_autostart() {
    if is_autostart_enabled; then
        # Desactivar
        sed -i "\|$AUTOSTART_LINE|d" "$BASHRC"
        echo -e "\n${yellow}🔒 Autoinicio de menú DESACTIVADO.${plain}"
        echo -e "${white}Al entrar por SSH, verás la consola bash estándar.${plain}"
    else
        # Activar
        sed -i "\|$AUTOSTART_LINE|d" "$BASHRC"
        echo "$AUTOSTART_LINE" >> "$BASHRC"
        echo -e "\n${green}⚡ Autoinicio de menú ACTIVADO.${plain}"
        echo -e "${white}Cada vez que inicies sesión como root, se abrirá el menú automáticamente.${plain}"
    fi
    sleep 2
}

while true; do
    clear
    draw_header
    echo -e "${yellow}          [ AUTOINICIAR SCRIPT AL ENTRAR POR SSH ]${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    if is_autostart_enabled; then
        echo -e " Estado actual: ${green}ACTIVADO (ON)${plain}"
        echo -e " El menú se abrirá automáticamente al iniciar sesión en el VPS."
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e " ${red}[1]${plain} > Desactivar autoinicio (Usar consola bash normal)"
    else
        echo -e " Estado actual: ${red}DESACTIVADO (OFF)${plain}"
        echo -e " Actualmente entras a la consola bash estándar."
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e " ${green}[1]${plain} > Activar autoinicio automático del menú"
    fi
    echo -e " ${white}[0]${plain} > Volver"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    read -p "$(echo -e ${white}"Selecciona una opción: "${plain})" opt_auto

    case $opt_auto in
        1)
            toggle_autostart
            ;;
        0)
            break
            ;;
        *)
            echo -e "${red}Opción inválida.${plain}"
            sleep 1
            ;;
    esac
done
