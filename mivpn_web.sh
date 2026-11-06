#!/bin/bash
# MiVPN Web Manager CLI
# Para administración del panel web de Node.js de MiVPN

# Definición de Colores para el UI interactivo
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Directorio del Panel
WEB_DIR="/root/mivpn/edge-node-manager" 
# Fallback local para pruebas
if [ ! -d "$WEB_DIR" ]; then
    WEB_DIR=$(pwd)
fi

DB_FILE="$WEB_DIR/database.sqlite"
ENV_FILE="$WEB_DIR/.env"

show_menu() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${GREEN}      MiVPN Web Manager - Herramientas Premium    ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    
    # Determinar si el servicio está corriendo para colorear el estado
    STATUS_WEB="${RED}[OFF]${NC}"
    if systemctl is-active --quiet mivpn-web 2>/dev/null; then
        STATUS_WEB="${GREEN}[ON]${NC}"
    fi

    echo -e " 1) ${YELLOW}Activar/Desactivar Panel Web${NC} $STATUS_WEB"
    echo -e " 2) ${YELLOW}Restablecer Credenciales Web (Admin)${NC}"
    echo -e " 3) ${YELLOW}Cambiar Puerto del Panel Web${NC}"
    echo -e " 4) ${YELLOW}Protección Anti-Hackers (Bloqueo por IP)${NC}"
    echo -e " 5) ${MAGENTA}Ver Logs y Auditoría (Modo Espía en Vivo)${NC}"
    echo -e " 6) ${RED}Forzar Cierre de Todas las Sesiones Web${NC}"
    echo -e " 7) ${GREEN}Actualizar Panel Web (Desde Repositorio)${NC}"
    echo -e " 8) ${CYAN}Crear Backup de Base de Datos y Entorno${NC}"
    echo -e " 9) ${CYAN}Restaurar Backup${NC}"
    echo -e " 0) ${RED}Salir al Sistema${NC}"
    echo -e "${CYAN}====================================================${NC}"
    read -p "Elige una opción: " opcion
    case $opcion in
        1) toggle_web ;;
        2) reset_credentials ;;
        3) change_port ;;
        4) ip_protection ;;
        5) view_logs ;;
        6) force_logout ;;
        7) update_panel ;;
        8) backup_web ;;
        9) restore_backup ;;
        0) exit 0 ;;
        *) echo "Opción inválida"; sleep 1; show_menu ;;
    esac
}

toggle_web() {
    echo -e "${CYAN}Verificando estado del servicio mivpn-web...${NC}"
    if systemctl is-active --quiet mivpn-web 2>/dev/null; then
        echo -e "${RED}El panel web está encendido. Apagando...${NC}"
        systemctl stop mivpn-web
        systemctl disable mivpn-web
        echo -e "${YELLOW}Panel Web Desactivado y retirado del auto-arranque.${NC}"
    else
        echo -e "${GREEN}El panel web está apagado. Encendiendo...${NC}"
        
        # Instalar dependencias si no existen
        if [ ! -d "$WEB_DIR/node_modules" ]; then
            echo -e "${CYAN}Instalando dependencias de Node.js por primera vez...${NC}"
            cd $WEB_DIR && npm install
        fi

        # Crear servicio systemd
        if [ ! -f /etc/systemd/system/mivpn-web.service ]; then
            echo -e "${CYAN}Configurando servicio persistente SystemD...${NC}"
            cat <<EOF > /etc/systemd/system/mivpn-web.service
[Unit]
Description=MiVPN Edge Node Manager Web Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WEB_DIR
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=3
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
        fi
        
        systemctl enable mivpn-web
        systemctl start mivpn-web
        echo -e "${GREEN}¡Panel Web Activado! Se iniciará automáticamente con el VPS.${NC}"
    fi
    read -p "Presiona Enter para volver al menú..."
    show_menu
}

reset_credentials() {
    echo -e "${CYAN}--- Restablecimiento de Credenciales de Administrador ---${NC}"
    if ! command -v sqlite3 &> /dev/null; then
        echo -e "${RED}Error: sqlite3 no está instalado. Instalándolo...${NC}"
        apt-get install sqlite3 -y
    fi

    read -p "Ingresa el nuevo Nombre de Usuario: " new_user
    read -p "Ingresa la nueva Contraseña: " new_pass
    
    sqlite3 $DB_FILE "UPDATE admin_config SET value = '$new_user' WHERE key = 'admin_user';"
    sqlite3 $DB_FILE "UPDATE admin_config SET value = '$new_pass' WHERE key = 'admin_pass';"
    
    echo -e "${GREEN}¡Credenciales inyectadas en SQLite exitosamente!${NC}"
    read -p "Presiona Enter para volver..."
    show_menu
}

change_port() {
    echo -e "${CYAN}--- Configuración de Puerto ---${NC}"
    
    if [ ! -f $ENV_FILE ]; then
        touch $ENV_FILE
    fi

    CURRENT_PORT=$(grep PORT $ENV_FILE | cut -d '=' -f2)
    echo -e "El puerto actual es: ${YELLOW}${CURRENT_PORT:-3000}${NC}"
    
    read -p "Ingresa el nuevo puerto (ej. 80, 8080): " new_port
    
    if grep -q "PORT=" "$ENV_FILE"; then
        sed -i "s/^PORT=.*/PORT=$new_port/" $ENV_FILE
    else
        echo "PORT=$new_port" >> $ENV_FILE
    fi
    
    if systemctl is-active --quiet mivpn-web 2>/dev/null; then
        systemctl restart mivpn-web
        echo -e "${GREEN}Puerto actualizado. Panel reiniciado.${NC}"
    else
        echo -e "${GREEN}Puerto actualizado. (El panel está apagado actualmente).${NC}"
    fi
    read -p "Presiona Enter para volver..."
    show_menu
}

ip_protection() {
    echo -e "${CYAN}--- Protección Anti-Hackers (Whitelist de IP) ---${NC}"
    echo "Esto usará Iptables para bloquear el acceso web a todos excepto a tu IP."
    
    PORT=$(grep PORT $ENV_FILE | cut -d '=' -f2)
    PORT=${PORT:-3000}
    
    read -p "Ingresa tu IP Pública de confianza (o deja vacío para desactivar protección): " ip_trust
    
    # Limpiar reglas viejas del puerto Web
    iptables -D INPUT -p tcp --dport $PORT -j DROP 2>/dev/null
    iptables -D INPUT -p tcp --dport $PORT -j ACCEPT 2>/dev/null
    # Eliminar cualquier IP whitelistada previa de forma agresiva
    iptables-save | grep "dport $PORT" | sed 's/-A/-D/' | while read cmd; do iptables $cmd 2>/dev/null; done

    if [ -n "$ip_trust" ]; then
        iptables -A INPUT -p tcp --dport $PORT -s $ip_trust -j ACCEPT
        iptables -A INPUT -p tcp --dport $PORT -j DROP
        
        # Guardar iptables (Depende de distro, asumiendo Ubuntu/Debian con iptables-persistent)
        netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4 2>/dev/null
        
        echo -e "${GREEN}¡Escudo Activado! Solo la IP $ip_trust puede entrar al puerto $PORT.${NC}"
    else
        iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
        echo -e "${YELLOW}Escudo Desactivado. El panel ahora es público a cualquier IP.${NC}"
    fi
    
    read -p "Presiona Enter para volver..."
    show_menu
}

view_logs() {
    echo -e "${CYAN}--- Modo Espía: Logs en vivo de Node.js ---${NC}"
    echo -e "Para salir de este modo, presiona ${RED}CTRL+C${NC}."
    journalctl -u mivpn-web -f -n 50
    show_menu
}

force_logout() {
    echo -e "${RED}⚠️ ATENCIÓN: Esto expulsará a cualquier persona logueada en la web ⚠️${NC}"
    echo -e "Invalidará los JWT rotando la llave criptográfica."
    read -p "¿Estás seguro? (s/n): " conf
    if [ "$conf" == "s" ]; then
        # Generar llave de 32 bytes en hex
        NEW_SECRET=$(openssl rand -hex 32)
        
        if [ ! -f $ENV_FILE ]; then touch $ENV_FILE; fi
        
        if grep -q "SESSION_SECRET=" "$ENV_FILE"; then
            sed -i "s/^SESSION_SECRET=.*/SESSION_SECRET=$NEW_SECRET/" $ENV_FILE
        else
            echo "SESSION_SECRET=$NEW_SECRET" >> $ENV_FILE
        fi
        
        if systemctl is-active --quiet mivpn-web 2>/dev/null; then
            systemctl restart mivpn-web
        fi
        echo -e "${GREEN}¡Llaves criptográficas rotadas! Todos los tokens JWT anteriores son inválidos.${NC}"
    fi
    read -p "Presiona Enter para volver..."
    show_menu
}

update_panel() {
    echo -e "${CYAN}--- Actualizador de Repositorio ---${NC}"
    cd $WEB_DIR
    echo -e "${YELLOW}Sincronizando con git...${NC}"
    git pull origin main || echo -e "${RED}Advertencia: Git no detectado o repositorio no clonado vía Git.${NC}"
    npm install
    
    if systemctl is-active --quiet mivpn-web 2>/dev/null; then
        systemctl restart mivpn-web
    fi
    echo -e "${GREEN}Proceso de actualización finalizado.${NC}"
    read -p "Presiona Enter para volver..."
    show_menu
}

backup_web() {
    BACKUP_FILE="/root/mivpn_web_backup_$(date +%F_%H-%M-%S).tar.gz"
    echo -e "${CYAN}--- Sistema de Respaldos ---${NC}"
    echo -e "Creando respaldo de Base de Datos y Configuración de entorno..."
    
    # Comprimir archivos (ignorando si no existen SHM o WAL)
    tar -czvf $BACKUP_FILE -C $WEB_DIR database.sqlite database.sqlite-shm database.sqlite-wal .env 2>/dev/null
    
    echo -e "${GREEN}¡Backup guardado con éxito en: $BACKUP_FILE !${NC}"
    read -p "Presiona Enter para volver..."
    show_menu
}

restore_backup() {
    echo -e "${CYAN}--- Restauración de Base de Datos ---${NC}"
    echo -e "${YELLOW}Backups disponibles en /root/:${NC}"
    ls -lh /root/mivpn_web_backup_*.tar.gz 2>/dev/null
    echo ""
    read -p "Pega el nombre del archivo de backup exacto (ej. mivpn_web_backup_2023...tar.gz): " bkp
    
    if [ -f "/root/$bkp" ]; then
        if systemctl is-active --quiet mivpn-web 2>/dev/null; then
            systemctl stop mivpn-web
        fi
        
        tar -xzvf "/root/$bkp" -C $WEB_DIR
        
        if systemctl is-enabled --quiet mivpn-web 2>/dev/null; then
            systemctl start mivpn-web
        fi
        echo -e "${GREEN}Respaldo restaurado con éxito. Base de datos sobreescrita.${NC}"
    else
        echo -e "${RED}Archivo no encontrado en /root/$bkp${NC}"
    fi
    read -p "Presiona Enter para volver..."
    show_menu
}

# Arranque Seguro
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Por favor ejecuta este script como root (sudo).${NC}"
  exit
fi

show_menu
