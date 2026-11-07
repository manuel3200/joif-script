#!/bin/bash
# =========================================================
# JOIF CLOUD - CLI Menu (Estilo JOIF Avanzado)
# =========================================================

# Importación de utilidades
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/core/utils.sh" ]; then
    source "$SCRIPT_DIR/core/utils.sh"
elif [ -f "/root/joif-core/core/utils.sh" ]; then
    source /root/joif-core/core/utils.sh
fi
    # Fallback temporal si no encuentra la ruta
    red='\033[1;31m'
    green='\033[1;32m'
    yellow='\033[1;33m'
    blue='\033[1;34m'
    cyan='\033[1;36m'
    white='\033[1;37m'
    plain='\033[0m'
fi
bg_red='\033[41;1;37m'
bg_blue='\033[44;1;37m'

API_URL="http://127.0.0.1:3000/api/users"
LOCAL_API_KEY=$(grep -m1 '^API_KEY=' /root/joif-core/.env 2>/dev/null | cut -d'=' -f2- | tr -d '\r\n')
[[ -z "$LOCAL_API_KEY" ]] && LOCAL_API_KEY="joif2026"


menu_crear_usuario() {
    clear
    echo -e "${cyan}      =====>>►► ${green}🐲 JOIF 💥 Cloud 🐲${cyan} ◄◄<<=====${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "        ${yellow}⚜️   CREADOR DE CUENTAS TIPO  ⚜️${plain} "
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${green}[01]${plain}  > SSH|DROPBEAR (DEMO) "
    echo -e " ${green}[02]${plain}  > SSH|DROPBEAR "
    echo -e " ${green}[03]${plain}  > HWID         "
    echo -e " ${green}[04]${plain}  > TOKEN "
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${green}[05]${plain}  > MODIFICAR CONTRASEÑA TOKEN "
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${red}[00]${plain}  ⇦ [ VOLVER ]"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    read -p "$(echo -e ${white}" ► Opcion : "${plain})" opt_crear
    
    if [ "$opt_crear" = "0" ] || [ "$opt_crear" = "00" ]; then
        return
    fi

    # CREADOR DE CUENTAS HWID ESTILO CHUMOGH / HTTP CUSTOM (EPRO)
    if [ "$opt_crear" = "3" ] || [ "$opt_crear" = "03" ]; then
        clear
        echo -e "${cyan}      =====>>►► ${green}🐲 JOIF 💥 Cloud 🐲${cyan} ◄◄<<=====${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        read -p "$(echo -e ${white}" Ingrese Nombre del Cliente (Identificación): "${plain})" client_name
        client_name=$(echo "$client_name" | tr -d '[:space:]')
        if [ -z "$client_name" ]; then
            echo -e "${red}Error: Debes ingresar el nombre del cliente para identificarlo.${plain}"
            sleep 2
            return
        fi

        clear
        echo -e "${cyan}      =====>>►► ${green}🐲 JOIF 💥 Cloud 🐲${cyan} ◄◄<<=====${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e ""
        echo -e " ${yellow}INGRESA HWID PARA ${white}$client_name${plain}"
        read -p "$(echo -e ${yellow}" HWID: "${green})" hwid
        echo -e "${plain}"
        hwid=$(echo "$hwid" | tr -d '[:space:]')
        if [ -z "$hwid" ]; then
            echo -e "${red}Error: Debes ingresar el HWID del dispositivo.${plain}"
            sleep 2
            return
        fi

        clear
        echo -e "${cyan}      =====>>►► ${green}🐲 JOIF 💥 Cloud 🐲${cyan} ◄◄<<=====${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e ""
        echo -e " ${yellow}TIEMPO DE DURACION EN DIAS PARA ${white}$client_name${plain}"
        read -p "$(echo -e ${yellow}" VALIDEZ : "${green})" days
        echo -e "${plain}"
        [[ -z "$days" ]] && days=30

        # Para HTTP Custom: El ID de hardware actúa automáticamente como usuario y contraseña
        # El nombre del cliente es únicamente la etiqueta humana de identificación
        exp_date=$(date -d "+$days days" --iso-8601=seconds)
        exp_display=$(date -d "+$days days" +"%d/%m/%Y")

        echo -e "${blue}Registrando cuenta HWID en el sistema...${plain}"
        res=$(curl -s -w "\n%{http_code}" -X POST "$API_URL" -H "Content-Type: application/json" -H "x-api-key: $LOCAL_API_KEY" \
            -d "{\"hwid\": \"$hwid\", \"alias\": \"$client_name\", \"expiration_date\": \"$exp_date\", \"max_connections\": 1}")
        http_code=$(echo "$res" | tail -n1)
        body=$(echo "$res" | sed '$d')

        if [ "$http_code" != "201" ]; then
            echo -e "${red}❌ Error al registrar en el servidor (HTTP $http_code): $body${plain}"
            echo -e "${yellow}Presione Enter para continuar...${plain}"
            read -r
            return
        fi

        DOMAIN=$(cat /root/.JOIF_domain 2>/dev/null || echo "$IP")
        clear
        echo -e "${cyan}      =====>>►► ${green}🐲 JOIF 💥 Cloud 🐲${cyan} ◄◄<<=====${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e " ${yellow}* Puertas Activas en su Servidor *${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        draw_active_ports
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e " DOMAIN          : ${white}$DOMAIN${plain}"
        echo -e " Host/IP-Address : ${white}$IP${plain}"
        echo -e " USUARIO         : ${white}$client_name${plain}"
        echo -e " HWID            : ${green}$hwid${plain}"
        echo -e " VALIDEZ         : ${white}$exp_display${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e "   ${white}En APPS como HTTP Inyector, CUSTOM, etc${plain}"
        echo -e "   ${red}No existe Dropbear${plain}"
        echo -e "   ${red}No existe SSL${plain}"
        echo -e " 🙍 ${yellow}Proxy(WS) : ${white}$DOMAIN:80${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e " ${green}¡Enter, para volver!${plain}"
        read -r
        return
    fi

    clear
    echo -e "${cyan}      =====>>►► ${green}🐲 JOIF 💥 Cloud 🐲${cyan} ◄◄<<=====${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "        ${yellow}⚜️   CREADOR DE CUENTAS TIPO  ⚜️${plain} "
    echo -e " ${red}⚠️ ATENCION ANTES DE CONTINUAR ⚠️${plain}"
    echo -e ""
    echo -e "  ${white}OPCIONAL DEFINE UN LIMITE DE RECONEXIONES${plain}"
    echo -e " ${white}ESPECIALES PARA APPS O METODOS INESTABLES!!${plain}"
    echo -e " ${white}SINO ENTIENDES LA FUNCION, PRESIONA ENTER!!${plain}"
    echo -e ""
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    read -p "$(echo -e ${white}" ⎚ DEFINE TU  LIMITE : "${plain})" max_conn
    
    if [ -z "$max_conn" ]; then
        max_conn=1
    fi

    echo -e "\n${yellow}[+] Datos del Usuario${plain}"
    read -p "Nombre de Usuario: " user
    read -p "Contraseña: " pass
    read -p "Días de duración (ej. 30) [30]: " days
    [[ -z "$days" ]] && days=30
    hwid=""

    exp_date=$(date -d "+$days days" --iso-8601=seconds)
    exp_display=$(date -d "+$days days" +"%d/%m/%Y")
    
    echo -e "${blue}Enviando datos al Panel Web...${plain}"
    res=$(curl -s -w "\n%{http_code}" -X POST "$API_URL" -H "Content-Type: application/json" -H "x-api-key: $LOCAL_API_KEY" \
        -d "{\"username\": \"$user\", \"password\": \"$pass\", \"expiration_date\": \"$exp_date\", \"max_connections\": $max_conn, \"hwid\": \"$hwid\"}")
    http_code=$(echo "$res" | tail -n1)
    body=$(echo "$res" | sed '$d')

    if [ "$http_code" != "201" ]; then
        echo -e "${red}❌ Error al registrar en el servidor (HTTP $http_code): $body${plain}"
        echo -e "${yellow}Presione Enter para continuar...${plain}"
        read -r
        return
    fi
    
    DOMAIN=$(cat /root/.JOIF_domain 2>/dev/null || echo "$IP")
    clear
    echo -e "${cyan}      =====>>►► ${green}🐲 JOIF 💥 Cloud 🐲${cyan} ◄◄<<=====${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${yellow}* Puertas Activas en su Servidor *${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    draw_active_ports
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " DOMAIN  : ${white}$DOMAIN${plain}"
    echo -e " Host/IP-Address : ${white}$IP${plain}"
    echo -e " USUARIO : ${white}$user${plain}"
    if [ -n "$hwid" ]; then
        echo -e " HWID    : ${white}$hwid${plain}"
    fi
    echo -e " VALIDEZ : ${white}$exp_display${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "   En APPS como HTTP Inyector, CUSTOM, etc"
    echo -e "   No existe Dropbear"
    echo -e "   No existe SSL"
    echo -e " 🙍 Proxy(WS) : ${white}$DOMAIN:80${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ¡Enter, para volver!"
    read -r
}

menu_banner() {
    clear
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "         ${yellow}- BANNER CUSTOM EDITABLE -${plain}  "
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${white}[INFO] Mantén los siguientes marcadores en tu banner HTML."
    echo -e "Las variables con 🔒 requieren JOIF APP V3 o Motor Custom.${plain}"
    echo -e ""
    echo -e " ${green}✅ VARIABLES DISPONIBLES AHORA:${plain}"
    echo -e "   • {fecha_actual} → Muestra la fecha del servidor"
    echo -e "   • {hora_actual}  → Muestra la hora del servidor"
    echo -e "   • {sistema}      → Muestra el nombre del servidor (JOIF)"
    echo -e ""
    echo -e " ${red}🔒 VARIABLES BLOQUEADAS (PRÓXIMAMENTE):${plain}"
    echo -e "   • {usuario}          → Nombre de la cuenta"
    echo -e "   • {dias_restantes}   → Días de vigencia"
    echo -e "   • {gbusage}          → GB consumidos"
    echo -e "   • {limitdgb}         → GB límite asignado"
    echo -e "   • {active-connections} → Conexiones activas"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${white}Edita el archivo en nano, no borres los placeholders."
    echo -e "Para salir: Ctrl+O, Enter, luego Ctrl+X${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " Presiona Enter para abrir el editor..."
    read -r

    if [ -f /etc/issue.net ]; then
        cp /etc/issue.net /etc/issue.net.bak
    else
        touch /etc/issue.net
    fi

    nano /etc/issue.net

    clear
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${yellow}Aplicando y compilando banner en SSH/Dropbear...${plain}"
    
    sed -i 's/{fecha_actual}/\\d/g' /etc/issue.net
    sed -i 's/{hora_actual}/\\t/g' /etc/issue.net
    sed -i 's/{sistema}/\\s/g' /etc/issue.net

    sed -i '/Banner/d' /etc/ssh/sshd_config
    echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
    systemctl restart sshd ssh 2>/dev/null

    if grep -q "DROPBEAR_EXTRA_ARGS" /etc/default/dropbear 2>/dev/null; then
        sed -i 's/DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS="-b \/etc\/issue.net"/g' /etc/default/dropbear
    else
        echo 'DROPBEAR_EXTRA_ARGS="-b /etc/issue.net"' >> /etc/default/dropbear
    fi
    systemctl restart dropbear 2>/dev/null

    echo -e "${green}✅ BANNER ESTÁTICO APLICADO EXITOSAMENTE${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ¡Enter, para volver!"
    read -r
}

menu_mostrar_conectados() {
    clear
    echo -e "${cyan}      =====>>►► ${green}🐲 JOIF 💥 Cloud 🐲${cyan} ◄◄<<=====${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${yellow}🔐 ADMINISTRADOR DE USUARIOS SSH|SSL|DROPBEAR 🔐${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${blue}USUARIO        CONEXIONES     TIEMPO HH:MM:SS${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

    unset conn_count
    unset max_time
    declare -A conn_count
    declare -A max_time
    
    while read -r linuxUser etimes; do
        conn_count["$linuxUser"]=$((conn_count["$linuxUser"] + 1))
        if [[ -z "${max_time[$linuxUser]}" ]] || (( etimes > max_time[$linuxUser] )); then
            max_time["$linuxUser"]=$etimes
        fi
    done < <(ps -eo etimes,command 2>/dev/null | awk '/sshd:|dropbear/ && !/root/ && !/grep/ && !/\[priv\]/ && !/listener/ {
        user = $3
        sub(/@.*/, "", user)
        if (user != "") {
            print user, $1
        }
    }')

    sec2time() {
        local T=$1
        local H=$((T/3600))
        local M=$(((T/60)%60))
        local S=$((T%60))
        printf "%02d:%02d:%02d" $H $M $S
    }

    idx=1
    total_online=0
    for l_user in "${!conn_count[@]}"; do
        c_count=${conn_count[$l_user]}
        c_time=${max_time[$l_user]}
        t_str=$(sec2time $c_time)
        
        db_res=$(sqlite3 -separator '|' /root/joif-core/database.sqlite "SELECT username, hwid, max_connections FROM users WHERE username='$l_user' OR hwid='$l_user' LIMIT 1;" 2>/dev/null)
        
        if [ -n "$db_res" ]; then
            db_uname=$(echo "$db_res" | cut -d'|' -f1)
            db_hwid=$(echo "$db_res" | cut -d'|' -f2)
            db_limit=$(echo "$db_res" | cut -d'|' -f3)
            
            uname_disp="[$idx]-$db_uname"
            if [ -n "$db_hwid" ]; then
                uname_disp="$uname_disp [HWID]"
            fi
            
            c_str="[$c_count/$db_limit]"
            if [ "$c_count" -gt "$db_limit" ]; then
                c_disp="${red}${c_str}${plain}"
            else
                c_disp="${green}${c_str}${plain}"
            fi
            
            printf " ${white}%-22s${plain}" "$uname_disp"
            
            pad=$(( 15 - ${#c_str} ))
            echo -ne "$c_disp"
            for ((i=0; i<pad; i++)); do echo -ne " "; done
            
            echo -e "$t_str"
            total_online=$((total_online + 1))
            idx=$((idx + 1))
        fi
    done
    
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "  🔰 # TIENES  [ ${green}${total_online}${plain} ] USUARIOS CONECTADOS 🔰 #"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ¡Enter, para volver!"
    read -r
}

menu_usuarios() {
    while true; do
        clear
        echo -e "${cyan}      =====>>►► ${green}🐲 JOIF 💥 Cloud 🐲${cyan} ◄◄<<=====${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e " ${yellow}🔐 ADMINISTRADOR DE USUARIOS SSH|SSL|DROPBEAR 🔐${plain}"
        echo -e "   ▸ M LIBRE: ${white}${RAM_FREE}M${plain}   ▸ USO DE CPU:  ${white}${CPU_USAGE}%${plain} "
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e " ${green}[01]${plain} ➮ AGREGAR USUARIO(HWID/NORMAL/TOKEN) 📝"
        echo -e " ${green}[02]${plain} ➮ BORRAR 1/TODOS LOS USUARIO/s       🗑 "
        echo -e " ${green}[03]${plain} ➮ EDITAR/RENOVAR USUARIOS               ♻ "
        echo -e " ${green}[04]${plain} ➮ MOSTRAR USUARIOS REGISTRADOS       🛡 "
        echo -e " ${green}[05]${plain} ➮ MOSTRAR USUARIOS CONECTADOS           👁️🗨 "
        echo -e " ${green}[06]${plain} ➮ 🔒 ADD/REMOVE BANNER ( SSH/DROPBEAR ) 🇪🇨 "
        echo -e " ${green}[07]${plain} ➮ 🔒 LOG DE CONSUMO ( Artificial )      🥨 "
        echo -e " ${green}[08]${plain} ➮ BLOQUEAR USUARIOS ( ALL UNLOCK )      ⛔ "
        echo -e " ${green}[09]${plain} ➮ BACKUP USUARIOS (#OFFICIAL) 💾"
        echo -e " ${green}[10]${plain} ➮ 🔒 MENU CUENTAS SSR/SS (#OFFICIAL)"
        echo -e " ${green}[11]${plain} ➮ 🔒 BOT CLIENTES TELEGRAM [ OFF ](#BETA)"
        echo -e " ${green}[12]${plain} ➮ 🔒 VERIFICADOR CLIENTES ( INDV ) "
        checkuser_status="${red}[OFF]${plain}"
        if systemctl is-active --quiet joif-api >/dev/null 2>&1; then
            checkuser_status="${green}[ON]${plain}"
        fi
        
        echo -e " ${green}[13]${plain} ➮ 🚀 ACTIVAR / REINSTALAR API CheckUser ( ${checkuser_status} )"
        echo -e " ${green}[14]${plain} ➮ 🔒 CONTROL DE ADMINISTRACION MULTILOGINS ( $ ) "
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e "  ${red}[0]${plain} ➮ [ REGRESAR ]"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        
        multilogin_status="${red}[OFF]${plain}"
        if systemctl is-active --quiet joif-limitador.service >/dev/null 2>&1; then
            multilogin_status="${green}[ON]${plain}"
        fi
        
        echo -e "${white}(CONTADOR : [OFF]) ( ACTIVAR KILL MULTISESIONES  ${multilogin_status}${white})${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        read -p "$(echo -e ${white}" ► Opcion : "${plain})" opt_usr

        case $opt_usr in
            1|01)
                menu_crear_usuario
                ;;
            2|02)
                while true; do
                    clear
                    echo -e "${cyan}      =====>>►► ${green}🐲 JOIF 💥 Cloud 🐲${cyan} ◄◄<<=====${plain}"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e " ${yellow}🔐 ADMINISTRADOR DE USUARIOS SSH|SSL|DROPBEAR 🔐${plain}"
                    echo -e "   ▸ M LIBRE: ${white}${RAM_FREE}M${plain}   ▸ USO DE CPU:  ${white}${CPU_USAGE}%${plain} "
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e " ${green}[01]${plain} ➮ AGREGAR USUARIO(HWID/NORMAL/TOKEN) 📝"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e " ELIMINAR USUARIOS"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e " ${green}[1]${plain} > 1 USER"
                    echo -e " ${green}[2]${plain} > TODOS (ITERATIVO 1x1) [RECOMENDADO]  "
                    echo -e " ${green}[3]${plain} > SOLO CADUCADOS"
                    echo -e " ${green}[4]${plain} > TODOS (SIN PREGUNTAR) [NO RECOMENDADO] "
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e "  ${red}[0]${plain} > [ REGRESAR ]"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    read -p "$(echo -e ${white}" ► Opcion : "${plain})" opt_del

                    case $opt_del in
                        1)
                            clear
                            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                            echo -e " USUARIOS REGISTRADOS "
                            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                            echo -e " - LISTA DE USUARIOS DISPONIBLES -"
                            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                            
                            idx=1
                            sqlite3 -separator '|' /root/joif-core/database.sqlite "SELECT username, hwid, COALESCE(alias, username) FROM users;" | while read -r line; do
                                uname=$(echo "$line" | cut -d'|' -f1)
                                uhwid=$(echo "$line" | cut -d'|' -f2)
                                ualias=$(echo "$line" | cut -d'|' -f3)
                                
                                if [ -n "$uhwid" ]; then
                                    str="${ualias} ->"
                                    printf " ${white}[%s] ➮ %-30s ${green}[HWID]${plain}\n" "$idx" "$str"
                                    echo -e "    ${green}⤷  ${white}${uhwid}${plain}  "
                                else
                                    echo -e " ${white}[${idx}] ➮ ${uname}${plain}"
                                fi
                                idx=$((idx + 1))
                            done
                            
                            read -p "$(echo -e ${white}"  ESCRIBE (nombre o número) DEL USUARIO: "${plain})" del_target
                            
                            # Check if it's a number
                            if [[ "$del_target" =~ ^[0-9]+$ ]]; then
                                offset=$((del_target - 1))
                                real_user=$(sqlite3 /root/joif-core/database.sqlite "SELECT username FROM users LIMIT 1 OFFSET $offset;")
                                if [ -z "$real_user" ]; then
                                    echo -e "${red}Usuario no encontrado en la lista.${plain}"
                                    sleep 2
                                    continue
                                fi
                                del_target="$real_user"
                            fi
                            
                            if [ -n "$del_target" ]; then
                                curl -s -X DELETE "$API_URL/$del_target" -H "x-api-key: $LOCAL_API_KEY" > /dev/null
                                echo -e "${red}✅ Usuario [$del_target] purgado del sistema y la BD.${plain}"
                                pause
                            fi
                            ;;
                        2)
                            echo -e "\n${yellow}Eliminando usuarios (Iterativo 1x1)...${plain}"
                            usuarios=$(sqlite3 /root/joif-core/database.sqlite "SELECT username FROM users;")
                            if [ -z "$usuarios" ]; then
                                echo -e "${red}No hay usuarios registrados.${plain}"
                            else
                                for u in $usuarios; do
                                    read -p "$(echo -e "¿Desea borrar al usuario ${white}$u${plain}? [s/N]: ")" resp
                                    if [[ "$resp" == "s" || "$resp" == "S" || "$resp" == "y" || "$resp" == "Y" ]]; then
                                        echo -e "Borrando ${white}$u${plain}..."
                                        curl -s -X DELETE "$API_URL/$u" -H "x-api-key: $LOCAL_API_KEY" > /dev/null
                                        sleep 0.5
                                    else
                                        echo -e "Omitiendo ${white}$u${plain}..."
                                    fi
                                done
                            fi
                            echo -e "${green}Proceso iterativo finalizado.${plain}"
                            pause
                            ;;
                        3)
                            echo -e "\n${yellow}Eliminando usuarios caducados...${plain}"
                            now_sec=$(date +%s)
                            sqlite3 -separator '|' /root/joif-core/database.sqlite "SELECT username, expiration_date FROM users;" | while read -r line; do
                                uname=$(echo "$line" | cut -d'|' -f1)
                                uexp=$(echo "$line" | cut -d'|' -f2)
                                exp_sec=$(date -d "$uexp" +%s 2>/dev/null)
                                if [ -n "$exp_sec" ]; then
                                    diff_sec=$((exp_sec - now_sec))
                                    if [ "$diff_sec" -le 0 ]; then
                                        echo -e "Borrando ${white}$uname${plain} (Caducado: $uexp)..."
                                        curl -s -X DELETE "$API_URL/$uname" -H "x-api-key: $LOCAL_API_KEY" > /dev/null
                                    fi
                                fi
                            done
                            echo -e "${green}Proceso finalizado.${plain}"
                            pause
                            ;;
                        4)
                            echo -e "\n${red}⚠️ ELIMINANDO TODOS LOS USUARIOS SIN PREGUNTAR ⚠️${plain}"
                            usuarios=$(sqlite3 /root/joif-core/database.sqlite "SELECT username FROM users;")
                            for u in $usuarios; do
                                curl -s -X DELETE "$API_URL/$u" -H "x-api-key: $LOCAL_API_KEY" > /dev/null
                            done
                            echo -e "${green}Base de datos y sistema purgados.${plain}"
                            pause
                            ;;
                        0)
                            break
                            ;;
                        *)
                            echo -e "${red}Opción inválida${plain}"
                            sleep 1
                            ;;
                    esac
                done
                ;;
            3|03)
                while true; do
                    clear
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e " MODIFICAR DATOS DE USUARIOS "
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e " - LISTA DE USUARIOS DISPONIBLES -"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    
                    idx=1
                    sqlite3 -separator '|' /root/joif-core/database.sqlite "SELECT username, hwid FROM users;" | while read -r line; do
                        uname=$(echo "$line" | cut -d'|' -f1)
                        uhwid=$(echo "$line" | cut -d'|' -f2)
                        
                        if [ -n "$uhwid" ]; then
                            str="${uname} ->"
                            printf " ${white}[%s] ➮ %-30s ${green}[HWID]${plain}\n" "$idx" "$str"
                            echo -e "    ${green}⤷  ${white}${uhwid}${plain}  "
                        else
                            echo -e " ${white}[${idx}] ➮ ${uname}${plain}"
                        fi
                        idx=$((idx + 1))
                    done
                    
                    read -p "$(echo -e ${white}"  ESCRIBE (nombre o número) DEL USUARIO (o 0 para salir): "${plain})" mod_target
                    
                    if [ "$mod_target" = "0" ]; then break; fi
                    if [ -z "$mod_target" ]; then continue; fi
                    
                    if [[ "$mod_target" =~ ^[0-9]+$ ]]; then
                        offset=$((mod_target - 1))
                        real_user=$(sqlite3 -separator '|' /root/joif-core/database.sqlite "SELECT username, hwid, max_connections, expiration_date FROM users LIMIT 1 OFFSET $offset;")
                        if [ -z "$real_user" ]; then
                            echo -e "${red}Usuario no encontrado.${plain}"; sleep 2; continue
                        fi
                    else
                        real_user=$(sqlite3 -separator '|' /root/joif-core/database.sqlite "SELECT username, hwid, max_connections, expiration_date FROM users WHERE username = '$mod_target';")
                        if [ -z "$real_user" ]; then
                            echo -e "${red}Usuario no encontrado.${plain}"; sleep 2; continue
                        fi
                    fi
                    
                    uname=$(echo "$real_user" | cut -d'|' -f1)
                    uhwid=$(echo "$real_user" | cut -d'|' -f2)
                    ulimit=$(echo "$real_user" | cut -d'|' -f3)
                    uexp=$(echo "$real_user" | cut -d'|' -f4)
                    
                    while true; do
                        clear
                        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                        echo -e " Seleccionaste el usuario: $uname"
                        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                        echo -e " $uname"
                        echo -e " ESCOJE LA OPCION A CAMBIAR DE $uname"
                        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                        echo -e " ${green}[1]${plain} > LIMITADOR DEL CLIENTE $uname"
                        echo -e " ${green}[2]${plain} > RENOVAR CLIENTE $uname"
                        if [ -n "$uhwid" ]; then
                            echo -e " ${green}[3]${plain} > CAMBIAR HWID DE $uname"
                        else
                            echo -e " ${green}[3]${plain} > CLAVE DEL CLIENTE $uname"
                        fi
                        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                        echo -e "  ${red}[0]${plain} > [ VOLVER ]"
                        read -p "$(echo -e ${white}" SELECCIONA UNA OPC : "${plain})" opc_mod
                        
                        case $opc_mod in
                            1)
                                echo -e " NUEVO LIMITE DE CONEXIONES : "
                                read -p "" n_lim
                                if [[ "$n_lim" =~ ^[0-9]+$ ]]; then
                                    sqlite3 /root/joif-core/database.sqlite "UPDATE users SET max_connections = $n_lim WHERE username = '$uname';"
                                    ulimit=$n_lim
                                    clear
                                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                                    echo -e " $uname"
                                    echo -e " ✭ Perfecto, HEMOS CAMBIADO SU LIMITE DE CONEXIONES!! ✭ "
                                    echo -e " RENOVADO EL  : $(date '+%d/%m/%Y') "
                                    echo -e " Host / IP    : ${DOMAIN:-'JOIF'} "
                                    echo -e " SU CLIENTE   : $uname "
                                    echo -e " NUEVO LIMITE : $n_lim "
                                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                                    echo -e " ¡Enter, para volver!"
                                    read -r
                                fi
                                ;;
                            2)
                                while true; do
                                    clear
                                    echo -e " ESCOJE LA OPCION A CAMBIAR DE $uname"
                                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                                    echo -e " ${green}[1]${plain} > AÑADIR DIAS A $uname"
                                    echo -e " ${green}[2]${plain} > QUITAR DIAS A $uname"
                                    echo -e " ${green}[3]${plain} > REINICIAR DIAS A $uname"
                                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                                    echo -e "  ${red}[0]${plain} > [ VOLVER ]"
                                    read -p "$(echo -e ${white}" OPCION : "${plain})" opc_dias
                                    
                                    if [ "$opc_dias" = "0" ]; then break; fi
                                    
                                    echo -e " NUMEROS DE DIAS : "
                                    read -p "" n_dias
                                    if [[ ! "$n_dias" =~ ^[0-9]+$ ]]; then continue; fi
                                    
                                    if [ "$opc_dias" = "1" ]; then
                                        new_date=$(date -d "$uexp + $n_dias days" +%Y-%m-%d)
                                    elif [ "$opc_dias" = "2" ]; then
                                        new_date=$(date -d "$uexp - $n_dias days" +%Y-%m-%d)
                                    elif [ "$opc_dias" = "3" ]; then
                                        new_date=$(date -d "+ $n_dias days" +%Y-%m-%d)
                                    fi
                                    
                                    if [ -n "$new_date" ]; then
                                        sqlite3 /root/joif-core/database.sqlite "UPDATE users SET expiration_date = '$new_date' WHERE username = '$uname';"
                                        
                                        linuxUser="${uhwid:-$uname}"
                                        sudo chage -E "$new_date" "$linuxUser" 2>/dev/null
                                        uexp="$new_date"
                                        
                                        new_date_fmt=$(date -d "$new_date" '+%d/%m/%Y')
                                        diff_sec=$(( $(date -d "$new_date" +%s) - $(date +%s) ))
                                        days_left=$(( diff_sec / 86400 ))
                                        
                                        clear
                                        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                                        echo -e "       ACTUALIZACION EXITOSA ! ! !"
                                        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                                        echo -e " ✭ PERFECTO, ACTUALIZAMOS TU MEMBRESIA!! ✭ "
                                        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                                        echo -e " RENOVADO EL  : $(date '+%d/%m/%Y') "
                                        echo -e " Host / IP    : ${DOMAIN:-'JOIF'} "
                                        echo -e " ID/CLIENTE   : $uname "
                                        echo -e " 📱 PERMITIDOS: $ulimit "
                                        echo -e " VALIDO HASTA : $new_date_fmt"
                                        echo -e " RENUEVA EN $days_left DIAS, DISFRUTE SU ESTANCIA!. "
                                        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                                        echo -e " ¡Enter, para volver!"
                                        read -r
                                    fi
                                done
                                ;;
                            3)
                                if [ -n "$uhwid" ]; then
                                    echo -e " NUEVO HWID (Serial del nuevo dispositivo) : "
                                    read -p "" n_hwid
                                    if [ -n "$n_hwid" ]; then
                                        # 1. Renombrar el usuario en Linux
                                        sudo usermod -l "$n_hwid" "$uhwid" 2>/dev/null
                                        
                                        # 2. Generar nueva contraseña MD5 y aplicarla
                                        new_pass=$(echo -n "${n_hwid}JOIF_CLOUD_SECURE_KEY_99" | md5sum | cut -c 1-8)
                                        echo "$n_hwid:$new_pass" | sudo chpasswd 2>/dev/null
                                        
                                        # 3. Actualizar la base de datos
                                        sqlite3 /root/joif-core/database.sqlite "UPDATE users SET hwid = '$n_hwid' WHERE username = '$uname';"
                                        
                                        uhwid=$n_hwid
                                        
                                        clear
                                        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                                        echo -e " $uname"
                                        echo -e " ✭ Perfecto, HEMOS ACTUALIZADO EL HWID!! ✭ "
                                        echo -e " RENOVADO EL  : $(date '+%d/%m/%Y') "
                                        echo -e " Host / IP    : ${DOMAIN:-'JOIF'} "
                                        echo -e " SU CLIENTE   : $uname "
                                        echo -e " NUEVO HWID   : $n_hwid "
                                        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                                        echo -e " ¡Enter, para volver!"
                                        read -r
                                    fi
                                else
                                    echo -e " NUEVA CLAVE : "
                                    read -p "" n_pass
                                    if [ -n "$n_pass" ]; then
                                        sqlite3 /root/joif-core/database.sqlite "UPDATE users SET password = '$n_pass' WHERE username = '$uname';"
                                        echo "$uname:$n_pass" | sudo chpasswd 2>/dev/null
                                        
                                        clear
                                        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                                        echo -e " $uname"
                                        echo -e " ✭ Perfecto, HEMOS CAMBIADO SU CONTRASEÑA!! ✭ "
                                        echo -e " RENOVADO EL  : $(date '+%d/%m/%Y') "
                                        echo -e " Host / IP    : ${DOMAIN:-'JOIF'} "
                                        echo -e " SU CLIENTE   : $uname "
                                        echo -e " NUEVA CLAVE  : $n_pass "
                                        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                                        echo -e " ¡Enter, para volver!"
                                        read -r
                                    fi
                                fi
                                ;;
                            0) break ;;
                        esac
                    done
                done
                ;;
            4|04)
                clear
                echo -e "${cyan}      =====>>►► ${green}🐲 JOIF 💥 Cloud 🐲${cyan} ◄◄<<=====${plain}"
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                echo -e " ${yellow}🔐 ADMINISTRADOR DE USUARIOS SSH|SSL|DROPBEAR 🔐${plain}"
                echo -e "   ▸ M LIBRE: ${white}${RAM_FREE}M${plain}   ▸ USO DE CPU:  ${white}${CPU_USAGE}%${plain} "
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                echo -e "  >  ${blue}USUARIO     CONTRASEÑA     LIMITE     CADUCA        DIAS${plain}"
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

                sqlite3 -separator '|' /root/joif-core/database.sqlite "SELECT id, username, password, max_connections, expiration_date, hwid FROM users;" | while read -r line; do
                    uid=$(echo "$line" | cut -d'|' -f1)
                    uname=$(echo "$line" | cut -d'|' -f2)
                    upass=$(echo "$line" | cut -d'|' -f3)
                    ulimit=$(echo "$line" | cut -d'|' -f4)
                    uexp=$(echo "$line" | cut -d'|' -f5)
                    uhwid=$(echo "$line" | cut -d'|' -f6)
                    
                    # Calcular dias
                    exp_sec=$(date -d "$uexp" +%s 2>/dev/null)
                    now_sec=$(date +%s)
                    if [ -z "$exp_sec" ]; then
                        days_display="${red}EXP${plain}"
                    else
                        diff_sec=$((exp_sec - now_sec))
                        if [ "$diff_sec" -le 0 ]; then
                            days_display="${red}EXP${plain}"
                        else
                            days_left=$((diff_sec / 86400))
                            days_display="${green}${days_left}${plain}"
                        fi
                    fi
                    
                    printf " ${white}[%s]>${plain} %-11s " "$uid" "$uname"
                    if [ -n "$uhwid" ]; then
                        printf "${magenta}%-14s${plain} " "ID${uid}"
                    else
                        printf "${white}%-14s${plain} " "$upass"
                    fi
                    printf "%-10s %-13s %b\n" "$ulimit" "$uexp" "$days_display"
                    
                    if [ -n "$uhwid" ]; then
                        echo -e "      ${green}⤷ HWID - ${white}${uhwid}${plain}"
                    fi
                done
                
                total=$(sqlite3 /root/joif-core/database.sqlite "SELECT COUNT(*) FROM users;")
                
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                echo -e "  🔰 # TIENES  [ ${green}${total}${plain} ] CLIENTES EN TU SERVIDOR 🔰 #"
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                echo -e " ¡Enter, para volver!"
                read -r
                ;;
            5|05)
                menu_mostrar_conectados
                ;;
            6|06)
                menu_banner
                ;;
            8|08)
                while true; do
                    clear
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e "         ${yellow}⛔ GESTOR DE BLOQUEOS (BANS) ⛔${plain}"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e " ${red}[1]${plain} ➮ BLOQUEAR USUARIO (Lock)"
                    echo -e " ${green}[2]${plain} ➮ DESBLOQUEAR USUARIO (Unlock)"
                    echo -e " ${yellow}[3]${plain} ➮ VER LISTA DE BLOQUEADOS"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e "  ${white}[0]${plain} ➮ [ REGRESAR ]"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    read -p "$(echo -e ${white}" ► Opcion : "${plain})" opt_ban
                    
                    case $opt_ban in
                        1)
                            clear
                            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                            echo -e "         ${yellow}⛔ BLOQUEAR USUARIO ⛔${plain}"
                            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                            echo -e " - LISTA DE USUARIOS ACTIVOS -"
                            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                            
                            idx=1
                            rm -f /tmp/active_users.txt
                            sqlite3 -separator '|' /root/joif-core/database.sqlite "SELECT username, hwid FROM users;" | while read -r line; do
                                uname=$(echo "$line" | cut -d'|' -f1)
                                uhwid=$(echo "$line" | cut -d'|' -f2)
                                linux_user=$uname
                                if [ -n "$uhwid" ]; then linux_user=$uhwid; fi
                                
                                status=$(passwd -S "$linux_user" 2>/dev/null | awk '{print $2}')
                                if [ "$status" != "L" ]; then
                                    if [ -n "$uhwid" ]; then
                                        printf " ${white}[%s] ➮ %-15s ${green}[ACTIVO] ${magenta}[HWID]${plain}\n" "$idx" "$uname"
                                    else
                                        printf " ${white}[%s] ➮ %-15s ${green}[ACTIVO]${plain}\n" "$idx" "$uname"
                                    fi
                                    echo "$idx|$uname|$uhwid" >> /tmp/active_users.txt
                                    idx=$((idx + 1))
                                fi
                            done
                            
                            if [ "$idx" -eq 1 ]; then
                                echo -e " ${white}No hay usuarios activos para bloquear.${plain}"
                                sleep 2
                                continue
                            fi
                            
                            read -p "$(echo -e ${white}"  ESCRIBE (nombre o número) DEL USUARIO A BLOQUEAR (o 0 para salir): "${plain})" mod_target
                            if [ "$mod_target" = "0" ] || [ -z "$mod_target" ]; then continue; fi
                            
                            if [[ "$mod_target" =~ ^[0-9]+$ ]]; then
                                db_res=$(grep "^$mod_target|" /tmp/active_users.txt | head -n 1 | cut -d'|' -f2,3)
                            else
                                db_res=$(sqlite3 -separator '|' /root/joif-core/database.sqlite "SELECT username, hwid FROM users WHERE username='$mod_target' OR hwid='$mod_target' LIMIT 1;")
                            fi
                            
                            if [ -n "$db_res" ]; then
                                uname=$(echo "$db_res" | cut -d'|' -f1)
                                uhwid=$(echo "$db_res" | cut -d'|' -f2)
                                linux_user=$uname
                                if [ -n "$uhwid" ]; then linux_user=$uhwid; fi
                                
                                usermod -L "$linux_user" 2>/dev/null
                                pkill -u "$linux_user" sshd 2>/dev/null
                                echo -e " ${green}✅ Usuario ${uname} ha sido BLOQUEADO y sus conexiones fueron cerradas.${plain}"
                            else
                                echo -e " ${red}❌ El usuario no existe o entrada inválida.${plain}"
                            fi
                            sleep 2
                            ;;
                        2)
                            clear
                            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                            echo -e "         ${green}✅ DESBLOQUEAR USUARIO ✅${plain}"
                            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                            echo -e " - LISTA DE USUARIOS BLOQUEADOS -"
                            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                            
                            idx=1
                            rm -f /tmp/banned_users.txt
                            sqlite3 -separator '|' /root/joif-core/database.sqlite "SELECT username, hwid FROM users;" | while read -r line; do
                                uname=$(echo "$line" | cut -d'|' -f1)
                                uhwid=$(echo "$line" | cut -d'|' -f2)
                                linux_user=$uname
                                if [ -n "$uhwid" ]; then linux_user=$uhwid; fi
                                
                                status=$(passwd -S "$linux_user" 2>/dev/null | awk '{print $2}')
                                if [ "$status" == "L" ]; then
                                    if [ -n "$uhwid" ]; then
                                        printf " ${white}[%s] ➮ %-15s ${red}[BLOQUEADO] ${magenta}[HWID]${plain}\n" "$idx" "$uname"
                                    else
                                        printf " ${white}[%s] ➮ %-15s ${red}[BLOQUEADO]${plain}\n" "$idx" "$uname"
                                    fi
                                    echo "$idx|$uname|$uhwid" >> /tmp/banned_users.txt
                                    idx=$((idx + 1))
                                fi
                            done
                            
                            if [ "$idx" -eq 1 ]; then
                                echo -e " ${white}No hay usuarios bloqueados actualmente.${plain}"
                                sleep 2
                                continue
                            fi
                            
                            read -p "$(echo -e ${white}"  ESCRIBE (nombre o número) DEL USUARIO A DESBLOQUEAR (o 0 para salir): "${plain})" mod_target
                            if [ "$mod_target" = "0" ] || [ -z "$mod_target" ]; then continue; fi
                            
                            if [[ "$mod_target" =~ ^[0-9]+$ ]]; then
                                db_res=$(grep "^$mod_target|" /tmp/banned_users.txt | head -n 1 | cut -d'|' -f2,3)
                            else
                                db_res=$(sqlite3 -separator '|' /root/joif-core/database.sqlite "SELECT username, hwid FROM users WHERE username='$mod_target' OR hwid='$mod_target' LIMIT 1;")
                            fi
                            
                            if [ -n "$db_res" ]; then
                                uname=$(echo "$db_res" | cut -d'|' -f1)
                                uhwid=$(echo "$db_res" | cut -d'|' -f2)
                                linux_user=$uname
                                if [ -n "$uhwid" ]; then linux_user=$uhwid; fi
                                
                                usermod -U "$linux_user" 2>/dev/null
                                echo -e " ${green}✅ Usuario ${uname} ha sido DESBLOQUEADO con éxito.${plain}"
                            else
                                echo -e " ${red}❌ El usuario no existe o entrada inválida.${plain}"
                            fi
                            sleep 2
                            ;;
                        3)
                            clear
                            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                            echo -e "           ${yellow}📋 USUARIOS BLOQUEADOS 📋${plain}"
                            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                            count=0
                            sqlite3 -separator '|' /root/joif-core/database.sqlite "SELECT username, hwid FROM users;" | while read -r line; do
                                uname=$(echo "$line" | cut -d'|' -f1)
                                uhwid=$(echo "$line" | cut -d'|' -f2)
                                
                                linux_user=$uname
                                if [ -n "$uhwid" ]; then
                                    linux_user=$uhwid
                                fi
                                
                                status=$(passwd -S "$linux_user" 2>/dev/null | awk '{print $2}')
                                if [ "$status" == "L" ]; then
                                    echo -e " ⛔ ${red}$uname${plain} ${white}(HWID: ${uhwid:-N/A})${plain}"
                                    count=$((count + 1))
                                fi
                            done
                            if [ "$count" -eq 0 ]; then
                                echo -e " ${white}No hay usuarios bloqueados actualmente.${plain}"
                            fi
                            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                            echo -e " ¡Enter, para volver!"
                            read -r
                            ;;
                        0) break ;;
                        *) echo -e "${red}Opción inválida${plain}"; sleep 1 ;;
                    esac
                done
                ;;
            9|09)
                bash /root/joif-core/modules/tools/backup_manager.sh
                ;;
            14)
                while true; do
                    clear
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e "      ${yellow}🛡 CONTROL DE MULTILOGIN (KILLER) 🛡${plain}"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e " ${green}[1]${plain} ➮ INICIAR AUTO-KILLER (Segundo Plano)"
                    echo -e " ${red}[2]${plain} ➮ DETENER AUTO-KILLER"
                    echo -e " ${yellow}[3]${plain} ➮ VER REGISTRO DE ELIMINACIONES (Log)"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e "  ${white}[0]${plain} ➮ [ REGRESAR ]"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    read -p "$(echo -e ${white}" ► Opcion : "${plain})" opt_kill
                    
                    case $opt_kill in
                        1)
                            echo -e " \n${yellow}Creando servicio en segundo plano...${plain}"
                            cat <<EOF > /etc/systemd/system/joif-limitador.service
[Unit]
Description=JOIF CLOUD Multilogin Killer
After=network.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash /root/joif-core/limitador.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
                            systemctl daemon-reload
                            systemctl enable joif-limitador >/dev/null 2>&1
                            systemctl start joif-limitador
                            echo -e " ${green}✅ Auto-Killer INICIADO (Revisando cada 10s)${plain}"
                            sleep 2
                            ;;
                        2)
                            echo -e " \n${yellow}Deteniendo servicio...${plain}"
                            systemctl stop joif-limitador >/dev/null 2>&1
                            systemctl disable joif-limitador >/dev/null 2>&1
                            echo -e " ${red}❌ Auto-Killer DETENIDO${plain}"
                            sleep 2
                            ;;
                        3)
                            clear
                            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                            echo -e "      ${yellow}📜 REGISTRO DE ELIMINACIONES 📜${plain}"
                            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                            if [ -f /var/log/joif-limitador.log ]; then
                                tail -n 20 /var/log/joif-limitador.log
                            else
                                echo -e " ${white}No hay registros todavía.${plain}"
                            fi
                            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                            echo -e " ¡Enter, para volver!"
                            read -r
                            ;;
                        0) break ;;
                        *) echo -e "${red}Opción inválida${plain}"; sleep 1 ;;
                    esac
                done
                ;;
            13|013)
                instalar_api_checkuser
                ;;
            0|00) break ;;
            *) echo -e "${red}Opción en construcción o inválida${plain}"; sleep 1 ;;
        esac
    done
}

menu_herramientas() {
    while true; do
        draw_header
        echo -e "${yellow}             [ HERRAMIENTAS DEL SISTEMA ]${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e " ${green}[1]${plain} > 📡 Monitor de Puertos Activos"
        echo -e " ${green}[2]${plain} > 🚀 Test de Velocidad (Speedtest)"
        echo -e " ${green}[3]${plain} > 🧹 Limpieza y Optimización del Sistema"
        echo -e " ${green}[4]${plain} > 💾 Memoria Virtual SWAP (Crear / Optimizar)"
        echo -e " ${green}[5]${plain} > 📦 Backup y Restauración de Cuentas"
        echo -e " ${green}[6]${plain} > ⚡ Autoconfigurar VPS para Portal Web (Auto-Link)"
        echo -e " ${red}[0]${plain} > 🔙 Volver al menú principal"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        read -p "$(echo -e ${white}"Selecciona una opción: "${plain})" opt_tools

        case $opt_tools in
            1)
                echo -e "\n${yellow}📡 PUERTOS ESCUCHANDO EN EL SERVIDOR${plain}"
                echo -e "PROTO  PUERTO    PROCESO"
                echo -e "--------------------------------------------------"
                ss -tulpn | grep LISTEN | awk '{print $1" "$5" "$7}' | while read proto local_addr process; do
                    port=$(echo $local_addr | rev | cut -d: -f1 | rev)
                    proc_name=$(echo $process | awk -F'"' '{print $2}')
                    if [ -z "$proc_name" ]; then proc_name=$(echo $process | cut -d/ -f1 | cut -d= -f2); fi
                    if [ "$proc_name" = "node" ]; then proc_name="CheckUserAPI(node)"; fi
                    printf "%-6s %-9s %s\n" "$proto" "$port" "${proc_name:-Desconocido}"
                done | sort -k2 -n | uniq
                pause
                ;;
            2)
                echo -e "\n${yellow}🚀 Iniciando Test de Velocidad...${plain}"
                if ! command -v speedtest-cli &> /dev/null; then
                    echo -e "${blue}Instalando módulo speedtest-cli...${plain}"
                    apt-get install -y speedtest-cli > /dev/null 2>&1
                fi
                speedtest-cli --simple 2>/dev/null || curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 - --simple
                pause
                ;;
            3)
                bash /root/joif-core/modules/system/cleaner.sh
                ;;
            4)
                bash /root/joif-core/modules/system/swap_manager.sh
                ;;
            5)
                bash /root/joif-core/modules/tools/backup_manager.sh
                ;;
            6)
                autoconfigurar_portal_web
                ;;
            0|00)
                break
                ;;
            *)
                echo -e "${red}Opción inválida.${plain}"
                sleep 1
                ;;
        esac
    done
}

autoconfigurar_portal_web() {
    clear
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "     ${yellow}⚡ AUTOCONFIGURACIÓN PARA PORTAL WEB JOIF ⚡${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${white}Esta herramienta prepara y optimiza este VPS para recibir${plain}"
    echo -e " ${white}cuentas automáticas desde tu Portal Web Central.${plain}"
    echo -e ""
    echo -e " ${cyan}Pasos automáticos:${plain}"
    echo -e "  ${green}1.${plain} Habilitar PasswordAuthentication y /bin/false en SSH"
    echo -e "  ${green}2.${plain} Desbloquear Firewall (Puertos 22, 80, 443, 3000, 7300)"
    echo -e "  ${green}3.${plain} Configurar API_KEY=joif2026 y reiniciar servicio joif"
    echo -e "  ${green}4.${plain} Testear API local en http://127.0.0.1:3000"
    echo -e "  ${green}5.${plain} (Opcional) Vincular y registrar el VPS en el Portal Central"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e ""
    read -p "$(echo -e ${yellow}"¿Deseas iniciar la autoconfiguración ahora? [S/n]: "${plain})" iniciar_auto
    if [[ "$iniciar_auto" =~ ^[Nn]$ ]]; then
        return
    fi

    echo -e "\n${blue}[1/5] Detectando red y dominio...${plain}"
    IP_DETECTADA=$(curl -s --connect-timeout 4 https://ifconfig.me 2>/dev/null || curl -s --connect-timeout 4 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$IP_DETECTADA" ]; then IP_DETECTADA="127.0.0.1"; fi

    DOMINIO_DEFAULT=""
    if [ -f "/root/.JOIF_domain" ]; then
        DOMINIO_DEFAULT=$(cat /root/.JOIF_domain 2>/dev/null | tr -d '\r\n ')
    fi
    if [ -z "$DOMINIO_DEFAULT" ]; then
        DOMINIO_DEFAULT="$IP_DETECTADA"
    fi

    echo -e "  • IP Pública detectada : ${green}$IP_DETECTADA${plain}"
    echo -e "  • Dominio actual       : ${yellow}$DOMINIO_DEFAULT${plain}"
    read -p "$(echo -e ${white}"  Presiona ENTER para usar este dominio o escribe uno nuevo: "${plain})" DOMINIO_INPUT
    DOMINIO_FINAL="${DOMINIO_INPUT:-$DOMINIO_DEFAULT}"
    echo "$DOMINIO_FINAL" > /root/.JOIF_domain

    echo -e "\n${blue}[2/5] Optimizando OpenSSH y shells del sistema (Ubuntu / Oracle Cloud)...${plain}"
    grep -qxF '/bin/false' /etc/shells || echo '/bin/false' >> /etc/shells

    mkdir -p /etc/ssh/sshd_config.d
    cat << 'EOF' > /etc/ssh/sshd_config.d/01-password-auth.conf
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PermitEmptyPasswords no
EOF
    sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/ClientAliveInterval/d' /etc/ssh/sshd_config 2>/dev/null
    echo "ClientAliveInterval 30" >> /etc/ssh/sshd_config
    sed -i '/ClientAliveCountMax/d' /etc/ssh/sshd_config 2>/dev/null
    echo "ClientAliveCountMax 2" >> /etc/ssh/sshd_config

    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
    echo -e "  ${green}✔ OpenSSH configurado con soporte de contraseñas.${plain}"

    echo -e "\n${blue}[3/5] Abriendo puertos en el Firewall del VPS (Oracle / iptables / ufw)...${plain}"
    for p in 22 80 443 3000 7300; do
        iptables -I INPUT 1 -p tcp --dport "$p" -j ACCEPT 2>/dev/null
        if command -v ufw &>/dev/null; then ufw allow "$p"/tcp &>/dev/null; fi
    done
    iptables -I INPUT 1 -p udp --dport 7300 -j ACCEPT 2>/dev/null
    if command -v ufw &>/dev/null; then ufw allow 7300/udp &>/dev/null; fi

    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save &>/dev/null
    elif command -v iptables-save &>/dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    echo -e "  ${green}✔ Puertos 22 (SSH), 80 (WS Proxy), 443 (SSL), 3000 (API) y 7300 (UDPGW) abiertos.${plain}"

    echo -e "\n${blue}[4/5] Configurando API_KEY en joif-core y reiniciando servicios...${plain}"
    mkdir -p /root/joif-core
    ENV_FILE="/root/joif-core/.env"
    
    if [ -f "$ENV_FILE" ]; then
        if grep -q '^API_KEY=' "$ENV_FILE"; then
            sed -i 's/^API_KEY=.*/API_KEY=joif2026/' "$ENV_FILE"
        else
            echo "API_KEY=joif2026" >> "$ENV_FILE"
        fi
        if grep -q '^NODE_API_SECRET=' "$ENV_FILE"; then
            sed -i 's/^NODE_API_SECRET=.*/NODE_API_SECRET=joif2026/' "$ENV_FILE"
        else
            echo "NODE_API_SECRET=joif2026" >> "$ENV_FILE"
        fi
    else
        cat << 'EOF' > "$ENV_FILE"
PORT=3000
API_KEY=joif2026
NODE_API_SECRET=joif2026
EOF
    fi

    systemctl restart joif 2>/dev/null || systemctl restart joif-api 2>/dev/null || true
    sleep 2

    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://127.0.0.1:3000/check 2>/dev/null || echo "000")
    if [ "$HTTP_STATUS" = "200" ]; then
        echo -e "  ${green}✔ API Edge Node respondiendo perfectamente (HTTP 200).${plain}"
    else
        echo -e "  ${yellow}[!] API local retornó código $HTTP_STATUS. Si recién instalaste, verifica 'systemctl status joif'.${plain}"
    fi

    echo -e "\n${blue}[5/5] Vinculación con el Portal Web Central...${plain}"
    echo -e "${white}¿Deseas registrar este VPS automáticamente en tu Portal Web Central?${plain}"
    read -p "$(echo -e ${yellow}"Registrar ahora en el Portal Central? [S/n]: "${plain})" reg_auto
    
    if [[ ! "$reg_auto" =~ ^[Nn]$ ]]; then
        echo ""
        read -p "$(echo -e ${white}"  URL del Portal Central [https://sv-free.joif.net]: "${plain})" PORTAL_URL_INPUT
        PORTAL_URL="${PORTAL_URL_INPUT:-https://sv-free.joif.net}"
        PORTAL_URL="${PORTAL_URL%/}"

        read -p "$(echo -e ${white}"  Key de la Web o Clave Admin [joif_live_... o ENTER para Admin12345!]: "${plain})" PORTAL_PASS_INPUT
        PORTAL_PASS="${PORTAL_PASS_INPUT:-Admin12345!}"

        DEFAULT_ID="vps-$(echo "$IP_DETECTADA" | tr '.' '-')"
        read -p "$(echo -e ${white}"  ID único del VPS [$DEFAULT_ID]: "${plain})" VPS_ID_INPUT
        VPS_ID="${VPS_ID_INPUT:-$DEFAULT_ID}"

        read -p "$(echo -e ${white}"  Nombre a mostrar [ej: USA - Servidor 01]: "${plain})" VPS_NAME_INPUT
        VPS_NAME="${VPS_NAME_INPUT:-Servidor JOIF}"

        read -p "$(echo -e ${white}"  Código de País (2 letras) [US]: "${plain})" VPS_CODE_INPUT
        VPS_CODE="${VPS_CODE_INPUT:-US}"

        read -p "$(echo -e ${white}"  Nombre del País [Estados Unidos]: "${plain})" VPS_COUNTRY_INPUT
        VPS_COUNTRY="${VPS_COUNTRY_INPUT:-Estados Unidos}"

        read -p "$(echo -e ${white}"  Bandera emoji [🇺🇸]: "${plain})" VPS_FLAG_INPUT
        VPS_FLAG="${VPS_FLAG_INPUT:-🇺🇸}"

        read -p "$(echo -e ${white}"  Límite diario de cuentas [100]: "${plain})" VPS_LIMIT_INPUT
        VPS_LIMIT="${VPS_LIMIT_INPUT:-100}"

        echo -e "\n  ${yellow}Enviando registro al Portal Central ($PORTAL_URL)...${plain}"

        REG_RESP=$(curl -s -X POST "${PORTAL_URL}/api/admin/servers" \
            -H "Content-Type: application/json" \
            -H "x-admin-password: ${PORTAL_PASS}" \
            -H "Authorization: Bearer ${PORTAL_PASS}" \
            -d "{
              \"id\": \"${VPS_ID}\",
              \"name\": \"${VPS_NAME}\",
              \"country_code\": \"${VPS_CODE}\",
              \"country_name\": \"${VPS_COUNTRY}\",
              \"flag\": \"${VPS_FLAG}\",
              \"domain\": \"${DOMINIO_FINAL}\",
              \"ip\": \"${IP_DETECTADA}\",
              \"ssh_port\": 22,
              \"proxy_port\": 80,
              \"ssl_port\": 443,
              \"udpgw_port\": 7300,
              \"api_url\": \"http://${IP_DETECTADA}:3000\",
              \"api_secret\": \"joif2026\",
              \"daily_limit\": ${VPS_LIMIT},
              \"is_active\": 1
            }" 2>/dev/null || echo '{"error":"Error de conexión"}')

        if echo "$REG_RESP" | grep -q '"success":true'; then
            echo -e "  ${green}🎉 ¡VPS REGISTRADO EXITOSAMENTE EN EL PORTAL CENTRAL!${plain}"
        else
            echo -e "  ${red}❌ No se pudo auto-registrar en el Portal.${plain}"
            echo -e "  ${yellow}Respuesta recibida: ${white}$REG_RESP${plain}"
            echo -e "  ${yellow}Puedes agregarlo manualmente desde el Panel de Administración.${plain}"
        fi
    fi

    echo -e "\n${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "     ${yellow}📋 RESUMEN DE CONFIGURACIÓN DEL SERVIDOR EDGE${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "  • Dominio / Host   : ${green}${DOMINIO_FINAL}${plain}"
    echo -e "  • IP Pública       : ${green}${IP_DETECTADA}${plain}"
    echo -e "  • Puerto SSH       : ${white}22${plain}"
    echo -e "  • Puerto Proxy WS  : ${white}80${plain}"
    echo -e "  • Puerto UDPGW     : ${white}7300${plain}"
    echo -e "  • URL de API Edge  : ${yellow}http://${IP_DETECTADA}:3000${plain}"
    echo -e "  • Clave API Secreta: ${yellow}joif2026${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${green}✔ Autoconfiguración completada con éxito.${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    pause
}


instalar_api_checkuser() {
    clear
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "           ${yellow}INSTALADOR DE API CHECKUSER${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${white}Esta API permite que aplicaciones como MiVPNApp"
    echo -e "muestren los días restantes y conexiones activas.${plain}\n"
    
    # Rango de puertos
    while true; do
        read -p "$(echo -e ${green}" ► Ingresa un puerto [3000-3500] (Default 3000): "${plain})" port_input
        if [ -z "$port_input" ]; then
            port_input=3000
            break
        elif [[ "$port_input" -ge 3000 && "$port_input" -le 3500 ]]; then
            break
        else
            echo -e "${red}El puerto debe estar entre 3000 y 3500.${plain}"
        fi
    done
    
    echo -e "\n${yellow}[+] Verificando Node.js...${plain}"
    if ! command -v node &> /dev/null; then
        echo -e "${blue}Instalando Node.js...${plain}"
        export DEBIAN_FRONTEND=noninteractive
        export NEEDRESTART_MODE=a
        apt-get update -qq && apt-get install -y -qq nodejs npm
    fi
    
    echo -e "${yellow}[+] Preparando entorno API...${plain}"
    cd /root/joif-core || echo "Advertencia: Directorio joif-core no existe. Creando." && mkdir -p /root/joif-core
    
    if [ ! -f /root/joif-core/package.json ]; then
        # Descargamos los archivos básicos desde un repo o usamos los que están si es la misma carpeta.
        # Ya que se asume que server.js está clonado junto con el menú.
        echo -e "${blue}Instalando dependencias locales de npm...${plain}"
        npm install express cors dotenv sqlite3 body-parser
    else
        npm install
    fi
    
    echo -e "${yellow}[+] Creando Servicio en Segundo Plano (Puerto $port_input)...${plain}"
    cat << EOF > /etc/systemd/system/joif-api.service
[Unit]
Description=JOIF API CheckUser Node.js
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/joif-core
Environment=PORT=$port_input
ExecStart=/usr/bin/node server.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable joif-api
    systemctl restart joif-api
    
    # Abrir puerto en el firewall
    if command -v ufw &> /dev/null; then
        ufw allow ${port_input}/tcp >/dev/null 2>&1
    fi
    if command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport ${port_input} -j ACCEPT >/dev/null 2>&1
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    
    echo -e "\n${green}✅ API CheckUser Instalada y Corriendo en el puerto $port_input!${plain}"
    
    # Obtener IP Pública para mostrar en pantalla
    PUBLIC_IP=$(curl -s ifconfig.me || echo "IP_DEL_VPS")
    
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${yellow}🌐 TUS ENLACES DE LA API CHECKUSER:${plain}"
    echo -e "${white}Ruta base (Para MiVPNApp / Otras Apps):${plain}"
    echo -e "${green}http://${PUBLIC_IP}:${port_input}/api/check/[usuario]${plain}"
    echo -e ""
    echo -e "${white}Panel de Administración Web:${plain}"
    echo -e "${green}http://${PUBLIC_IP}:${port_input}/${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${white}Asegúrate de tener este puerto abierto en tu VPS (UFW/Iptables).${plain}"
    echo -e "Presiona ENTER para volver."
    read -r
}

check_first_run() {
    if [ ! -f /root/.JOIF_welcome_done ]; then
        clear
        echo -e "${cyan}  ╔══════════════════════════════════════════════════╗${plain}"
        echo -e "${cyan}  ║                                                  ║${plain}"
        echo -e "${cyan}  ║           ${yellow}BIENVENIDO A JOIF SCRIPT${cyan}              ║${plain}"
        echo -e "${cyan}  ║                                                  ║${plain}"
        echo -e "${cyan}  ╠══════════════════════════════════════════════════╣${plain}"
        echo -e "${cyan}  ║                                                  ║${plain}"
        echo -e "${cyan}  ║  ${white}¡Gracias por instalar nuestro script!${cyan}           ║${plain}"
        echo -e "${cyan}  ║                                                  ║${plain}"
        echo -e "${cyan}  ║  ${white}Este software ha sido desarrollado con${cyan}          ║${plain}"
        echo -e "${cyan}  ║  ${white}dedicación para facilitar la administración${cyan}     ║${plain}"
        echo -e "${cyan}  ║  ${white}de servidores VPN e Inyectores HTTPS.${cyan}           ║${plain}"
        echo -e "${cyan}  ║                                                  ║${plain}"
        echo -e "${cyan}  ║  ${yellow}Características principales:${cyan}                    ║${plain}"
        echo -e "${cyan}  ║  ${green}• Gestión de usuarios (Enlace Web API)${cyan}          ║${plain}"
        echo -e "${cyan}  ║  ${green}• Monitorización del sistema${cyan}                    ║${plain}"
        echo -e "${cyan}  ║  ${green}• Instaladores UDP-GW y Python Websocket${cyan}        ║${plain}"
        echo -e "${cyan}  ║  ${green}• Y mucho más...${cyan}                                ║${plain}"
        echo -e "${cyan}  ║                                                  ║${plain}"
        echo -e "${cyan}  ║  ${white}Este mensaje solo aparecerá esta vez.${cyan}           ║${plain}"
        echo -e "${cyan}  ║  ${white}Como agradecimiento por elegirnos${cyan}               ║${plain}"
        echo -e "${cyan}  ║                                                  ║${plain}"
        echo -e "${cyan}  ║  ${yellow}[Presione ENTER para continuar o espere 10s...]${cyan} ║${plain}"
        echo -e "${cyan}  ║                                                  ║${plain}"
        echo -e "${cyan}  ╚══════════════════════════════════════════════════╝${plain}"
        read -t 10 -r
        touch /root/.JOIF_welcome_done
    fi
}

# Menú Principal
check_first_run
while true; do
    draw_header
    online_count=$(get_online_users 2>/dev/null || echo "0")
    autostart_badge="${red}[OFF]${plain}"
    grep -Fq "[ -f /usr/bin/menu ] && /usr/bin/menu" /root/.bashrc 2>/dev/null && autostart_badge="${green}[ON]${plain}"

    echo -e " ${green}[01]${plain} ➮ 👥 CONTROL USUARIOS (SSH/SSL/HWID) "
    echo -e " ${green}[02]${plain} ➮ 🛠️  HERRAMIENTAS DEL SISTEMA "
    echo -e " ${green}[03]${plain} ➮ 👁️  MONITOR DE USUARIOS EN LÍNEA  [ ${green}${online_count}${plain} ]"
    echo -e " ${green}[04]${plain} ➮ ⚡ AUTOINICIAR SCRIPT AL ENTRAR   ${autostart_badge}"
    echo -e " ${green}[05]${plain} ➮ 📡 INSTALADOR DE PROTOCOLOS (WS, BadVPN, SSL)"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${green}[06]${plain} ➮ 🔄 GESTIÓN / ACTUALIZAR SCRIPT  |  ${red}[0]${plain} ⇦ [ SALIR ]"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    read -p "$(echo -e ${white}" ► Opcion : "${plain})" opt_main

    case $opt_main in
        1|01) menu_usuarios ;;
        2|02) menu_herramientas ;;
        3|03) menu_mostrar_conectados ;;
        4|04) bash /root/joif-core/modules/system/autostart_manager.sh ;;
        5|05) bash /root/joif-core/modules/network/protocol_manager.sh ;;
        6|06)
            clear
            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
            echo -e "           ${yellow}GESTIÓN DEL SCRIPT JOIF${plain}"
            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
            echo -e " ${green}[1]${plain} ➮ ACTUALIZAR SCRIPT (Git Pull Rápido)"
            echo -e " ${green}[2]${plain} ➮ BACKUP Y RESTAURACIÓN DE CUENTAS"
            echo -e " ${red}[3]${plain} ➮ DESINSTALAR SCRIPT (Remover JOIF)"
            echo -e " ${white}[0]${plain} ➮ REGRESAR"
            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
            read -p "$(echo -e ${white}" ► Opcion : "${plain})" sub_opt
            case $sub_opt in
                1) 
                    if [ -f /usr/bin/joif-update ]; then
                        /usr/bin/joif-update
                        exit 0
                    elif [ -f /root/joif-core/update.sh ]; then
                        /root/joif-core/update.sh
                        exit 0
                    else
                        echo -e " ${red}Actualizador no encontrado.${plain}"
                        sleep 2
                    fi
                    ;;
                2)
                    bash /root/joif-core/modules/tools/backup_manager.sh
                    ;;
                3)
                    bash /root/joif-core/modules/system/uninstall.sh
                    ;;
            esac
            ;;
        0) clear; echo -e "${green}¡Gracias por usar JOIF CLOUD!${plain}"; exit 0 ;;
        *) echo -e "${red}Opción inválida${plain}"; sleep 1 ;;
    esac
done
