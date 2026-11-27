#!/bin/bash
# =========================================================================
# JOIF Cloud v2.0 — Actualizador Rápido (Git Pull Oficial)
# =========================================================================

clear
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "  \033[1;32mJOIF CLOUD v2.0\033[0m \033[0;90m│\033[0m \033[1;33mActualizando desde GitHub...\033[0m"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

SUCCESS=0
if [ -d "/root/joif-core/.git" ]; then
    cd /root/joif-core || exit 1
    git fetch origin main >/dev/null 2>&1
    if git reset --hard origin/main >/dev/null 2>&1; then
        SUCCESS=1
    fi
fi

if [ "$SUCCESS" != "1" ]; then
    echo -e " \033[1;33m[*] Descargando paquete de respaldo...\033[0m"
    wget -qO /tmp/core.zip "https://repo.juanconnect.online/joif-repo.zip?t=$(date +%s)"
    if [ -f /tmp/core.zip ]; then
        unzip -qo /tmp/core.zip -d /root/joif-core >/dev/null 2>&1
        rm -f /tmp/core.zip
        SUCCESS=1
    fi
fi

if [ "$SUCCESS" = "1" ]; then
    chmod +x /root/joif-core/menu.sh /root/joif-core/update.sh /root/joif-core/limitador.sh 2>/dev/null || true
    chmod -R +x /root/joif-core/core /root/joif-core/modules 2>/dev/null || true

    unalias menu 2>/dev/null || true
    sed -i '/alias menu=/d' /root/.bashrc 2>/dev/null || true
    rm -f /usr/local/bin/menu /bin/menu
    ln -sf /root/joif-core/menu.sh /usr/bin/menu
    ln -sf /root/joif-core/update.sh /usr/bin/joif-update
    ln -sf /root/joif-core/modules/system/network_tuning.sh /usr/bin/joif-bbr
    ln -sf /root/joif-core/modules/system/network_tuning.sh /usr/bin/bbr
    ln -sf /root/joif-core/modules/network/smartdns_client.sh /usr/local/bin/joif-smartdns
    ln -sf /root/joif-core/modules/network/firewall_manager.sh /usr/local/bin/joif-firewall
    hash -r

    # Limpiar servicio duplicado heredado si existía
    if systemctl list-unit-files 2>/dev/null | grep -q '^joif-api\.service'; then
        systemctl stop joif-api 2>/dev/null || true
        systemctl disable joif-api 2>/dev/null || true
        rm -f /etc/systemd/system/joif-api.service
        systemctl daemon-reload
    fi

    echo -e " \033[1;33m[*] Reiniciando servicios activos...\033[0m"
    systemctl restart joif 2>/dev/null || true
    systemctl is-active --quiet joif-proxy && systemctl restart joif-proxy 2>/dev/null || true
    systemctl is-active --quiet joif-limitador && systemctl restart joif-limitador 2>/dev/null || true
    systemctl is-active --quiet badvpn-7300 && systemctl restart badvpn-7300 2>/dev/null || true
    systemctl is-active --quiet badvpn-7200 && systemctl restart badvpn-7200 2>/dev/null || true
    systemctl is-active --quiet joif-smartdns-watchdog && systemctl restart joif-smartdns-watchdog 2>/dev/null || true
    if [ -f /etc/joif-firewall.conf ]; then
        bash /root/joif-core/modules/network/firewall_manager.sh --apply >/dev/null 2>&1 || true
    fi

    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e " \033[1;32m✔ Actualización aplicada correctamente.\033[0m"
    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
else
    echo -e " \033[1;31m✖ Error al actualizar el repositorio.\033[0m"
    exit 1
fi
