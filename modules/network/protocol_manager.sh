#!/bin/bash
# =========================================================
# JOIF Cloud - Gestor Modular de Protocolos
# =========================================================

source /root/joif-core/core/utils.sh 2>/dev/null

liberar_puerto_80() {
    echo -e " ${yellow}[*] Analizando y liberando puerto 80...${plain}"

    # 1. Detener joif-proxy si estaba corriendo para no interferir
    systemctl stop joif-proxy 2>/dev/null || true

    # 2. Detener y deshabilitar servicios conocidos que ocupan el puerto 80
    local known_svcs=("nginx" "apache2" "httpd" "lighttpd" "caddy" "haproxy" "openresty" "python-proxy" "epro" "eproxy" "wsproxy" "chumo-proxy" "socks")
    for svc in "${known_svcs[@]}"; do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
    done

    # 3. Detectar PIDs en puerto 80 e identificar servicios systemd que los auto-reinician
    local pids=""
    if command -v lsof &>/dev/null; then
        pids=$(lsof -t -i:80 2>/dev/null || true)
    elif command -v fuser &>/dev/null; then
        pids=$(fuser 80/tcp 2>/dev/null || true)
    fi

    for p in $pids; do
        if [ -n "$p" ]; then
            local unit=$(systemctl status "$p" 2>/dev/null | grep -oE '[a-zA-Z0-9_.-]+\.service' | head -n1)
            if [ -n "$unit" ] && [ "$unit" != "joif-proxy.service" ]; then
                echo -e " ${yellow}[*] Deteniendo servicio en conflicto: $unit${plain}"
                systemctl stop "$unit" 2>/dev/null || true
                systemctl disable "$unit" 2>/dev/null || true
            fi
            kill -9 "$p" 2>/dev/null || true
        fi
    done

    # 4. Matar procesos residuales de Chumo / ADM por nombre
    killall -9 nginx apache2 httpd lighttpd caddy haproxy openresty 2>/dev/null || true
    pkill -9 -f "nginx" 2>/dev/null || true
    pkill -9 -f "apache2" 2>/dev/null || true
    pkill -9 -f "PDirect" 2>/dev/null || true
    pkill -9 -f "P3Direct" 2>/dev/null || true
    pkill -9 -f "PPub" 2>/dev/null || true
    pkill -9 -f "PPriv" 2>/dev/null || true
    pkill -9 -f "wsproxy" 2>/dev/null || true
    pkill -9 -f "epro" 2>/dev/null || true
    pkill -9 -f "proxy.js" 2>/dev/null || true
    pkill -9 -f "node.*proxy" 2>/dev/null || true

    # 5. Limpiar sesiones screen y tareas de crontab
    pkill -9 -f "screen.*(wsproxy|proxy|socks|python|epro)" 2>/dev/null || true
    crontab -l 2>/dev/null | grep -E -v 'autoboot|PDirect|wsproxy|epro|chumovps' | crontab - 2>/dev/null || true
    sed -i '/autoboot/d' /etc/crontab 2>/dev/null || true
    rm -f /bin/autoboot /etc/autoboot 2>/dev/null || true

    # 6. Remover configuración por defecto de Nginx en puerto 80 si existe
    if [ -f /etc/nginx/sites-enabled/default ]; then
        rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    fi

    # 7. Forzar SIGKILL en socket 80
    if command -v fuser &>/dev/null; then
        fuser -k -9 80/tcp >/dev/null 2>&1 || true
    fi

    # 8. Esperar hasta 5 segundos a que el kernel y SO liberen el puerto
    local free=0
    for i in 1 2 3 4 5; do
        if ! ss -tlpn 2>/dev/null | grep -qE '(:80[[:space:]]|:80$)'; then
            free=1
            break
        fi
        fuser -k -9 80/tcp >/dev/null 2>&1 || true
        sleep 1
    done

    if [ "$free" -eq 1 ]; then
        echo -e " ${green}✔ Puerto 80 liberado y verificado correctamente.${plain}"
        return 0
    else
        echo -e " ${red}❌ Advertencia: No se pudo liberar el puerto 80 por completo. Procesos detectados:${plain}"
        ss -tlpn 'sport = :80' 2>/dev/null || lsof -i :80 2>/dev/null
        return 1
    fi
}

menu_usuarios_xray() {
    local config_file="/usr/local/etc/xray/config.json"
    if [ ! -f "$config_file" ]; then
        echo -e "\n ${red}❌ Error: No existe configuración de Xray en $config_file${plain}"
        echo -e " ${yellow}Por favor instala Xray VLESS primero (Opción [1]).${plain}"
        pause
        return
    fi

    while true; do
        clear
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e " 👥 ${yellow}ADMINISTRADOR DE USUARIOS XRAY VLESS (UUID)${plain}"
        echo -e "    ${green}Acceso por Dispositivo / Multi-Usuario Seguro${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

        python3 -c "
import json, sys
try:
    with open('$config_file', 'r') as f:
        data = json.load(f)
    clients = data.get('inbounds', [{}])[0].get('settings', {}).get('clients', [])
    if not clients:
        print('  \033[1;33mNo hay usuarios registrados actualmente.\033[0m')
    else:
        print('  \033[1;37mUSUARIOS REGISTRADOS:\033[0m')
        print('  \033[0;36m┌──────┬──────────────────────┬──────────────────────────────────────┐\033[0m')
        print('  \033[0;36m│  #   │ Alias / Usuario      │ UUID / Device ID                     │\033[0m')
        print('  \033[0;36m├──────┼──────────────────────┼──────────────────────────────────────┤\033[0m')
        for idx, c in enumerate(clients, 1):
            email = str(c.get('email', 'sin-nombre'))[:20]
            uid = str(c.get('id', 'N/A'))
            print(f'  \033[0;36m│\033[0m \033[1;37m{idx:<4}\033[0m \033[0;36m│\033[0m \033[0;32m{email:<20}\033[0m \033[0;36m│\033[0m \033[1;33m{uid:<36}\033[0m \033[0;36m│\033[0m')
        print('  \033[0;36m└──────┴──────────────────────┴──────────────────────────────────────┘\033[0m')
        print(f'  Total usuarios: \033[0;32m{len(clients)}\033[0m\n')
except Exception as e:
    print('  \033[0;31mError leyendo configuración: ' + str(e) + '\033[0m')
"

        echo -e " ${green}[1]${plain} > ➕ Crear / Registrar Nuevo Usuario (Asignar o Pegar UUID)"
        echo -e " ${green}[2]${plain} > 🗑  Eliminar Usuario Registrado"
        echo -e " ${green}[3]${plain} > 📋 Ver Enlace VLESS y Datos de un Usuario"
        echo -e " ${green}[4]${plain} > 🔄 Reiniciar Servicio Xray"
        echo -e " ${white}[0]${plain} > 🔙 Volver al menú anterior"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        read -p "$(echo -e ${white}"Selecciona una opción: "${plain})" opt_u

        case $opt_u in
            1)
                clear
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                echo -e " ➕ ${yellow}CREAR NUEVO USUARIO XRAY VLESS${plain}"
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                read -p "$(echo -e ${white}"Nombre o Alias del cliente (ej: celular-manuel): "${plain})" u_alias
                u_alias=$(echo "$u_alias" | tr -d '[:space:]')
                if [ -z "$u_alias" ]; then
                    u_alias="usuario-$(date +%s)"
                fi

                local gen_uuid=$(uuidgen 2>/dev/null || /usr/local/bin/xray uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null)
                echo -e "\n ${white}Identificador UUID:${plain}"
                echo -e " UUID sugerido: ${green}$gen_uuid${plain}"
                echo -e " ${yellow}(Consejo: En la app puedes tocar [ 📋 Copiar ID ] y pegarlo aquí)${plain}"
                read -p "$(echo -e ${white}"Pega el UUID del dispositivo (o Enter para usar el sugerido): "${plain})" input_uid
                local final_uid="${input_uid:-$gen_uuid}"
                final_uid=$(echo "$final_uid" | tr -d '[:space:]')

                python3 -c "
import json, sys
try:
    with open('$config_file', 'r') as f:
        data = json.load(f)
    clients = data['inbounds'][0]['settings'].setdefault('clients', [])
    for c in clients:
        if c.get('id') == '$final_uid':
            print('EXISTS_UUID')
            sys.exit(0)
    clients.append({
        'id': '$final_uid',
        'email': '$u_alias',
        'level': 0
    })
    with open('$config_file', 'w') as f:
        json.dump(data, f, indent=2)
    print('OK')
except Exception as e:
    print('ERROR:' + str(e))
" > /tmp/xray_add_res.txt
                local res=$(cat /tmp/xray_add_res.txt 2>/dev/null)
                rm -f /tmp/xray_add_res.txt

                if [ "$res" = "OK" ]; then
                    systemctl restart xray
                    local my_ip=$(curl -s -m 4 https://api.ipify.org || curl -s -m 4 ifconfig.me || echo "IP_DEL_VPS")
                    local cur_path=$(grep -oE '"path":\s*"[^"]+"' "$config_file" | head -n1 | cut -d'"' -f4)
                    [ -z "$cur_path" ] && cur_path="/"
                    local vless_link="vless://${final_uid}@${my_ip}:80?path=$(echo -n "$cur_path" | jq -sRr @uri 2>/dev/null || echo "%2F")&security=none&encryption=none&type=httpupgrade#${u_alias}"

                    echo -e "\n${green}✔ Usuario '${u_alias}' agregado y servicio Xray reiniciado exitosamente.${plain}\n"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e "  • Alias:        ${white}$u_alias${plain}"
                    echo -e "  • UUID:         ${yellow}$final_uid${plain}"
                    echo -e "  • Servidor IP:  ${white}$my_ip${plain}"
                    echo -e "  • Puerto:       ${green}80${plain}"
                    echo -e "  • Path:         ${white}$cur_path${plain}"
                    echo -e "  • Protocolo:    ${green}VLESS (HTTPUpgrade)${plain}"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e "  🔗 Link VLESS:  ${cyan}$vless_link${plain}"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                elif [ "$res" = "EXISTS_UUID" ]; then
                    echo -e "\n${yellow}⚠️ El UUID ingresado ya se encuentra registrado para otro cliente.${plain}"
                else
                    echo -e "\n${red}❌ Error agregando usuario: $res${plain}"
                fi
                pause
                ;;

            2)
                clear
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                echo -e " 🗑  ${yellow}ELIMINAR USUARIO XRAY VLESS${plain}"
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                read -p "$(echo -e ${white}"Ingresa el número (#) del usuario a eliminar (o 0 para cancelar): "${plain})" del_num
                if [ -z "$del_num" ] || [ "$del_num" = "0" ]; then
                    continue
                fi

                python3 -c "
import json, sys
try:
    with open('$config_file', 'r') as f:
        data = json.load(f)
    clients = data['inbounds'][0]['settings'].get('clients', [])
    idx = int('$del_num') - 1
    if idx < 0 or idx >= len(clients):
        print('INVALID_INDEX')
        sys.exit(0)
    removed = clients.pop(idx)
    with open('$config_file', 'w') as f:
        json.dump(data, f, indent=2)
    name = removed.get('email', removed.get('id', 'N/A'))
    print('OK:' + str(name))
except Exception as e:
    print('ERROR:' + str(e))
" > /tmp/xray_del_res.txt
                local d_res=$(cat /tmp/xray_del_res.txt 2>/dev/null)
                rm -f /tmp/xray_del_res.txt

                if [[ "$d_res" == OK:* ]]; then
                    local removed_name="${d_res#OK:}"
                    systemctl restart xray
                    echo -e "\n${green}✔ Usuario '${removed_name}' eliminado correctamente y servicio reiniciado.${plain}"
                elif [ "$d_res" = "INVALID_INDEX" ]; then
                    echo -e "\n${red}❌ Número de usuario inválido.${plain}"
                else
                    echo -e "\n${red}❌ Error eliminando usuario: $d_res${plain}"
                fi
                pause
                ;;

            3)
                clear
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                echo -e " 📋 ${yellow}VER DATOS Y ENLACE VLESS DE UN USUARIO${plain}"
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                read -p "$(echo -e ${white}"Ingresa el número (#) del usuario (o 0 para cancelar): "${plain})" view_num
                if [ -z "$view_num" ] || [ "$view_num" = "0" ]; then
                    continue
                fi

                python3 -c "
import json, sys
try:
    with open('$config_file', 'r') as f:
        data = json.load(f)
    clients = data['inbounds'][0]['settings'].get('clients', [])
    idx = int('$view_num') - 1
    if idx < 0 or idx >= len(clients):
        print('INVALID_INDEX')
        sys.exit(0)
    target = clients[idx]
    path = data['inbounds'][0].get('streamSettings', {}).get('httpupgradeSettings', {}).get('path', '/')
    print(f'DATA|{target.get(\"email\", \"usuario\")}|{target.get(\"id\", \"\")}|{path}')
except Exception as e:
    print('ERROR:' + str(e))
" > /tmp/xray_view_res.txt
                local v_res=$(cat /tmp/xray_view_res.txt 2>/dev/null)
                rm -f /tmp/xray_view_res.txt

                if [[ "$v_res" == DATA\|* ]]; then
                    IFS='|' read -r _ t_alias t_uuid t_path <<< "$v_res"
                    local my_ip=$(curl -s -m 4 https://api.ipify.org || curl -s -m 4 ifconfig.me || echo "IP_DEL_VPS")
                    local enc_path=$(echo -n "$t_path" | jq -sRr @uri 2>/dev/null || echo "%2F")
                    local link="vless://${t_uuid}@${my_ip}:80?path=${enc_path}&security=none&encryption=none&type=httpupgrade#${t_alias}"
                    echo -e "\n${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e "  • Alias:        ${green}$t_alias${plain}"
                    echo -e "  • UUID:         ${yellow}$t_uuid${plain}"
                    echo -e "  • Servidor IP:  ${white}$my_ip${plain}"
                    echo -e "  • Puerto:       ${green}80${plain}"
                    echo -e "  • Path:         ${white}$t_path${plain}"
                    echo -e "  • Protocolo:    ${green}VLESS (HTTPUpgrade)${plain}"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e "  🔗 Link VLESS:  ${cyan}$link${plain}"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                elif [ "$v_res" = "INVALID_INDEX" ]; then
                    echo -e "\n${red}❌ Número de usuario inválido.${plain}"
                else
                    echo -e "\n${red}❌ Error: $v_res${plain}"
                fi
                pause
                ;;

            4)
                echo -e "\n${yellow}[*] Reiniciando servicio Xray...${plain}"
                systemctl restart xray
                sleep 1
                if systemctl is-active --quiet xray; then
                    echo -e "${green}✔ Xray reiniciado correctamente.${plain}"
                else
                    echo -e "${red}❌ Error reiniciando Xray.${plain}"
                fi
                pause
                ;;

            0) break ;;
            *) echo -e "${red}Opción inválida${plain}"; sleep 1 ;;
        esac
    done
}

gestionar_xray_vless() {
    while true; do
        clear
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e " ⚡ ${yellow}GESTOR XRAY VLESS HTTPUPGRADE (PUERTO 80)${plain}"
        echo -e "   ${green}Máxima velocidad (Zero-Overhead) + Bypass DPI + Payload HTTP${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

        local xray_active=0
        if systemctl is-active --quiet xray; then
            xray_active=1
            local xray_pid=$(pgrep -f "xray.*run" 2>/dev/null | head -n1)
            echo -e " ${green}● Xray VLESS se encuentra ACTIVO (PID: ${xray_pid:-OK}) en puerto 80.${plain}\n"
        else
            echo -e " ${red}○ Xray VLESS se encuentra INACTIVO o no configurado.${plain}\n"
        fi

        echo -e " ${green}[1]${plain} > ⚡ Instalar / Reconfigurar Servidor Xray VLESS (Puerto 80)"
        if [ "$xray_active" -eq 1 ]; then
            echo -e " ${green}[2]${plain} > 👥 Administrar Usuarios VLESS (Crear, Listar, Eliminar)"
            echo -e " ${green}[3]${plain} > 📋 Ver Parámetros de Conexión y VLESS Link (Para la App)"
            echo -e " ${green}[4]${plain} > 🔄 Reiniciar Servicio Xray"
            echo -e " ${red}[5]${plain} > 🛑 Detener Xray y Liberar Puerto 80"
        fi
        echo -e " ${white}[0]${plain} > 🔙 Volver al menú anterior"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        read -p "$(echo -e ${white}"Selecciona una opción: "${plain})" xr_opt

        case $xr_opt in
            1)
                clear
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                echo -e " 🚀 ${yellow}INSTALACIÓN Y CONFIGURACIÓN XRAY VLESS${plain}"
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

                # 1. Verificar dependencias
                export DEBIAN_FRONTEND=noninteractive
                export NEEDRESTART_MODE=a
                if ! command -v curl &>/dev/null || ! command -v unzip &>/dev/null || ! command -v uuidgen &>/dev/null; then
                    echo -e " ${yellow}[*] Instalando dependencias del sistema...${plain}"
                    apt-get update -qq && apt-get install -y -qq curl unzip uuid-runtime jq > /dev/null 2>&1
                fi

                # 2. Descargar o instalar binario oficial de Xray
                if [ ! -x "/usr/local/bin/xray" ]; then
                    echo -e " ${yellow}[*] Descargando e instalando núcleo Xray oficial...${plain}"
                    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install > /dev/null 2>&1
                fi

                if [ ! -x "/usr/local/bin/xray" ]; then
                    # Fallback descarga directa
                    local arch=$(uname -m)
                    local pkg_arch="64"
                    case "$arch" in
                        x86_64|amd64) pkg_arch="64" ;;
                        aarch64|arm64) pkg_arch="arm64-v8a" ;;
                        armv7*|armhf) pkg_arch="arm32-v7a" ;;
                    esac
                    echo -e " ${yellow}[*] Descarga directa de GitHub Releases (Arch: $pkg_arch)...${plain}"
                    mkdir -p /tmp/xray_dl
                    wget -qO /tmp/xray_dl/xray.zip "https://github.com/XTLS/Xray-core/releases/download/v26.11.9/Xray-linux-${pkg_arch}.zip"
                    unzip -qo /tmp/xray_dl/xray.zip -d /tmp/xray_dl
                    mv /tmp/xray_dl/xray /usr/local/bin/xray
                    chmod +x /usr/local/bin/xray
                    mkdir -p /usr/local/share/xray
                    cp /tmp/xray_dl/*.dat /usr/local/share/xray/ 2>/dev/null || true
                    rm -rf /tmp/xray_dl
                fi

                if [ ! -x "/usr/local/bin/xray" ]; then
                    echo -e "${red}❌ Error: No se pudo instalar el binario de Xray.${plain}"
                    pause
                    continue
                fi

                echo -e " ${green}✔ Núcleo Xray verificado: $(/usr/local/bin/xray version | head -n1)${plain}"

                # 3. Liberar puerto 80 (detener joif-proxy si estaba corriendo)
                if systemctl is-active --quiet joif-proxy; then
                    echo -e " ${yellow}[!] El Proxy WebSocket (joif-proxy) está activo en puerto 80.${plain}"
                    echo -e " ${yellow}[*] Deteniendo joif-proxy para asignar puerto 80 a Xray VLESS...${plain}"
                    systemctl stop joif-proxy 2>/dev/null || true
                    systemctl disable joif-proxy 2>/dev/null || true
                fi
                liberar_puerto_80

                # 4. Parámetros de configuración
                local default_uuid=$(uuidgen 2>/dev/null || /usr/local/bin/xray uuid 2>/dev/null || echo "11111111-2222-3333-4444-555555555555")
                echo -e "\n ${white}Generando identificador UUID para el cliente...${plain}"
                echo -e " UUID asignado: ${green}$default_uuid${plain}"
                read -p "$(echo -e ${white}"Presiona Enter para usar este UUID o escribe uno personalizado: "${plain})" custom_uuid
                local final_uuid="${custom_uuid:-$default_uuid}"

                read -p "$(echo -e ${white}"Ruta HTTPUpgrade / Path [por defecto / ]: "${plain})" custom_path
                local final_path="${custom_path:-/}"

                # 5. Escribir configuración
                rm -rf /etc/systemd/system/xray.service.d 2>/dev/null || true
                mkdir -p /usr/local/etc/xray /var/log/xray
                chmod -R 777 /var/log/xray 2>/dev/null || true
                chown -R nobody:nogroup /var/log/xray 2>/dev/null || true
                cat << EOF > /usr/local/etc/xray/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 80,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$final_uuid",
            "email": "user@joif.vpn",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "httpupgrade",
        "security": "none",
        "httpupgradeSettings": {
          "path": "$final_path"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}
EOF

                # 6. Servicio Systemd
                cat << 'EOF' > /etc/systemd/system/xray.service
[Unit]
Description=Xray VLESS Service (Port 80 HTTPUpgrade)
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

                systemctl daemon-reload
                systemctl enable xray >/dev/null 2>&1
                systemctl restart xray

                # 7. Firewall
                if command -v iptables &>/dev/null; then
                    iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true
                fi
                if command -v ufw &>/dev/null; then
                    ufw allow 80/tcp >/dev/null 2>&1 || true
                fi

                sleep 2
                if systemctl is-active --quiet xray; then
                    local my_ip=$(curl -s -m 4 https://api.ipify.org || curl -s -m 4 ifconfig.me || echo "IP_DEL_VPS")
                    echo -e "\n${green}✅ ¡Xray VLESS HTTPUpgrade instalado y ACTIVO en el puerto 80!${plain}\n"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e " 📱 ${yellow}PARÁMETROS PARA LA APLICACIÓN ANDROID:${plain}"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    echo -e "  • Protocolo:     ${green}VLESS (HTTPUpgrade)${plain}"
                    echo -e "  • Host / IP:     ${white}$my_ip${plain}"
                    echo -e "  • Puerto:        ${green}80${plain}"
                    echo -e "  • UUID:          ${yellow}$final_uuid${plain}"
                    echo -e "  • Path / Ruta:   ${white}$final_path${plain}"
                    echo -e "  • Transporte:    ${green}httpupgrade${plain}"
                    echo -e "  • Seguridad:     ${white}none (texto plano para payload)${plain}"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    local vless_link="vless://${final_uuid}@${my_ip}:80?path=$(echo -n "$final_path" | jq -sRr @uri 2>/dev/null || echo "%2F")&security=none&encryption=none&type=httpupgrade#JOIF-VLESS-80"
                    echo -e "  🔗 Link VLESS:  ${cyan}$vless_link${plain}"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                else
                    echo -e "\n${red}❌ Error: No se pudo iniciar el servicio xray. Logs:${plain}"
                    journalctl -u xray -n 12 --no-pager 2>/dev/null
                fi
                pause
                ;;

            2)
                menu_usuarios_xray
                ;;

            3)
                clear
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                echo -e " 📋 ${yellow}DATOS DE CONEXIÓN XRAY VLESS (PUERTO 80)${plain}"
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                if [ -f "/usr/local/etc/xray/config.json" ]; then
                    local my_ip=$(curl -s -m 4 https://api.ipify.org || curl -s -m 4 ifconfig.me || echo "IP_DEL_VPS")
                    local cur_uuid=$(grep -oE '"id":\s*"[^"]+"' /usr/local/etc/xray/config.json | head -n1 | cut -d'"' -f4)
                    local cur_path=$(grep -oE '"path":\s*"[^"]+"' /usr/local/etc/xray/config.json | head -n1 | cut -d'"' -f4)
                    echo -e "  • Estado:        ${green}Activo en Puerto 80${plain}"
                    echo -e "  • Servidor IP:   ${white}$my_ip${plain}"
                    echo -e "  • Puerto:        ${green}80${plain}"
                    echo -e "  • UUID Activo:   ${yellow}$cur_uuid${plain}"
                    echo -e "  • Path:          ${white}${cur_path:-/}${plain}"
                    echo -e "  • Transporte:    ${green}httpupgrade (Fast Anti-DPI)${plain}"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                    local vless_link="vless://${cur_uuid}@${my_ip}:80?path=%2F&security=none&encryption=none&type=httpupgrade#JOIF-VLESS-80"
                    echo -e "  🔗 Link VLESS:  ${cyan}$vless_link${plain}"
                    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                else
                    echo -e "${yellow}No se encontró configuración activa de Xray en /usr/local/etc/xray/config.json${plain}"
                fi
                pause
                ;;

            4)
                echo -e "\n${yellow}[*] Reiniciando servicio Xray...${plain}"
                systemctl restart xray
                sleep 1
                if systemctl is-active --quiet xray; then
                    echo -e "${green}✔ Xray reiniciado correctamente.${plain}"
                else
                    echo -e "${red}❌ Error reiniciando Xray.${plain}"
                fi
                pause
                ;;

            5)
                echo -e "\n${yellow}[*] Deteniendo servicio Xray y liberando puerto 80...${plain}"
                systemctl stop xray 2>/dev/null || true
                systemctl disable xray 2>/dev/null || true
                if command -v fuser &>/dev/null; then
                    fuser -k -9 80/tcp >/dev/null 2>&1 || true
                fi
                echo -e "${green}✔ Servicio Xray detenido. Puerto 80 liberado.${plain}"
                pause
                ;;

            0) break ;;
            *) echo -e "${red}Opción inválida${plain}"; sleep 1 ;;
        esac
    done
}

while true; do
    clear
    draw_header
    echo -e "${yellow}             [ INSTALADOR MODULAR DE PROTOCOLOS ]${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${green}[1]${plain} > ⚡ Proxy WebSocket Optimizado (Puerto 80 -> 22)"
    echo -e " ${green}[2]${plain} > 🎮 BadVPN UDP-GW (Puertos 7300 y 7200 - Juegos y Llamadas)"
    echo -e " ${green}[3]${plain} > 🔒 SSL / TLS Stunnel (Puerto 443 -> WS 80 o SSH 22)"
    echo -e " ${green}[4]${plain} > 📊 Estado de Protocolos en Vivo"
    echo -e " ${green}[5]${plain} > ⚡ Xray VLESS HTTPUpgrade (Puerto 80 - Anti-DPI)"
    echo -e " ${green}[30]${plain}> 🛠  Herramientas Extras"
    echo -e " ${red}[0]${plain} > 🔙 Volver al menú principal"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    read -p "$(echo -e ${white}"Selecciona una opción: "${plain})" opt_prot

    case $opt_prot in
        1)
            clear
            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
            echo -e " 🚀 ${yellow}GESTOR DE PROXY WEBSOCKET (PUERTO 80 -> 22)${plain}"
            echo -e "   ${green}Zero-Latency (NoDelay) + KeepAlive 15s + EventLoop Libuv${plain}"
            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

            if systemctl is-active --quiet joif-proxy; then
                echo -e " ${green}● El Proxy WebSocket ya se encuentra ACTIVO en el puerto 80.${plain}\n"
                echo -e " ${green}[1]${plain} > 🔄 Reiniciar y Re-verificar Puerto 80"
                echo -e " ${red}[2]${plain} > 🛑 Detener Servicio y Liberar Puerto 80"
                echo -e " ${white}[0]${plain} > 🔙 Volver"
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                read -p "$(echo -e ${white}"Selecciona una opción: "${plain})" ws_action
                case $ws_action in
                    2)
                        echo -e "\n${yellow}[*] Deteniendo servicio joif-proxy...${plain}"
                        systemctl stop joif-proxy 2>/dev/null || true
                        systemctl disable joif-proxy 2>/dev/null || true
                        echo -e "${green}✅ Proxy WebSocket detenido y puerto 80 liberado.${plain}"
                        pause
                        continue
                        ;;
                    0) continue ;;
                    *) echo -e "\n${yellow}[*] Reiniciando servicio...${plain}" ;;
                esac
            fi

            if ! command -v node &> /dev/null; then
                export DEBIAN_FRONTEND=noninteractive
                export NEEDRESTART_MODE=a
                apt-get update -qq && apt-get install -y -qq nodejs npm > /dev/null 2>&1
            fi
            NODE_BIN=$(command -v node || echo "/usr/bin/node")

            if ! command -v fuser &>/dev/null || ! command -v lsof &>/dev/null; then
                export DEBIAN_FRONTEND=noninteractive
                apt-get install -y -qq psmisc lsof > /dev/null 2>&1
            fi

            liberar_puerto_80

            cat << EOF > /etc/systemd/system/joif-proxy.service
[Unit]
Description=JOIF High-Performance WebSocket SSH Proxy (Port 80)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/joif-core
ExecStart=$NODE_BIN /root/joif-core/proxy.js --port 80 --target 22
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

            systemctl daemon-reload
            systemctl enable joif-proxy >/dev/null 2>&1
            systemctl restart joif-proxy

            if command -v iptables &>/dev/null; then
                iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true
            fi
            if command -v ufw &>/dev/null; then
                ufw allow 80/tcp >/dev/null 2>&1 || true
            fi
            if command -v netfilter-persistent &>/dev/null; then
                netfilter-persistent save >/dev/null 2>&1 || true
            elif command -v iptables-save &>/dev/null; then
                mkdir -p /etc/iptables 2>/dev/null || true
                iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
            fi

            sleep 2
            if systemctl is-active --quiet joif-proxy; then
                echo -e "\n${green}✅ Proxy WebSocket Activo en puerto 80 -> Destino local 22.${plain}"
            else
                echo -e "\n${red}❌ No se pudo iniciar joif-proxy. Detalle de logs del sistema:${plain}"
                journalctl -u joif-proxy -n 12 --no-pager 2>/dev/null
                echo -e "\n${yellow}[*] Diagnóstico de procesos en puerto 80:${plain}"
                ss -tlpn 'sport = :80' 2>/dev/null || lsof -i :80 2>/dev/null
            fi
            pause
            ;;

        2)
            clear
            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
            echo -e "         ${yellow}🎮 GESTOR BADVPN UDP-GW 🎮${plain}"
            echo -e "   ${white}Puertos 7300 y 7200 para Juegos Online y VoIP${plain}"
            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

            if systemctl is-active --quiet badvpn-7300 || systemctl is-active --quiet badvpn-7200 || pgrep -x "badvpn-udpgw" >/dev/null; then
                echo -e " ${green}● BadVPN UDP-GW ya se encuentra ACTIVO en puertos 7300 y 7200.${plain}\n"
                echo -e " ${green}[1]${plain} > 🔄 Reiniciar BadVPN"
                echo -e " ${red}[2]${plain} > 🛑 Detener BadVPN y Liberar Puertos"
                echo -e " ${white}[0]${plain} > 🔙 Volver"
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                read -p "$(echo -e ${white}"Selecciona una opción: "${plain})" bad_action
                case $bad_action in
                    2)
                        echo -e "\n${yellow}[*] Deteniendo BadVPN...${plain}"
                        systemctl stop badvpn-7300 badvpn-7200 badvpn-dual 2>/dev/null || true
                        systemctl disable badvpn-7300 badvpn-7200 badvpn-dual 2>/dev/null || true
                        killall -9 badvpn-udpgw 2>/dev/null || true
                        pkill -9 -f "badvpn" 2>/dev/null || true
                        echo -e "${green}✅ BadVPN detenido y puertos liberados.${plain}"
                        pause
                        continue
                        ;;
                    0) continue ;;
                    *) echo -e "\n${yellow}[*] Reiniciando BadVPN...${plain}" ;;
                esac
            fi

            BADVPN_BIN=""
            if [ -x "/usr/local/bin/badvpn-udpgw" ]; then
                BADVPN_BIN="/usr/local/bin/badvpn-udpgw"
            elif [ -x "/usr/bin/badvpn-udpgw" ]; then
                BADVPN_BIN="/usr/bin/badvpn-udpgw"
            elif command -v badvpn-udpgw &>/dev/null; then
                BADVPN_BIN=$(command -v badvpn-udpgw)
            fi

            if [ -z "$BADVPN_BIN" ]; then
                echo -e " ${yellow}[*] Preparando dependencias de compilación...${plain}"
                export DEBIAN_FRONTEND=noninteractive
                export NEEDRESTART_MODE=a
                apt-get update -qq && apt-get install -y -qq cmake make gcc g++ build-essential unzip > /dev/null 2>&1

                echo -e " ${yellow}[*] Descargando y compilando BadVPN...${plain}"
                cd /tmp
                rm -rf badvpn* 2>/dev/null
                wget -qO badvpn.zip https://github.com/ambrop72/badvpn/archive/master.zip
                unzip -q badvpn.zip
                cd badvpn-master
                mkdir -p build && cd build
                cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 > /dev/null 2>&1
                make install > /dev/null 2>&1
                cd /root
                rm -rf /tmp/badvpn* 2>/dev/null
                BADVPN_BIN="/usr/local/bin/badvpn-udpgw"
            fi

            if [ ! -f "$BADVPN_BIN" ]; then
                echo -e "\n${red}❌ Error: No se pudo compilar o encontrar el binario badvpn-udpgw.${plain}"
                pause
                continue
            fi

            chmod +x "$BADVPN_BIN"
            ln -sf "$BADVPN_BIN" /usr/local/bin/badvpn-udpgw 2>/dev/null || true
            ln -sf "$BADVPN_BIN" /usr/bin/badvpn-udpgw 2>/dev/null || true
            echo -e " ${green}✔ Binario badvpn-udpgw listo (${BADVPN_BIN}).${plain}"

            # Limpiar servicio legacy con screen
            systemctl stop badvpn-dual badvpn-7300 badvpn-7200 2>/dev/null || true
            systemctl disable badvpn-dual 2>/dev/null || true
            rm -f /etc/systemd/system/badvpn-dual.service /bin/JOIF-badvpn 2>/dev/null || true
            killall -9 badvpn-udpgw 2>/dev/null || true
            pkill -9 -f "badvpn" 2>/dev/null || true

            # Crear servicios nativos limpios en systemd (sin dependencia de screen ni tty)
            cat << EOF > /etc/systemd/system/badvpn-7300.service
[Unit]
Description=BadVPN UDP Gateway (Port 7300)
After=network.target

[Service]
Type=simple
User=root
ExecStart=$BADVPN_BIN --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

            cat << EOF > /etc/systemd/system/badvpn-7200.service
[Unit]
Description=BadVPN UDP Gateway (Port 7200)
After=network.target

[Service]
Type=simple
User=root
ExecStart=$BADVPN_BIN --listen-addr 127.0.0.1:7200 --max-clients 1000 --max-connections-for-client 10
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

            systemctl daemon-reload
            systemctl enable badvpn-7300 badvpn-7200 >/dev/null 2>&1
            systemctl restart badvpn-7300 badvpn-7200

            if command -v iptables &>/dev/null; then
                iptables -I INPUT 1 -p udp --dport 7300 -j ACCEPT >/dev/null 2>&1 || true
                iptables -I INPUT 1 -p udp --dport 7200 -j ACCEPT >/dev/null 2>&1 || true
            fi
            if command -v ufw &>/dev/null; then
                ufw allow 7300/udp >/dev/null 2>&1 || true
                ufw allow 7200/udp >/dev/null 2>&1 || true
            fi
            if command -v netfilter-persistent &>/dev/null; then
                netfilter-persistent save >/dev/null 2>&1 || true
            elif command -v iptables-save &>/dev/null; then
                mkdir -p /etc/iptables 2>/dev/null || true
                iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
            fi

            sleep 1
            if systemctl is-active --quiet badvpn-7300 && systemctl is-active --quiet badvpn-7200; then
                echo -e "\n${green}✅ BadVPN Dual Channel Activo y Operativo en puertos 7300 y 7200 UDP.${plain}"
            else
                echo -e "\n${red}❌ No se pudo iniciar BadVPN. Detalle de logs del sistema:${plain}"
                journalctl -u badvpn-7300 -n 6 --no-pager 2>/dev/null
                journalctl -u badvpn-7200 -n 6 --no-pager 2>/dev/null
            fi
            pause
            ;;

        3)
            clear
            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
            echo -e "            ${yellow}🔒 GESTOR SSL / TLS STUNNEL4 🔒${plain}"
            echo -e "    ${white}Túnel SSL en puerto 443 hacia el WebSocket (80)${plain}"
            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

            if systemctl is-active --quiet stunnel4; then
                echo -e " ${green}● Stunnel SSL ya se encuentra ACTIVO en el puerto 443.${plain}\n"
                echo -e " ${green}[1]${plain} > 🔄 Reiniciar / Reconfigurar Stunnel"
                echo -e " ${red}[2]${plain} > 🛑 Detener Stunnel y Liberar Puerto 443"
                echo -e " ${white}[0]${plain} > 🔙 Volver"
                echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
                read -p "$(echo -e ${white}"Selecciona una opción: "${plain})" st_action
                case $st_action in
                    2)
                        echo -e "\n${yellow}[*] Deteniendo Stunnel4...${plain}"
                        systemctl stop stunnel4 2>/dev/null || true
                        systemctl disable stunnel4 2>/dev/null || true
                        echo -e "${green}✅ Stunnel detenido y puerto 443 liberado.${plain}"
                        pause
                        continue
                        ;;
                    0) continue ;;
                    *) echo -e "\n${yellow}[*] Reiniciando Stunnel...${plain}" ;;
                esac
            fi

            export DEBIAN_FRONTEND=noninteractive
            export NEEDRESTART_MODE=a
            apt-get update -qq && apt-get install -y -qq stunnel4 openssl > /dev/null 2>&1

            mkdir -p /etc/stunnel
            if [ ! -f /etc/stunnel/stunnel.pem ]; then
                echo -e " ${yellow}[*] Generando certificado SSL auto-firmado...${plain}"
                openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
                    -subj "/CN=joif-cloud/O=JOIF/C=CL" \
                    -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem > /dev/null 2>&1
                chmod 600 /etc/stunnel/stunnel.pem
            fi

            cat << 'EOF' > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel4.pid
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[ssl-proxy]
accept = 0.0.0.0:443
connect = 127.0.0.1:80
EOF

            sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4 2>/dev/null || true
            systemctl enable stunnel4 >/dev/null 2>&1
            systemctl restart stunnel4

            if command -v iptables &>/dev/null; then
                iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT >/dev/null 2>&1 || true
            fi
            if command -v ufw &>/dev/null; then
                ufw allow 443/tcp >/dev/null 2>&1 || true
            fi
            if command -v netfilter-persistent &>/dev/null; then
                netfilter-persistent save >/dev/null 2>&1 || true
            elif command -v iptables-save &>/dev/null; then
                mkdir -p /etc/iptables 2>/dev/null || true
                iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
            fi

            echo -e "\n${green}✅ Stunnel SSL 443 Activo reenviando a WebSocket 80.${plain}"
            pause
            ;;

        4)
            clear
            draw_header
            echo -e "${yellow}             [ ESTADO DE PROTOCOLOS EN VIVO ]${plain}"
            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
            check_svc() {
                local name="$1"
                local svc="$2"
                if systemctl is-active --quiet "$svc"; then
                    echo -e "  • ${white}%-28s${plain} ${green}[ACTIVO - ONLINE]${plain}" "$name"
                else
                    echo -e "  • ${white}%-28s${plain} ${red}[INACTIVO - OFF]${plain}" "$name"
                fi
            }
            printf "  • %-28s " "OpenSSH (Puerto 22)"
            if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then
                echo -e "${green}[ACTIVO - ONLINE]${plain}"
            else
                echo -e "${red}[INACTIVO]${plain}"
            fi

            printf "  • %-28s " "JOIF Web API (Puerto 3000)"
            if systemctl is-active --quiet joif; then
                echo -e "${green}[ACTIVO - ONLINE]${plain}"
            else
                echo -e "${red}[INACTIVO]${plain}"
            fi

            printf "  • %-28s " "WebSocket Proxy (Puerto 80)"
            if systemctl is-active --quiet joif-proxy; then
                echo -e "${green}[ACTIVO - ONLINE]${plain}"
            else
                echo -e "${red}[INACTIVO]${plain}"
            fi

            printf "  • %-28s " "SSL Stunnel (Puerto 443)"
            if systemctl is-active --quiet stunnel4; then
                echo -e "${green}[ACTIVO - ONLINE]${plain}"
            else
                echo -e "${red}[INACTIVO]${plain}"
            fi

            printf "  • %-28s " "BadVPN UDP-GW (7300/7200)"
            if systemctl is-active --quiet badvpn-7300 || pgrep -x "badvpn-udpgw" >/dev/null; then
                echo -e "${green}[ACTIVO - ONLINE]${plain}"
            else
                echo -e "${red}[INACTIVO]${plain}"
            fi

            printf "  • %-28s " "Limitador Multilogin"
            if systemctl is-active --quiet joif-limitador; then
                echo -e "${green}[ACTIVO - ONLINE]${plain}"
            else
                echo -e "${red}[INACTIVO]${plain}"
            fi

            printf "  • %-28s " "Xray VLESS (Puerto 80)"
            if systemctl is-active --quiet xray; then
                echo -e "${green}[ACTIVO - ONLINE]${plain}"
            else
                echo -e "${red}[INACTIVO]${plain}"
            fi

            pause
            ;;

        5)
            gestionar_xray_vless
            ;;

        30)
            if [ -f "/root/joif-core/modules/tools/extras_menu.sh" ]; then
                bash /root/joif-core/modules/tools/extras_menu.sh
            fi
            ;;
        0) break ;;
        *) echo -e "${red}Opción inválida${plain}"; sleep 1 ;;
    esac
done
