#!/bin/bash
clear
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "       \033[1;32m🚀 ACTUALIZANDO JOIF CLOUD 🚀\033[0m"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

SUCCESS=0

if [ -d "/root/joif-core/.git" ]; then
    echo -e " \033[1;33m[*] Sincronizando con repositorio oficial (Git Pull)...\033[0m"
    cd /root/joif-core
    git fetch origin main > /dev/null 2>&1
    if git reset --hard origin/main > /dev/null 2>&1; then
        SUCCESS=1
    fi
fi

if [ "$SUCCESS" != "1" ]; then
    echo -e " \033[1;33m[*] Descargando paquete de respaldo...\033[0m"
    wget -qO /tmp/core.zip "https://repo.juanconnect.online/joif-repo.zip?t=$(date +%s)"
    if [ -f /tmp/core.zip ]; then
        unzip -o /tmp/core.zip -d /root/joif-core > /dev/null 2>&1
        rm -f /tmp/core.zip
        SUCCESS=1
    fi
fi

if [ "$SUCCESS" = "1" ]; then
    chmod +x /root/joif-core/menu.sh /root/joif-core/update.sh 2>/dev/null
    chmod +x /root/joif-core/core/*.sh /root/joif-core/modules/**/*.sh 2>/dev/null
    
    # Prevenir que el comando 'menu' se quede pegado en rutas viejas
    unalias menu 2>/dev/null
    sed -i '/alias menu=/d' ~/.bashrc
    rm -f /usr/local/bin/menu /bin/menu
    ln -sf /root/joif-core/menu.sh /usr/bin/menu
    ln -sf /root/joif-core/update.sh /usr/bin/joif-update
    
    hash -r
    
    echo -e " \033[1;33m[*] Reiniciando panel web y servicios...\033[0m"
    systemctl restart joif 2>/dev/null || true
    systemctl is-active --quiet joif-proxy && systemctl restart joif-proxy 2>/dev/null || true
    
    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e " \033[1;32m✅ ACTUALIZACIÓN APLICADA CON ÉXITO EN 1 SEGUNDO ✅\033[0m"
    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
else
    echo -e " \033[1;31m❌ Error al actualizar el repositorio.\033[0m"
fi
