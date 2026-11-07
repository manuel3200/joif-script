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

while true; do
    clear
    draw_header
    echo -e "${yellow}             [ INSTALADOR MODULAR DE PROTOCOLOS ]${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${green}[1]${plain} > ⚡ Proxy WebSocket Optimizado (Puerto 80 -> 22)"
    echo -e " ${green}[2]${plain} > 🎮 BadVPN UDP-GW (Puertos 7300 y 7200 - Juegos y Llamadas)"
    echo -e " ${green}[3]${plain} > 🔒 SSL / TLS Stunnel (Puerto 443 -> WS 80 o SSH 22)"
    echo -e " ${green}[4]${plain} > 📊 Estado de Protocolos en Vivo"
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

            pause
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
