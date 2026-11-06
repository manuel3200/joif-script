#!/bin/bash

# =========================================================
# JOIF Cloud - Menú Herramientas Extras
# =========================================================

# Cargar utilidades (colores y funciones UI)
source /root/joif-core/core/utils.sh 2>/dev/null

while true; do
    clear
    echo -e "${red}============================================================${plain}"
    echo -e "${yellow}       ☯ MENU DE HERRAMIENTAS BETA (EXPERIMENTALES) ☯${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${green}[1]${plain} ➮ ⚡ Autoconfigurar VPS para Portal Web (Auto-Link)"
    echo -e " ${green}[5]${plain} ➮ Memoria SWAP Particion ( #BETA )"
    echo -e " ${red}[0]${plain} ➮ [ REGRESAR ]"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    read -p "$(echo -e ${white}" OPCION : "${plain})" opt_extra

    case $opt_extra in
        1)
            if command -v menu >/dev/null 2>&1; then
                bash -c "source /root/joif-core/core/utils.sh 2>/dev/null; source /root/joif-core/menu.sh; autoconfigurar_portal_web"
            elif [ -f "/root/joif-core/menu.sh" ]; then
                bash -c "source /root/joif-core/core/utils.sh 2>/dev/null; source /root/joif-core/menu.sh; autoconfigurar_portal_web"
            fi
            ;;
        5)
            # Carga dinámica del módulo
            if [ -f "/root/joif-core/modules/system/swap_manager.sh" ]; then
                bash /root/joif-core/modules/system/swap_manager.sh
            else
                echo -e "${red}Módulo no encontrado: /root/joif-core/modules/system/swap_manager.sh${plain}"
                sleep 2
            fi
            ;;
        0) break ;;
        *) echo -e "${red}Opción inválida${plain}"; sleep 1 ;;
    esac
done
