#!/bin/bash

# Cargar utilidades (colores y funciones UI)
source /root/joif-core/core/utils.sh 2>/dev/null
swap_file="/swapfile"

# Limpiar pantalla y mostrar cabecera intro (solo primera vez)
clear
echo -e "${red}============================================================${plain}"
echo -e "${white}Esto le ayudara a crear un archivo swap para su sistema${plain}"
echo -e "${red}============================================================${plain}"
echo -e "${green}Enter para continuar...${plain}"
read -p ""

while true; do
    clear
    echo -e "${red}============================================================${plain}"
    echo -e "${green}Seleccione una opcion${plain}"
    echo -e "${red}============================================================${plain}"
    echo -e "${green}1)${plain} Crear/Eliminar archivo"
    echo -e "${green}2)${plain} Comprovar archivo"
    echo -e "${green}3)${plain} Dar formato y permisos al archivo"
    echo -e "${green}4)${plain} Activar/Desactvar swap"
    echo -e "${green}5)${plain} Prioridad swap"
    echo ""
    echo -e "${green}0)${plain} Salir"
    echo -e "${red}============================================================${plain}"
    read -p "$(echo -e ${green}"Opcion:"${plain}) " opc

    case $opc in
        1)
            clear
            if [ -f "$swap_file" ]; then
                echo -e "${red}============================================================${plain}"
                echo -e "${white}Se encontro un archivo swap pre-existente${plain}"
                echo -e "${red}============================================================${plain}"
                echo -e "desea remover el archivo"
                echo ""
                echo -e "1) si"
                echo -e "2) no"
                echo -e "${red}============================================================${plain}"
                read -p "Opcion: " rm_opc
                if [ "$rm_opc" == "1" ]; then
                    swapoff $swap_file 2>/dev/null
                    sed -i "\|${swap_file}|d" /etc/fstab
                    rm -f $swap_file
                    echo "Archivo removido."
                    sleep 2
                fi
            else
                echo -e "${red}============================================================${plain}"
                echo -e "${white}se recomienda que la memoria swap${plain}"
                echo -e "${white}sea de almenos el doble de su memoria ram${plain}"
                echo -e "${red}============================================================${plain}"
                echo -e "Seleccione una opcion"
                echo ""
                echo -e "1) 2GB"
                echo -e "2) 4GB"
                echo -e "3) 8GB"
                echo ""
                echo -e "0) Regresar al inicio"
                echo -e "${red}============================================================${plain}"
                read -p "Opcion: " size_opc
                
                size="0"
                if [ "$size_opc" == "1" ]; then size="2G"; fi
                if [ "$size_opc" == "2" ]; then size="4G"; fi
                if [ "$size_opc" == "3" ]; then size="8G"; fi
                
                if [ "$size" != "0" ]; then
                    clear
                    echo -e "${red}============================================================${plain}"
                    echo -e "${white}Creando archivo swapfile${plain}"
                    echo -e "${red}============================================================${plain}"
                    fallocate -l $size $swap_file 2>/dev/null
                    if [ $? -ne 0 ]; then
                        # Si fallocate falla, usamos dd
                        mb=$(( ${size%G} * 1024 ))
                        dd if=/dev/zero of=$swap_file bs=1M count=$mb status=progress
                    fi
                    echo -e "${red}============================================================${plain}"
                    echo -e "Archivo creado"
                    echo -e "comprueve detalles en la opcion 2"
                    echo ""
                    read -p "Enter para continuar"
                fi
            fi
            ;;
        2)
            clear
            echo -e "${red}============================================================${plain}"
            echo -e "${white}Comprobando detalles del archivo${plain}"
            echo -e "${red}============================================================${plain}"
            if [ -f "$swap_file" ]; then
                ls -lh $swap_file
            else
                echo "El archivo swap no existe."
            fi
            echo -e "${red}============================================================${plain}"
            echo ""
            read -p "Enter para continuar"
            ;;
        3)
            clear
            echo -e "${red}============================================================${plain}"
            echo -e "${white}Asignando permisos y formato${plain}"
            echo -e "${red}============================================================${plain}"
            if [ -f "$swap_file" ]; then
                chmod 600 $swap_file
                mkswap $swap_file
            else
                echo "Primero debe crear el archivo en la opción 1."
            fi
            echo -e "${red}============================================================${plain}"
            echo -e "listo"
            echo ""
            read -p "Enter para continuar"
            ;;
        4)
            clear
            echo -e "${red}============================================================${plain}"
            echo -e "${white}Como desea activar la memoria swap${plain}"
            echo -e "${red}============================================================${plain}"
            echo -e "1) permanente"
            echo -e "2) temporal (asta el proximo reinicio)"
            echo -e "3) desactivar swap"
            echo ""
            echo -e "0) Regresar al inicio"
            echo -e "${red}============================================================${plain}"
            read -p "Opcion:" act_opc
            
            if [ "$act_opc" == "1" ]; then
                swapon $swap_file 2>/dev/null
                if ! grep -q "$swap_file" /etc/fstab; then
                    echo "$swap_file none swap sw 0 0" >> /etc/fstab
                fi
                clear
                echo -e "${red}============================================================${plain}"
                echo -e "${white}memoria swap activada${plain}"
                echo -e "${white}de forma permanente${plain}"
                echo -e "${red}============================================================${plain}"
                echo ""
                read -p "Enter para continuar"
            elif [ "$act_opc" == "2" ]; then
                swapon $swap_file 2>/dev/null
                clear
                echo -e "${red}============================================================${plain}"
                echo -e "${white}memoria swap activada${plain}"
                echo -e "${white}de forma temporal${plain}"
                echo -e "${red}============================================================${plain}"
                echo ""
                read -p "Enter para continuar"
            elif [ "$act_opc" == "3" ]; then
                swapoff $swap_file 2>/dev/null
                sed -i "\|${swap_file}|d" /etc/fstab
                echo "Swap desactivada."
                read -p "Enter para continuar"
            fi
            ;;
        5)
            clear
            echo -e "${red}============================================================${plain}"
            echo -e "${white}Asigne la prioridad swap${plain}"
            echo -e "${red}============================================================${plain}"
            echo -e "1) 10"
            echo -e "2) 20 (recomendado)"
            echo -e "3) 30"
            echo -e "4) 40"
            echo -e "5) 50"
            echo -e "6) 60"
            echo -e "7) 70"
            echo -e "8) 80"
            echo -e "9) 90"
            echo -e "10) 100"
            echo ""
            echo -e "0) Regresar al inicio"
            echo -e "${red}============================================================${plain}"
            read -p "Opcion: " prio_opc
            
            val=""
            case $prio_opc in
                1) val=10 ;;
                2) val=20 ;;
                3) val=30 ;;
                4) val=40 ;;
                5) val=50 ;;
                6) val=60 ;;
                7) val=70 ;;
                8) val=80 ;;
                9) val=90 ;;
                10) val=100 ;;
            esac
            
            if [ -n "$val" ]; then
                sysctl vm.swappiness=$val >/dev/null 2>&1
                if grep -q "^vm.swappiness" /etc/sysctl.conf; then
                    sed -i "s/^vm.swappiness.*/vm.swappiness=$val/" /etc/sysctl.conf
                else
                    echo "vm.swappiness=$val" >> /etc/sysctl.conf
                fi
                echo ""
                echo -e "swappines asignado en $val"
                echo -e "los cambios se aplicaran"
                echo -e "despues del reinicio (y ahora mismo)"
                echo ""
                read -p "Enter para continuar"
            fi
            ;;
        0)
            break
            ;;
    esac
done
