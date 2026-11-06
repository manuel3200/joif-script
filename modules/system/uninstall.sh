#!/bin/bash
# =========================================================
# JOIF Cloud - Desinstalador Seguro del Sistema
# =========================================================

source /root/joif-core/core/utils.sh 2>/dev/null

clear
echo -e "${red}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e "          ${yellow}⚠️  DESINSTALADOR DE JOIF CLOUD  ⚠️${plain}"
echo -e "${red}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e " ${white}Esta acción detendrá y removerá los servicios de JOIF:${plain}"
echo -e "  • Servicio Web y API Edge (puerto 3000)"
echo -e "  • Proxy WebSocket (puerto 80)"
echo -e "  • Limitador de multilogin y BadVPN"
echo -e "  • Comando global 'menu'"
echo -e ""
echo -e " ${green}✔ IMPORTANTE:${plain} Tu servidor SSH y tu acceso como root"
echo -e "   ${green}SEGUIRÁN ACTIVOS Y FUNCIONANDO.${plain} No perderás acceso al VPS."
echo -e "${red}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e ""
read -p "$(echo -e ${yellow}"¿Estás seguro de que deseas desinstalar JOIF? [s/N]: "${plain})" confirm_un

if [[ ! "$confirm_un" =~ ^[SsYy]$ ]]; then
    echo -e "\n${green}Operación cancelada. El sistema no ha sido modificado.${plain}"
    sleep 2
    exit 0
fi

echo -e ""
read -p "$(echo -e ${yellow}"¿Deseas respaldar la base de datos de usuarios antes de borrar? [S/n]: "${plain})" backup_db
if [[ ! "$backup_db" =~ ^[Nn]$ ]]; then
    if [ -f /root/joif-core/database.sqlite ]; then
        BACKUP_DEST="/root/joif-users-backup-$(date +%Y%m%d-%H%M).sqlite"
        cp -f /root/joif-core/database.sqlite "$BACKUP_DEST"
        echo -e "  ${green}✔ Copia guardada en: $BACKUP_DEST${plain}"
    fi
fi

echo -e "\n${blue}[1/4] Deteniendo y deshabilitando servicios...${plain}"
for svc in joif joif-proxy joif-limitador joif-api badvpn-dual badvpn; do
    systemctl stop "$svc" 2>/dev/null
    systemctl disable "$svc" 2>/dev/null
    rm -f "/etc/systemd/system/${svc}.service"
done
systemctl daemon-reload

echo -e "${blue}[2/4] Limpiando procesos de BadVPN y proxies...${plain}"
killall badvpn-udpgw 2>/dev/null || true
screen -wipe 2>/dev/null || true

echo -e "${blue}[3/4] Eliminando comandos de terminal y alias...${plain}"
rm -f /usr/bin/menu /usr/local/bin/menu /bin/menu /usr/bin/joif-update /bin/JOIF-badvpn
sed -i '/alias menu=/d' /root/.bashrc
sed -i '\|/usr/bin/menu|d' /root/.bashrc

echo -e "${blue}[4/4] Removiendo archivos del núcleo...${plain}"
rm -rf /root/joif-core /tmp/core.zip /root/.JOIF_welcome_done

echo -e "\n${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e "   ${green}✅ JOIF CLOUD HA SIDO DESINSTALADO COMPLETAMENTE ✅${plain}"
echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e " Tu terminal SSH sigue activa y sin interrupciones."
echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}\n"
exit 0
