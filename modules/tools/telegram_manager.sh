#!/bin/bash
# =========================================================================
# JOIF Cloud v2.0 — Gestor del Bot de Telegram [Modo Alfa]
# =========================================================================

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "${SCRIPT_DIR}/../../core/utils.sh" 2>/dev/null || source /root/joif-core/core/utils.sh 2>/dev/null

ENV_FILE="/root/joif-core/.env"
TG_SVC="/etc/systemd/system/joif-telegram.service"

set_env_tg() {
    local key="$1" val="$2"
    touch "$ENV_FILE"
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
    else
        echo "${key}=${val}" >> "$ENV_FILE"
    fi
    chmod 600 "$ENV_FILE" 2>/dev/null || true
}

activar_bot() {
    ui_title "ACTIVAR BOT DE TELEGRAM [MODO ALFA]"
    echo -e "  ${gray}1. Crea tu bot en @BotFather y copia el Token.${plain}"
    echo -e "  ${gray}2. Obtén tu ID numérico en @userinfobot.${plain}\n"

    local cur_token cur_admin
    cur_token=$(grep -m1 '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r\n')
    cur_admin=$(grep -m1 '^TELEGRAM_ADMIN_ID=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r\n')

    read -r -p "$(echo -e "  ${green}► TELEGRAM_BOT_TOKEN [${cur_token:+configurado}]: ${plain}")" in_token
    in_token="${in_token:-$cur_token}"
    read -r -p "$(echo -e "  ${green}► TELEGRAM_ADMIN_ID [${cur_admin:-tu_id}]: ${plain}")" in_admin
    in_admin="${in_admin:-$cur_admin}"

    in_token=$(echo "$in_token" | tr -d '[:space:]')
    in_admin=$(echo "$in_admin" | tr -d '[:space:]')

    if [ -z "$in_token" ] || [ -z "$in_admin" ]; then
        echo -e "\n  ${red}✖ Debes ingresar tanto el TOKEN como tu ADMIN_ID.${plain}"
        pause; return
    fi

    set_env_tg "TELEGRAM_BOT_TOKEN" "$in_token"
    set_env_tg "TELEGRAM_ADMIN_ID" "$in_admin"

    local node_bin
    node_bin=$(command -v node 2>/dev/null || echo "/usr/bin/node")

    cat << EOF > "$TG_SVC"
[Unit]
Description=JOIF Cloud Telegram Admin Bot (Alpha)
After=network-online.target joif.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/joif-core
ExecStart=${node_bin} /root/joif-core/telegram-bot.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable joif-telegram >/dev/null 2>&1
    systemctl restart joif-telegram
    sleep 2

    if systemctl is-active --quiet joif-telegram 2>/dev/null; then
        echo -e "\n  ${green}✔ Bot de Telegram [Alfa] ACTIVO. Revisa tu chat de Telegram.${plain}"
    else
        echo -e "\n  ${red}✖ El bot no pudo iniciar. Revisa los logs:${plain}"
        journalctl -u joif-telegram -n 10 --no-pager 2>/dev/null
    fi
    pause
}

desactivar_bot() {
    systemctl stop joif-telegram 2>/dev/null || true
    systemctl disable joif-telegram 2>/dev/null || true
    echo -e "\n  ${yellow}● Bot de Telegram detenido y desactivado.${plain}"
    pause
}

while true; do
    draw_header
    tg_st="${red}[OFF]${plain}"
    systemctl is-active --quiet joif-telegram 2>/dev/null && tg_st="${green}[ON]${plain}"
    echo -e "  ${yellow}BOT DE ADMINISTRACIÓN Y ALERTAS TELEGRAM [ALFA]${plain}"
    echo -e "  ${white}Estado actual: ${tg_st}"
    ui_subline
    echo -e "  ${green}[1]${plain} Activar / Configurar Token y Admin ID"
    echo -e "  ${red}[2]${plain} Desactivar Bot de Telegram"
    echo -e "  ${cyan}[3]${plain} Ver últimos logs del Bot"
    echo -e "  ${white}[0]${plain} Volver"
    ui_line
    read -r -p "$(echo -e "${white}Selecciona una opción: ${plain}")" opt_tg

    case "$opt_tg" in
        1) activar_bot ;;
        2) desactivar_bot ;;
        3)
            ui_title "LOGS DEL BOT DE TELEGRAM"
            journalctl -u joif-telegram -n 25 --no-pager 2>/dev/null || echo "  Sin registros."
            pause
            ;;
        0|00|"") break ;;
        *) echo -e "  ${red}Opción inválida.${plain}"; sleep 1 ;;
    esac
done
