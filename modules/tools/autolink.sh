#!/bin/bash
# =========================================================================
# JOIF Cloud v2.0 — Vinculación Segura con Portal Web (Auto-Link)
# =========================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../core/utils.sh" 2>/dev/null || source /root/joif-core/core/utils.sh 2>/dev/null

ejecutar_autolink() {
    local portal_arg="${1:-}"
    local token_arg="${2:-}"
    local name_arg="${3:-}"
    local force_cli="${4:-}"
    local is_cli=0
    if [ "$force_cli" = "cli" ] || [ -n "$token_arg" ]; then
        is_cli=1
    fi

    if [ "$is_cli" -eq 0 ]; then
        ui_title "AUTOCONFIGURACIÓN Y VINCULACIÓN (AUTO-LINK)"
        echo -e "  ${white}Prepara este VPS para recibir cuentas desde tu Portal Web.${plain}"
        echo -e "  ${gray}1. Configura OpenSSH (/bin/false + PasswordAuth + sshd -t)${plain}"
        echo -e "  ${gray}2. Asegura puertos en firewall (22, 80, 443, API, 7300)${plain}"
        echo -e "  ${gray}3. Garantiza API_KEY única y servicio joif.service activo${plain}"
        echo -e "  ${gray}4. Registra el nodo en tu portal vía JSON seguro (jq)${plain}"
        ui_subline
        read -r -p "$(echo -e "${yellow}¿Iniciar autoconfiguración ahora? [S/n]: ${plain}")" start_ans
        [[ "$start_ans" =~ ^[Nn]$ ]] && return 0
    fi

    echo -e "\n${blue}[1/5] Detectando IP pública y geolocalización (HTTPS)...${plain}"
    local ip_detectada dominio_default
    ip_detectada=$(get_cached_public_ip)
    dominio_default=$(cat /root/.JOIF_domain 2>/dev/null | tr -d '\r\n ')
    [ -z "$dominio_default" ] && dominio_default="$ip_detectada"

    local geo_json auto_code auto_country auto_flag="🌐"
    geo_json=$(curl -fsS --connect-timeout 4 --max-time 6 "https://ipwho.is/${ip_detectada}" 2>/dev/null || echo "{}")
    auto_code=$(echo "$geo_json" | jq -r '.country_code // "US"' 2>/dev/null || echo "US")
    auto_country=$(echo "$geo_json" | jq -r '.country // "Estados Unidos"' 2>/dev/null || echo "Estados Unidos")
    if command -v node >/dev/null 2>&1; then
        auto_flag=$(node -e "const c=process.argv[1].toUpperCase(); console.log(c.length===2 ? String.fromCodePoint(...[...c].map(x=>0x1F1E6+x.charCodeAt(0)-65)) : '🌐');" "$auto_code" 2>/dev/null || echo "🌐")
    fi

    echo -e "  • IP Pública : ${green}${ip_detectada}${plain}"
    echo -e "  • Ubicación  : ${green}${auto_flag} ${auto_country} (${auto_code})${plain}"

    local dominio_final="$dominio_default"
    if [ "$is_cli" -eq 0 ]; then
        read -r -p "$(echo -e "${white}  Dominio o Host [${dominio_default}]: ${plain}")" dom_in
        [ -n "$dom_in" ] && dominio_final="$dom_in"
    fi
    echo "$dominio_final" > /root/.JOIF_domain 2>/dev/null || true

    echo -e "\n${blue}[2/5] Verificando OpenSSH de forma segura (sshd -t)...${plain}"
    [ -f /etc/shells ] && { grep -qxF '/bin/false' /etc/shells 2>/dev/null || echo '/bin/false' >> /etc/shells; }
    if [ -d /etc/ssh ]; then
        mkdir -p /etc/ssh/sshd_config.d
        cat << 'EOF' > /etc/ssh/sshd_config.d/01-password-auth.conf
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PermitEmptyPasswords no
EOF
        safe_reload_ssh && echo -e "  ${green}✔ OpenSSH validado y recargado.${plain}"
    fi

    local api_port
    api_port=$(get_api_port)
    echo -e "\n${blue}[3/5] Asegurando reglas de Firewall (idempotentes)...${plain}"
    for p in 22 80 443 "$api_port" 7300; do
        ensure_firewall_port "$p" "tcp"
    done
    ensure_firewall_port 7300 "udp"
    ensure_firewall_port 7200 "udp"
    persist_firewall
    echo -e "  ${green}✔ Puertos 22, 80, 443, ${api_port} y 7300/7200 habilitados.${plain}"

    echo -e "\n${blue}[4/5] Verificando API_KEY y salud de joif.service...${plain}"
    mkdir -p "$JOIF_DIR"
    if [ ! -f "$JOIF_ENV" ]; then
        local gen_key
        gen_key=$(generate_random_api_key)
        cat << EOF > "$JOIF_ENV"
PORT=${api_port}
API_KEY=${gen_key}
NODE_API_SECRET=${gen_key}
EOF
    fi
    chmod 600 "$JOIF_ENV"
    local api_key_local
    api_key_local=$(get_api_key)
    if [ -z "$api_key_local" ]; then
        api_key_local=$(generate_random_api_key)
        { echo "API_KEY=${api_key_local}"; echo "NODE_API_SECRET=${api_key_local}"; } >> "$JOIF_ENV"
    fi

    systemctl restart joif 2>/dev/null || true
    sleep 1
    if curl -fsS --max-time 3 "http://127.0.0.1:${api_port}/health" >/dev/null 2>&1; then
        echo -e "  ${green}✔ API local saludable en puerto ${api_port} (/health OK).${plain}"
    else
        echo -e "  ${yellow}⚠ API local no respondió en /health; revisa journalctl -u joif.${plain}"
    fi

    echo -e "\n${blue}[5/5] Registro contra el Portal Web...${plain}"
    local portal_url="${portal_arg:-https://shop.joif.net}"
    local portal_key="$token_arg"
    local vps_id="vps-$(echo "$ip_detectada" | tr '.' '-')"
    local vps_name="${name_arg:-Nodo ${auto_country} (${ip_detectada})}"
    local vps_code="$auto_code" vps_country="$auto_country" vps_flag="$auto_flag" vps_limit=100

    if [ "$is_cli" -eq 0 ]; then
        read -r -p "$(echo -e "${white}  URL del Portal [${portal_url}]: ${plain}")" in_url
        [ -n "$in_url" ] && portal_url="$in_url"
        read -r -p "$(echo -e "${white}  Token de Vinculación (joif_live_...): ${plain}")" portal_key
        read -r -p "$(echo -e "${white}  ID único del VPS [${vps_id}]: ${plain}")" in_id
        [ -n "$in_id" ] && vps_id="$in_id"
        read -r -p "$(echo -e "${white}  Nombre a mostrar [${vps_name}]: ${plain}")" in_name
        [ -n "$in_name" ] && vps_name="$in_name"
        read -r -p "$(echo -e "${white}  Capacidad máxima de usuarios [100]: ${plain}")" in_lim
        [[ "$in_lim" =~ ^[0-9]+$ ]] && vps_limit="$in_lim"
    fi

    portal_url="${portal_url%/}"
    if [ -z "$portal_key" ]; then
        echo -e "  ${red}✖ Token de vinculación requerido (sin valor por defecto inseguro).${plain}"
        [ "$is_cli" -eq 0 ] && pause
        return 1
    fi

    local payload
    payload=$(jq -n \
        --arg id "$vps_id" \
        --arg name "$vps_name" \
        --arg country_code "$vps_code" \
        --arg country_name "$vps_country" \
        --arg flag "$vps_flag" \
        --arg domain "$dominio_final" \
        --arg ip "$ip_detectada" \
        --arg api_url "http://${ip_detectada}:${api_port}" \
        --arg api_secret "$api_key_local" \
        --argjson lim "$vps_limit" \
        '{
          id:$id, name:$name, country_code:$country_code, country_name:$country_name,
          flag:$flag, domain:$domain, ip:$ip, ssh_port:22, proxy_port:80, ssl_port:443,
          udpgw_port:7300, api_url:$api_url, api_secret:$api_secret,
          daily_limit:$lim, capacidadMaxima:$lim, capacidad_maxima:$lim, max_users:$lim, is_active:1
        }')

    local reg_resp
    reg_resp=$(curl -sS --connect-timeout 8 --max-time 15 -X POST "${portal_url}/api/admin/servers" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${portal_key}" \
        -H "x-api-key: ${portal_key}" \
        -d "$payload" 2>/dev/null || echo '{"error":"Error de conexión con el portal"}')

    echo ""
    if echo "$reg_resp" | grep -qE '"success":\s*true|"ok":\s*true'; then
        echo -e "  ${green}✔ VPS vinculado exitosamente en ${portal_url}/admin${plain}"
        [ "$is_cli" -eq 0 ] && pause
        return 0
    else
        echo -e "  ${red}✖ Error al vincular:${plain} ${yellow}${reg_resp}${plain}"
        [ "$is_cli" -eq 0 ] && pause
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ejecutar_autolink "$@"
fi
