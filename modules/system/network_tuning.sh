#!/bin/bash
# ==============================================================================
#  🚀 SCRIPT DE OPTIMIZACIÓN DE RED Y SSH PARA VPS VPN (JOIF CLOUD)
#  Ajustes de TCP BBR, Búferes del Kernel, OpenSSH y BadVPN para baja latencia
# ==============================================================================

# Colores
red='\033[1;31m'
green='\033[1;32m'
yellow='\033[1;33m'
blue='\033[1;34m'
cyan='\033[1;36m'
white='\033[1;37m'
plain='\033[0m'

clear
echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e " ⚡ ${yellow}OPTIMIZACIÓN DE RED Y TCP BBR EN VPS${plain} ⚡"
echo -e "    ${green}Aceleración Gaming, Anti-Bufferbloat y Baja Latencia${plain}"
echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

echo -e "\n ${yellow}[*] Paso 1: Habilitando módulo de congestión TCP BBR...${plain}"
modprobe tcp_bbr 2>/dev/null || true

echo -e " ${yellow}[*] Paso 2: Aplicando configuración de kernel sysctl...${plain}"
cat << 'EOF' > /etc/sysctl.d/99-vpn-tuning.conf
# Cola de paquetes FQ y Algoritmo de Congestión BBR (Google)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP Fast Open para clientes y servidores (0-RTT TCP)
net.ipv4.tcp_fastopen = 3

# Evitar slow-start tras reposo (crucial para no sufrir lag en 4G/LTE)
net.ipv4.tcp_slow_start_after_idle = 0

# Límite de búfer de cola no enviada para minimizar latencia (anti-bufferbloat)
net.ipv4.tcp_notsent_lowat = 16384

# Descubrimiento dinámico de MTU para evitar agujeros negros de paquetes en 4G
net.ipv4.tcp_mtu_probing = 1

# Reutilización rápida de sockets en TIME_WAIT para alta concurrencia
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# Escalado de ventana TCP para aprovechar todo el ancho de banda
net.ipv4.tcp_adv_win_scale = 1

# Optimización de búferes de recepción y envío TCP para alto ancho de banda
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Búferes UDP para gaming (Free Fire, COD, VoIP) y BadVPN
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_max_syn_backlog = 8192

# Reenvío de paquetes IP (IPv4 y IPv6)
net.ipv4.ip_forward = 1
EOF

sysctl --system > /dev/null 2>&1
echo -e " ${green}✔ Módulo TCP BBR, búferes y colas FQ aplicados con éxito.${plain}"

echo -e "\n ${yellow}[*] Paso 3: Optimizando servidor OpenSSH para baja latencia...${plain}"
mkdir -p /etc/ssh/sshd_config.d
cat << 'EOF' > /etc/ssh/sshd_config.d/99-vpn-speed.conf
# Keepalive para evitar cortes de antena 4G / NAT de la operadora
ClientAliveInterval 15
ClientAliveCountMax 4
TCPKeepAlive yes

# Desactivar compresión SSH (ahorra CPU del servidor y reduce 5-10ms de latencia)
Compression no

# Desactivar resolución inversa de DNS (conexión instantánea sin esperas)
UseDNS no

# Permitir ráfagas de conexiones concurrentes para pools de Zeptun
MaxStartups 100:30:200

# Cifrados de alto rendimiento con aceleración por hardware en procesadores ARM y x86
Ciphers chacha20-poly1305@openssh.com,aes128-gcm@openssh.com,aes256-gcm@openssh.com
EOF

systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
echo -e " ${green}✔ OpenSSH configurado con KeepAlive, sin compresión y cifrados ultra-rápidos.${plain}"

echo -e "\n ${yellow}[*] Paso 4: Optimizando BadVPN UDP-GW (Puertos 7300 y 7200)...${plain}"
BADVPN_BIN="/usr/local/bin/badvpn-udpgw"
[ ! -f "$BADVPN_BIN" ] && BADVPN_BIN=$(command -v badvpn-udpgw 2>/dev/null || echo "/usr/bin/badvpn-udpgw")

if [ -f "$BADVPN_BIN" ]; then
    cat << EOF > /etc/systemd/system/badvpn-7300.service
[Unit]
Description=BadVPN UDP Gateway (Port 7300)
After=network.target

[Service]
Type=simple
User=root
ExecStart=$BADVPN_BIN --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 500 --client-socket-sndbuf 65536
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
ExecStart=$BADVPN_BIN --listen-addr 127.0.0.1:7200 --max-clients 1000 --max-connections-for-client 500 --client-socket-sndbuf 65536
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1
    systemctl restart badvpn-7300 badvpn-7200 >/dev/null 2>&1
    echo -e " ${green}✔ BadVPN optimizado para 500 conexiones UDP por cliente y reiniciado.${plain}"
fi

systemctl is-active --quiet badvpn-7300.service && echo -e " ${green}✔ badvpn-7300: ACTIVO${plain}" || echo -e " ${red}⚠ badvpn-7300: INACTIVO${plain}"
systemctl is-active --quiet badvpn-7200.service && echo -e " ${green}✔ badvpn-7200: ACTIVO${plain}" || echo -e " ${red}⚠ badvpn-7200: INACTIVO${plain}"

echo -e "\n${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e " ${green}🎉 ¡OPTIMIZACIÓN DEL SERVIDOR VPS COMPLETADA!${plain}"
echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo ""
read -p "Presiona [Enter] para continuar..."
