#!/bin/bash
# =========================================================================
# JOIF Cloud v2.0 — Desinstalador Completo y Seguro (Sin cortar SSH)
# =========================================================================

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "${SCRIPT_DIR}/../../core/utils.sh" 2>/dev/null || source /root/joif-core/core/utils.sh 2>/dev/null

ui_title "DESINSTALADOR DE JOIF CLOUD"
echo -e "  ${white}Se detendrán y eliminarán todos los componentes de JOIF:${plain}"
echo -e "   • Servicios: joif, joif-proxy, joif-limitador, badvpn, smartdns-client"
echo -e "   • Reglas DNAT SmartDNS (JOIF_SMARTDNS_OUT), sysctl BBR y tuning SSH"
echo -e "   • Comandos globales: menu, joif-update, joif-bbr, bbr, joif-smartdns"
echo -e ""
echo -e "  ${green}✔ Tu servidor SSH y acceso root seguirán intactos.${plain}"
ui_line
read -r -p "$(echo -e "${yellow}¿Seguro que deseas desinstalar JOIF Cloud? [s/N]: ${plain}")" confirm_un
[[ ! "$confirm_un" =~ ^[SsYy]$ ]] && { echo -e "\n  ${green}Cancelado.${plain}"; sleep 1; exit 0; }

read -r -p "$(echo -e "${yellow}¿Respaldar la base de datos antes de borrar? [S/n]: ${plain}")" backup_db
if [[ ! "$backup_db" =~ ^[Nn]$ ]] && [ -f /root/joif-core/database.sqlite ]; then
    BACKUP_DEST="/root/joif-users-backup-$(date +%Y%m%d-%H%M).sqlite"
    sqlite3 /root/joif-core/database.sqlite ".backup '${BACKUP_DEST}'" 2>/dev/null || cp -f /root/joif-core/database.sqlite "$BACKUP_DEST"
    chmod 600 "$BACKUP_DEST" 2>/dev/null || true
    echo -e "  ${green}✔ Respaldo guardado en: ${BACKUP_DEST}${plain}"
fi

read -r -p "$(echo -e "${yellow}¿Eliminar también las cuentas VPN de Linux? [s/N]: ${plain}")" purge_users
if [[ "$purge_users" =~ ^[SsYy]$ ]] && [ -f /root/joif-core/database.sqlite ]; then
    while IFS='|' read -r uname uhwid; do
        target="${uhwid:-$uname}"
        [ -z "$target" ] && continue
        pkill -KILL -u "$target" 2>/dev/null || true
        userdel -f "$target" 2>/dev/null || true
    done < <(sqlite3 -separator '|' /root/joif-core/database.sqlite "SELECT username, hwid FROM users;" 2>/dev/null)
    echo -e "  ${green}✔ Cuentas VPN de Linux eliminadas.${plain}"
fi

echo -e "\n${blue}[1/4] Deteniendo y eliminando servicios systemd...${plain}"
for svc in joif joif-proxy joif-limitador joif-api joif-smartdns-client joif-smartdns-watchdog joif-firewall badvpn-dual badvpn badvpn-7300 badvpn-7200; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
    rm -f "/etc/systemd/system/${svc}.service"
done
systemctl daemon-reload

echo -e "${blue}[2/4] Limpiando reglas SmartDNS, Firewall, sysctl y configs drop-in SSH...${plain}"
bash /root/joif-core/modules/network/firewall_manager.sh --disable-all >/dev/null 2>&1 || true
while iptables -t nat -C OUTPUT -j JOIF_SMARTDNS_OUT >/dev/null 2>&1; do
    iptables -t nat -D OUTPUT -j JOIF_SMARTDNS_OUT 2>/dev/null || break
done
iptables -t nat -F JOIF_SMARTDNS_OUT 2>/dev/null || true
iptables -t nat -X JOIF_SMARTDNS_OUT 2>/dev/null || true
persist_firewall

rm -f /etc/joif-smartdns-client.conf /etc/joif-firewall.conf /var/log/joif-smartdns-failover.log /run/joif-smartdns-state
rm -f /etc/sysctl.d/99-vpn-tuning.conf /etc/sysctl.d/98-joif-swap.conf
rm -f /etc/ssh/sshd_config.d/99-vpn-speed.conf /etc/ssh/sshd_config.d/95-joif-banner.conf
safe_reload_ssh 2>/dev/null || true

echo -e "${blue}[3/4] Eliminando comandos de terminal y autoinicio...${plain}"
rm -f /usr/bin/menu /usr/local/bin/menu /bin/menu /usr/bin/joif-update /usr/bin/joif-bbr /usr/bin/bbr /usr/local/bin/joif-smartdns /usr/local/bin/joif-firewall /bin/JOIF-badvpn
sed -i '/alias menu=/d;\|/usr/bin/menu|d' /root/.bashrc 2>/dev/null || true

echo -e "${blue}[4/4] Removiendo directorio /root/joif-core...${plain}"
rm -rf /root/joif-core /tmp/core.zip /run/joif_public_ip /root/.JOIF_welcome_done

echo -e "\n${green}✅ JOIF CLOUD desinstalado limpiamente. Tu acceso SSH sigue intacto.${plain}\n"
exit 0
