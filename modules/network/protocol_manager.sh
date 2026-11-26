#!/bin/bash
# =========================================================================
# JOIF Cloud v2.0 — Gestor Modular de Protocolos (WS-Proxy, BadVPN, SSL)
# =========================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../core/utils.sh" 2>/dev/null || source /root/joif-core/core/utils.sh 2>/dev/null

liberar_puerto_80() {
    echo -e " ${yellow}[*] Analizando y liberando puerto 80...${plain}"
    systemctl stop joif-proxy 2>/dev/null || true

    local known_svcs=("nginx" "apache2" "httpd" "lighttpd" "caddy" "haproxy" "openresty" "python-proxy" "epro" "eproxy" "wsproxy" "chumo-proxy" "socks")
    for svc in "${known_svcs[@]}"; do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
    done

    local pids=""
    if command -v lsof >/dev/null 2>&1; then
        pids=$(lsof -t -i:80 2>/dev/null || true)
    elif command -v fuser >/dev/null 2>&1; then
        pids=$(fuser 80/tcp 2>/dev/null || true)
    fi

    for p in $pids; do
        [ -z "$p" ] && continue
        local unit
        unit=$(systemctl status "$p" 2>/dev/null | grep -oE '[a-zA-Z0-9_.-]+\.service' | head -n1)
        if [ -n "$unit" ] && [ "$unit" != "joif-proxy.service" ]; then
            systemctl stop "$unit" 2>/dev/null || true
            systemctl disable "$unit" 2>/dev/null || true
        fi
        kill -9 "$p" 2>/dev/null || true
    done

    pkill -9 -f "PDirect|P3Direct|PPub|PPriv|wsproxy|epro|proxy\.js" 2>/dev/null || true
    command -v fuser >/dev/null 2>&1 && fuser -k -9 80/tcp >/dev/null 2>&1 || true

    for _ in 1 2 3 4 5; do
        if ! ss -tlpn 2>/dev/null | grep -qE '(:80[[:space:]]|:80$)'; then
            echo -e " ${green}✔ Puerto 80 liberado correctamente.${plain}"
            return 0
        fi
        sleep 1
    done
    echo -e " ${red}✖ No se pudo liberar por completo el puerto 80.${plain}"
    return 1
}

gestionar_ws_proxy() {
    ui_title "PROXY WEBSOCKET (PUERTO 80 -> SSH 22)"
    if systemctl is-active --quiet joif-proxy 2>/dev/null; then
        echo -e "  ${green}● joif-proxy se encuentra ACTIVO en puerto 80.${plain}\n"
        echo -e "  ${green}[1]${plain} Reiniciar y verificar puerto 80"
        echo -e "  ${red}[2]${plain} Detener servicio y liberar puerto 80"
        echo -e "  ${white}[0]${plain} Volver"
        ui_subline
        read -r -p "$(echo -e "${white}Opción: ${plain}")" ws_act
        case "$ws_act" in
            2)
                systemctl stop joif-proxy 2>/dev/null || true
                systemctl disable joif-proxy 2>/dev/null || true
                echo -e "  ${green}✔ Proxy WebSocket detenido.${plain}"
                pause; return
                ;;
            0|"") return ;;
        esac
    fi

    local node_bin
    node_bin=$(command -v node 2>/dev/null || echo "/usr/bin/node")
    liberar_puerto_80

    cat << EOF > /etc/systemd/system/joif-proxy.service
[Unit]
Description=JOIF High-Performance WebSocket SSH Proxy (Port 80)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/joif-core
ExecStart=${node_bin} /root/joif-core/proxy.js --port 80 --target 22
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable joif-proxy >/dev/null 2>&1
    systemctl restart joif-proxy
    ensure_firewall_port 80 "tcp"
    persist_firewall

    sleep 1
    if systemctl is-active --quiet joif-proxy; then
        echo -e "\n  ${green}✔ Proxy WebSocket activo en puerto 80 -> SSH local 22.${plain}"
    else
        echo -e "\n  ${red}✖ Error al iniciar joif-proxy:${plain}"
        journalctl -u joif-proxy -n 10 --no-pager 2>/dev/null
    fi
    pause
}

gestionar_badvpn() {
    ui_title "BADVPN UDP-GW (PUERTOS 7300 Y 7200)"
    if systemctl is-active --quiet badvpn-7300 || systemctl is-active --quiet badvpn-7200; then
        echo -e "  ${green}● BadVPN UDP-GW se encuentra ACTIVO (7300 / 7200).${plain}\n"
        echo -e "  ${green}[1]${plain} Reiniciar / Reaplicar optimización (500 conn/cliente)"
        echo -e "  ${red}[2]${plain} Detener BadVPN y liberar puertos"
        echo -e "  ${white}[0]${plain} Volver"
        ui_subline
        read -r -p "$(echo -e "${white}Opción: ${plain}")" bad_act
        case "$bad_act" in
            2)
                systemctl stop badvpn-7300 badvpn-7200 badvpn-dual 2>/dev/null || true
                systemctl disable badvpn-7300 badvpn-7200 badvpn-dual 2>/dev/null || true
                pkill -9 -x badvpn-udpgw 2>/dev/null || true
                echo -e "  ${green}✔ BadVPN detenido.${plain}"
                pause; return
                ;;
            0|"") return ;;
        esac
    fi

    local badvpn_bin=""
    for cand in /usr/local/bin/badvpn-udpgw /usr/bin/badvpn-udpgw "$(command -v badvpn-udpgw 2>/dev/null || true)"; do
        [ -n "$cand" ] && [ -x "$cand" ] && { badvpn_bin="$cand"; break; }
    done

    if [ -z "$badvpn_bin" ]; then
        echo -e " ${yellow}[*] Compilando badvpn-udpgw...${plain}"
        DEBIAN_FRONTEND=noninteractive apt-get update -qq && apt-get install -y -qq cmake make gcc g++ build-essential unzip >/dev/null 2>&1
        rm -rf /tmp/badvpn* 2>/dev/null
        wget -qO /tmp/badvpn.zip https://github.com/ambrop72/badvpn/archive/master.zip
        unzip -qo /tmp/badvpn.zip -d /tmp
        (cd /tmp/badvpn-master && mkdir -p build && cd build && cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 >/dev/null 2>&1 && make install >/dev/null 2>&1)
        rm -rf /tmp/badvpn* 2>/dev/null
        badvpn_bin="/usr/local/bin/badvpn-udpgw"
    fi

    if [ ! -x "$badvpn_bin" ]; then
        echo -e "  ${red}✖ No se pudo compilar o localizar badvpn-udpgw.${plain}"
        pause; return
    fi

    systemctl stop badvpn-dual badvpn-7300 badvpn-7200 2>/dev/null || true
    systemctl disable badvpn-dual 2>/dev/null || true
    rm -f /etc/systemd/system/badvpn-dual.service /bin/JOIF-badvpn 2>/dev/null || true
    pkill -9 -x badvpn-udpgw 2>/dev/null || true

    for port in 7300 7200; do
        cat << EOF > "/etc/systemd/system/badvpn-${port}.service"
[Unit]
Description=BadVPN UDP Gateway (Port ${port})
After=network.target

[Service]
Type=simple
User=root
ExecStart=${badvpn_bin} --listen-addr 127.0.0.1:${port} --max-clients 1000 --max-connections-for-client 500 --client-socket-sndbuf 65536
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    done

    systemctl daemon-reload
    systemctl enable badvpn-7300 badvpn-7200 >/dev/null 2>&1
    systemctl restart badvpn-7300 badvpn-7200
    ensure_firewall_port 7300 "udp"
    ensure_firewall_port 7200 "udp"
    persist_firewall

    sleep 1
    if systemctl is-active --quiet badvpn-7300 && systemctl is-active --quiet badvpn-7200; then
        echo -e "\n  ${green}✔ BadVPN activo en 7300 y 7200 (500 conn/cliente, sndbuf 64KB).${plain}"
    else
        echo -e "\n  ${red}✖ Error al iniciar BadVPN.${plain}"
    fi
    pause
}

gestionar_stunnel() {
    ui_title "SSL / TLS STUNNEL4 (PUERTO 443 -> WS 80)"
    if systemctl is-active --quiet stunnel4 2>/dev/null; then
        echo -e "  ${green}● Stunnel SSL se encuentra ACTIVO en puerto 443.${plain}\n"
        echo -e "  ${green}[1]${plain} Reiniciar / Reconfigurar Stunnel"
        echo -e "  ${red}[2]${plain} Detener Stunnel y liberar puerto 443"
        echo -e "  ${white}[0]${plain} Volver"
        ui_subline
        read -r -p "$(echo -e "${white}Opción: ${plain}")" st_act
        case "$st_act" in
            2)
                systemctl stop stunnel4 2>/dev/null || true
                systemctl disable stunnel4 2>/dev/null || true
                echo -e "  ${green}✔ Stunnel detenido.${plain}"
                pause; return
                ;;
            0|"") return ;;
        esac
    fi

    DEBIAN_FRONTEND=noninteractive apt-get update -qq && apt-get install -y -qq stunnel4 openssl >/dev/null 2>&1
    mkdir -p /etc/stunnel
    if [ ! -f /etc/stunnel/stunnel.pem ]; then
        openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
            -subj "/CN=joif-cloud/O=JOIF/C=AR" \
            -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem >/dev/null 2>&1
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
    ensure_firewall_port 443 "tcp"
    persist_firewall

    echo -e "\n  ${green}✔ Stunnel SSL 443 activo -> WebSocket 80.${plain}"
    pause
}

mostrar_estado_protocolos() {
    ui_title "ESTADO DE PROTOCOLOS Y SERVICIOS EN VIVO"
    print_row() {
        local label="$1" ok="$2" extra="${3:-}"
        if [ "$ok" -eq 1 ]; then
            printf "  ${white}%-30s${plain} ${green}● ACTIVO${plain} %s\n" "$label" "$extra"
        else
            printf "  ${white}%-30s${plain} ${red}○ INACTIVO${plain}\n" "$label"
        fi
    }

    local s_ssh=0 s_api=0 s_ws=0 s_ssl=0 s_bad=0 s_lim=0 s_bbr=0 s_sdns=0
    (systemctl is-active --quiet ssh || systemctl is-active --quiet sshd) 2>/dev/null && s_ssh=1
    systemctl is-active --quiet joif 2>/dev/null && s_api=1
    systemctl is-active --quiet joif-proxy 2>/dev/null && s_ws=1
    systemctl is-active --quiet stunnel4 2>/dev/null && s_ssl=1
    (systemctl is-active --quiet badvpn-7300 || pgrep -x badvpn-udpgw >/dev/null) 2>/dev/null && s_bad=1
    systemctl is-active --quiet joif-limitador 2>/dev/null && s_lim=1
    sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | grep -qx 'bbr' && s_bbr=1
    iptables -t nat -C OUTPUT -j JOIF_SMARTDNS_OUT >/dev/null 2>&1 && s_sdns=1

    print_row "OpenSSH (Puerto 22)" "$s_ssh"
    print_row "JOIF CheckUser API" "$s_api" "(:$(get_api_port))"
    print_row "WebSocket Proxy (Puerto 80)" "$s_ws"
    print_row "SSL Stunnel (Puerto 443)" "$s_ssl"
    print_row "BadVPN UDP-GW (7300/7200)" "$s_bad"
    print_row "Limitador Multilogin" "$s_lim"
    print_row "TCP BBR (Kernel)" "$s_bbr"
    print_row "Smart DNS Cliente (AR)" "$s_sdns"
    ui_line
    pause
}

while true; do
    draw_header
    echo -e "  ${yellow}PROTOCOLOS VPN Y TÚNELES${plain}"
    ui_subline
    echo -e "  ${green}[1]${plain} Proxy WebSocket Optimizado (Puerto 80 -> 22)"
    echo -e "  ${green}[2]${plain} BadVPN UDP-GW (Puertos 7300 y 7200)"
    echo -e "  ${green}[3]${plain} SSL / TLS Stunnel (Puerto 443 -> WS 80)"
    echo -e "  ${green}[4]${plain} Estado de protocolos en vivo"
    echo -e "  ${red}[0]${plain} Volver al menú principal"
    ui_line
    read -r -p "$(echo -e "${white}Selecciona una opción: ${plain}")" opt_prot

    case "$opt_prot" in
        1) gestionar_ws_proxy ;;
        2) gestionar_badvpn ;;
        3) gestionar_stunnel ;;
        4) mostrar_estado_protocolos ;;
        0|00) break ;;
        *) echo -e "  ${red}Opción inválida.${plain}"; sleep 1 ;;
    esac
done
