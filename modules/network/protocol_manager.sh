#!/bin/bash
# =========================================================
# JOIF Cloud - Gestor Modular de Protocolos
# =========================================================

source /root/joif-core/core/utils.sh 2>/dev/null

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
            echo -e "\n${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
            echo -e " 🚀 ${yellow}Configurando Proxy WebSocket Optimizado (Node.js)...${plain}"
            echo -e "   ${green}Zero-Latency (NoDelay) + KeepAlive 15s + EventLoop Libuv${plain}"
            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

            if ! command -v node &> /dev/null; then
                export DEBIAN_FRONTEND=noninteractive
                export NEEDRESTART_MODE=a
                apt-get update -qq && apt-get install -y -qq nodejs npm > /dev/null 2>&1
            fi
            NODE_BIN=$(command -v node || echo "/usr/bin/node")

            echo -e " ${yellow}[*] Liberando puerto 80 (deteniendo servicios que compitan)...${plain}"
            systemctl stop apache2 2>/dev/null || true
            systemctl disable apache2 2>/dev/null || true
            systemctl stop nginx 2>/dev/null || true
            systemctl stop python-proxy 2>/dev/null || true
            systemctl disable python-proxy 2>/dev/null || true
            if command -v fuser &>/dev/null; then
                fuser -k 80/tcp 2>/dev/null || true
            fi
            sleep 1

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

            iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT 2>/dev/null
            if command -v ufw &>/dev/null; then ufw allow 80/tcp &>/dev/null; fi
            netfilter-persistent save 2>/dev/null || true

            sleep 1
            if systemctl is-active --quiet joif-proxy; then
                echo -e "${green}✅ Proxy WebSocket Activo en puerto 80 -> Destino local 22.${plain}"
            else
                echo -e "${red}❌ No se pudo iniciar joif-proxy. Detalle de logs del sistema:${plain}"
                journalctl -u joif-proxy -n 8 --no-pager 2>/dev/null
            fi
            pause
            ;;

        2)
            clear
            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
            echo -e "         ${yellow}🎮 INSTALADOR BADVPN UDP-GW 🎮${plain}"
            echo -e "   ${white}Habilita puertos 7300 y 7200 para juegos y VoIP${plain}"
            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

            if [ -f "/usr/local/bin/badvpn-udpgw" ] || [ -f "/usr/bin/badvpn-udpgw" ]; then
                echo -e " ${green}✔ Binario badvpn-udpgw ya se encuentra instalado.${plain}"
            else
                echo -e " ${yellow}[*] Preparando dependencias de compilación...${plain}"
                export DEBIAN_FRONTEND=noninteractive
                export NEEDRESTART_MODE=a
                apt-get update -qq && apt-get install -y -qq cmake make gcc g++ build-essential unzip screen psmisc > /dev/null 2>&1

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
            fi

            cat << 'EOF' > /bin/JOIF-badvpn
#!/bin/bash
killall badvpn-udpgw 2>/dev/null
screen -dmS badvpn nice -n -15 /usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10
screen -dmS badUDP72 nice -n -15 /usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 1000 --max-connections-for-client 10
EOF
            chmod +x /bin/JOIF-badvpn

            cat << 'EOF' > /etc/systemd/system/badvpn-dual.service
[Unit]
Description=BadVPN Dual Channel Launcher (7300 & 7200)
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/JOIF-badvpn
ExecStop=/usr/bin/killall badvpn-udpgw
KillMode=none

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable badvpn-dual >/dev/null 2>&1
            systemctl restart badvpn-dual

            iptables -I INPUT 1 -p udp --dport 7300 -j ACCEPT 2>/dev/null
            iptables -I INPUT 1 -p udp --dport 7200 -j ACCEPT 2>/dev/null
            if command -v ufw &>/dev/null; then
                ufw allow 7300/udp &>/dev/null
                ufw allow 7200/udp &>/dev/null
            fi
            netfilter-persistent save 2>/dev/null || true

            echo -e "\n${green}✅ BadVPN Dual Channel Activo en puertos 7300 y 7200 UDP.${plain}"
            pause
            ;;

        3)
            clear
            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
            echo -e "            ${yellow}🔒 INSTALADOR SSL / TLS STUNNEL4 🔒${plain}"
            echo -e "    ${white}Túnel SSL en puerto 443 hacia el WebSocket (80)${plain}"
            echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

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

            iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT 2>/dev/null
            if command -v ufw &>/dev/null; then ufw allow 443/tcp &>/dev/null; fi
            netfilter-persistent save 2>/dev/null || true

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
            if pgrep -x "badvpn-udpgw" >/dev/null; then
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
