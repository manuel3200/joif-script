#!/bin/bash
# =========================================================
# JOIF Cloud - Limpiador del Sistema y Optimización de Memoria
# =========================================================

source /root/joif-core/core/utils.sh 2>/dev/null

while true; do
    clear
    draw_header
    echo -e "${yellow}             [ LIMPIEZA Y OPTIMIZACIÓN DE VPS ]${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${green}[1]${plain} > 🧹 Limpiar Caché de RAM (drop_caches)"
    echo -e " ${green}[2]${plain} > 📦 Limpiar paquetes huérfanos y caché APT"
    echo -e " ${green}[3]${plain} > 📜 Truncar registros y logs antiguos (/var/log)"
    echo -e " ${green}[4]${plain} > 🚀 LIMPIEZA COMPLETA PROFUNDA (Todo en uno)"
    echo -e " ${white}[0]${plain} > Volver"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    read -p "$(echo -e ${white}"Selecciona una opción: "${plain})" opt_clean

    case $opt_clean in
        1)
            echo -e "\n${yellow}[*] Liberando memoria RAM de buffers y caché...${plain}"
            sync; echo 3 > /proc/sys/vm/drop_caches
            echo -e "${green}✔ Caché de RAM liberada exitosamente.${plain}"
            pause
            ;;
        2)
            echo -e "\n${yellow}[*] Limpiando paquetes y repositorios...${plain}"
            apt-get clean -y >/dev/null 2>&1
            apt-get autoremove -y >/dev/null 2>&1
            echo -e "${green}✔ Paquetes temporales y huérfanos eliminados.${plain}"
            pause
            ;;
        3)
            echo -e "\n${yellow}[*] Vaciando registros masivos...${plain}"
            journalctl --vacuum-time=3d >/dev/null 2>&1
            if [ -f /var/log/joif-limitador.log ]; then
                tail -n 100 /var/log/joif-limitador.log > /tmp/limitador.tmp && mv /tmp/limitador.tmp /var/log/joif-limitador.log
            fi
            echo -e "${green}✔ Logs reducidos y optimizados.${plain}"
            pause
            ;;
        4)
            echo -e "\n${yellow}[*] Ejecutando Limpieza Completa Profunda...${plain}"
            sync; echo 3 > /proc/sys/vm/drop_caches
            apt-get clean -y >/dev/null 2>&1
            apt-get autoremove -y >/dev/null 2>&1
            journalctl --vacuum-time=3d >/dev/null 2>&1
            if [ -f /var/log/joif-limitador.log ]; then
                tail -n 100 /var/log/joif-limitador.log > /tmp/limitador.tmp && mv /tmp/limitador.tmp /var/log/joif-limitador.log
            fi
            echo -e "${green}✔ ¡Limpieza profunda completada al 100%!${plain}"
            pause
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
