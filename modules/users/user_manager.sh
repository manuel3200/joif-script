#!/bin/bash
# =========================================================================
# JOIF Cloud v2.0 — Gestor de Usuarios (100% vía API local + UI limpia)
# =========================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../core/utils.sh" 2>/dev/null || source /root/joif-core/core/utils.sh 2>/dev/null

fmt_date_dmy() {
    local iso="$1"
    local d="${iso%%T*}"
    if [[ "$d" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
        echo "${BASH_REMATCH[3]}/${BASH_REMATCH[2]}/${BASH_REMATCH[1]}"
    else
        echo "${d:-N/A}"
    fi
}

crear_usuario() {
    ui_title "CREAR CUENTA VPN"
    echo -e "  ${green}[1]${plain} Cuenta SSH Estándar (Usuario + Contraseña)"
    echo -e "  ${green}[2]${plain} Cuenta Demo Rápida (6 horas, 2 conexiones)"
    echo -e "  ${green}[3]${plain} Cuenta HWID (HTTP Custom / JOIF App)"
    echo -e "  ${green}[4]${plain} Cuenta Token (Prefijo TKN-)"
    echo -e "  ${red}[0]${plain} Volver"
    ui_subline
    read -r -p "$(echo -e "${white}Selecciona tipo: ${plain}")" tipo
    [ "$tipo" = "0" ] || [ -z "$tipo" ] && return

    local payload="" summary_user="" summary_pass="" summary_hwid="" summary_exp="" summary_limit="1"

    case "$tipo" in
        1|4)
            read -r -p "$(echo -e "${white}Nombre de usuario: ${plain}")" u_name
            u_name=$(echo "$u_name" | tr -d '[:space:]')
            [ -z "$u_name" ] && { echo -e "${red}✖ Usuario requerido.${plain}"; sleep 1; return; }
            [ "$tipo" = "4" ] && [[ "$u_name" != TKN-* ]] && u_name="TKN-${u_name}"

            read -r -p "$(echo -e "${white}Contraseña: ${plain}")" u_pass
            [ -z "$u_pass" ] && { echo -e "${red}✖ Contraseña requerida.${plain}"; sleep 1; return; }

            read -r -p "$(echo -e "${white}Días de vigencia [30]: ${plain}")" u_days
            u_days="${u_days:-30}"
            read -r -p "$(echo -e "${white}Límite de conexiones [1]: ${plain}")" u_lim
            u_lim="${u_lim:-1}"

            local exp_iso
            exp_iso=$(date -d "+${u_days} days" --iso-8601=seconds)
            summary_exp=$(date -d "+${u_days} days" +"%d/%m/%Y")
            summary_user="$u_name"; summary_pass="$u_pass"; summary_limit="$u_lim"

            payload=$(jq -n \
                --arg username "$u_name" \
                --arg password "$u_pass" \
                --arg expiration_date "$exp_iso" \
                --argjson max_connections "$u_lim" \
                '{username:$username, password:$password, expiration_date:$expiration_date, max_connections:$max_connections}')
            ;;
        2)
            read -r -p "$(echo -e "${white}Sufijo del demo (ej. juan -> demo-juan): ${plain}")" d_suf
            d_suf=$(echo "$d_suf" | tr -d '[:space:]')
            [ -z "$d_suf" ] && d_suf="$(date +%H%M%S)"
            [[ "$d_suf" != demo-* ]] && d_suf="demo-${d_suf}"

            local d_pass exp_iso
            d_pass=$(openssl rand -hex 4 2>/dev/null || echo "demo$(date +%M%S)")
            exp_iso=$(date -d "+6 hours" --iso-8601=seconds)
            summary_exp=$(date -d "+6 hours" +"%d/%m/%Y %H:%M")
            summary_user="$d_suf"; summary_pass="$d_pass"; summary_limit="2"

            payload=$(jq -n \
                --arg username "$d_suf" \
                --arg password "$d_pass" \
                --arg expiration_date "$exp_iso" \
                '{username:$username, password:$password, expiration_date:$expiration_date, max_connections:2}')
            ;;
        3)
            read -r -p "$(echo -e "${white}Alias / Nombre del cliente: ${plain}")" c_alias
            c_alias=$(echo "$c_alias" | tr -d '\r\n')
            [ -z "$c_alias" ] && { echo -e "${red}✖ Alias requerido.${plain}"; sleep 1; return; }

            read -r -p "$(echo -e "${white}HWID del dispositivo: ${plain}")" c_hwid
            c_hwid=$(echo "$c_hwid" | tr -d '[:space:]')
            [ -z "$c_hwid" ] && { echo -e "${red}✖ HWID requerido.${plain}"; sleep 1; return; }

            read -r -p "$(echo -e "${white}Días de vigencia [30]: ${plain}")" u_days
            u_days="${u_days:-30}"
            local exp_iso
            exp_iso=$(date -d "+${u_days} days" --iso-8601=seconds)
            summary_exp=$(date -d "+${u_days} days" +"%d/%m/%Y")
            summary_user="$c_alias"; summary_hwid="$c_hwid"; summary_limit="1"

            payload=$(jq -n \
                --arg hwid "$c_hwid" \
                --arg alias "$c_alias" \
                --arg expiration_date "$exp_iso" \
                '{hwid:$hwid, alias:$alias, expiration_date:$expiration_date, max_connections:1}')
            ;;
        *)
            echo -e "${red}Opción inválida.${plain}"; sleep 1; return
            ;;
    esac

    joif_api_call "POST" "/api/users" "$payload"
    if [ "$API_HTTP_CODE" != "201" ]; then
        local err_msg
        err_msg=$(echo "$API_BODY" | jq -r '.error // empty' 2>/dev/null)
        echo -e "\n${red}✖ Error creando cuenta (HTTP ${API_HTTP_CODE}): ${err_msg:-$API_BODY}${plain}"
        pause
        return
    fi

    get_sys_info
    ui_title "CUENTA CREADA CON ÉXITO"
    echo -e "  ${gray}Host / Dominio :${plain} ${white}${DOMAIN}${plain} ${gray}(${IP})${plain}"
    echo -e "  ${gray}Cliente        :${plain} ${green}${summary_user}${plain}"
    if [ -n "$summary_hwid" ]; then
        echo -e "  ${gray}HWID           :${plain} ${cyan}${summary_hwid}${plain}"
    else
        echo -e "  ${gray}Contraseña     :${plain} ${yellow}${summary_pass}${plain}"
    fi
    echo -e "  ${gray}Límite         :${plain} ${white}${summary_limit} conexión(es)${plain}"
    echo -e "  ${gray}Válido hasta   :${plain} ${white}${summary_exp}${plain}"
    ui_subline
    echo -e "  ${gray}CheckUser URL  :${plain} ${cyan}http://${DOMAIN}/api/check/${summary_hwid:-$summary_user}${plain}"
    ui_line
    pause
}

listar_usuarios() {
    ui_title "USUARIOS REGISTRADOS"
    joif_api_call "GET" "/api/users"
    if [ "$API_HTTP_CODE" != "200" ]; then
        echo -e "  ${red}✖ No se pudo consultar la API local (HTTP ${API_HTTP_CODE}).${plain}"
        pause
        return
    fi

    local count
    count=$(echo "$API_BODY" | jq 'length' 2>/dev/null || echo 0)
    if [ "$count" -eq 0 ]; then
        echo -e "  ${yellow}No hay cuentas registradas todavía.${plain}"
        pause
        return
    fi

    printf "  ${cyan}%-3s %-15s %-11s %-7s %-10s %s${plain}\n" "#" "USUARIO" "VENCE" "CONEX" "TRÁFICO" "ESTADO"
    ui_subline

    local idx=1
    while IFS=$'\t' read -r uname ualias uexp ulim uactive ugb ustatus uhwid; do
        local label="${ualias:-$uname}"
        [ "${#label}" -gt 14 ] && label="${label:0:13}…"
        local dmy
        dmy=$(fmt_date_dmy "$uexp")
        local badge="${green}ACTIVO${plain}"
        if [ "$ustatus" = "revoked" ]; then
            badge="${red}BLOQ${plain}"
        elif [ "$ustatus" != "active" ]; then
            badge="${yellow}VENC${plain}"
        fi
        printf "  ${white}%-3s${plain} %-15s %-11s %-7s %-10s %b\n" "$idx" "$label" "$dmy" "${uactive}/${ulim}" "$ugb" "$badge"
        if [ -n "$uhwid" ] && [ "$uhwid" != "null" ]; then
            echo -e "      ${gray}└ HWID: ${uhwid}${plain}"
        fi
        ((idx++))
    done < <(echo "$API_BODY" | jq -r '.[] | [.username, (.alias // ""), .expiration_date, (.max_connections|tostring), ((.active_connections // 0)|tostring), (.gb_used // "0.00 MB"), .status, (.hwid // "")] | @tsv')

    ui_subline
    echo -e "  ${gray}Total cuentas:${plain} ${green}${count}${plain}"
    pause
}

seleccionar_usuario_desde_api() {
    SELECTED_USER=""
    SELECTED_JSON=""
    joif_api_call "GET" "/api/users"
    if [ "$API_HTTP_CODE" != "200" ]; then
        echo -e "  ${red}✖ API local no disponible (HTTP ${API_HTTP_CODE}).${plain}"
        sleep 2
        return 1
    fi
    local total
    total=$(echo "$API_BODY" | jq 'length' 2>/dev/null || echo 0)
    if [ "$total" -eq 0 ]; then
        echo -e "  ${yellow}No hay usuarios registrados.${plain}"
        sleep 2
        return 1
    fi

    local idx=1
    local -a usernames=()
    while IFS=$'\t' read -r uname ualias ustatus uhwid; do
        usernames+=("$uname")
        local tag=""
        [ -n "$uhwid" ] && [ "$uhwid" != "null" ] && tag=" ${cyan}[HWID]${plain}"
        local st="${green}[ACTIVO]${plain}"
        [ "$ustatus" = "revoked" ] && st="${red}[BLOQ]${plain}"
        [ "$ustatus" = "expired" ] && st="${yellow}[VENC]${plain}"
        printf "  ${white}[%2d]${plain} %-18s %b%b\n" "$idx" "${ualias:-$uname}" "$st" "$tag"
        ((idx++))
    done < <(echo "$API_BODY" | jq -r '.[] | [.username, (.alias // ""), .status, (.hwid // "")] | @tsv')

    ui_subline
    read -r -p "$(echo -e "${white}Número o nombre de usuario (0 para cancelar): ${plain}")" target
    [ -z "$target" ] || [ "$target" = "0" ] && return 1

    if [[ "$target" =~ ^[0-9]+$ ]] && (( target >= 1 && target <= ${#usernames[@]} )); then
        SELECTED_USER="${usernames[$((target - 1))]}"
    else
        SELECTED_USER="$target"
    fi
    SELECTED_JSON=$(echo "$API_BODY" | jq -c --arg t "$SELECTED_USER" '.[] | select(.username == $t or .alias == $t or .hwid == $t)' | head -n1)
    if [ -z "$SELECTED_JSON" ]; then
        echo -e "  ${red}✖ Usuario no encontrado: ${SELECTED_USER}${plain}"
        sleep 2
        return 1
    fi
    SELECTED_USER=$(echo "$SELECTED_JSON" | jq -r '.username')
    return 0
}

editar_renovar_usuario() {
    ui_title "EDITAR / RENOVAR USUARIO"
    seleccionar_usuario_desde_api || return

    local u_alias u_hwid u_lim u_exp
    u_alias=$(echo "$SELECTED_JSON" | jq -r '.alias // .username')
    u_hwid=$(echo "$SELECTED_JSON" | jq -r '.hwid // ""')
    u_lim=$(echo "$SELECTED_JSON" | jq -r '.max_connections')
    u_exp=$(fmt_date_dmy "$(echo "$SELECTED_JSON" | jq -r '.expiration_date')")

    ui_title "EDITANDO: ${u_alias}"
    echo -e "  ${gray}Cuenta:${plain} ${white}${SELECTED_USER}${plain}  ${gray}│  Vence:${plain} ${white}${u_exp}${plain}  ${gray}│  Límite:${plain} ${white}${u_lim}${plain}"
    ui_subline
    echo -e "  ${green}[1]${plain} Renovar (+ añadir días y reactivar si estaba vencida)"
    echo -e "  ${green}[2]${plain} Definir nuevos días desde hoy"
    echo -e "  ${green}[3]${plain} Cambiar límite de conexiones"
    if [ -n "$u_hwid" ]; then
        echo -e "  ${green}[4]${plain} Cambiar HWID del dispositivo"
    else
        echo -e "  ${green}[4]${plain} Cambiar contraseña"
    fi
    echo -e "  ${green}[5]${plain} Reiniciar contador de tráfico (0.00 MB)"
    echo -e "  ${red}[0]${plain} Volver"
    ui_subline
    read -r -p "$(echo -e "${white}Opción: ${plain}")" opt_ed

    local patch_json=""
    case "$opt_ed" in
        1)
            read -r -p "$(echo -e "${white}Días a añadir (ej. 30): ${plain}")" d_add
            [[ ! "$d_add" =~ ^[0-9]+$ ]] && return
            patch_json=$(jq -n --argjson add_days "$d_add" '{add_days:$add_days}')
            ;;
        2)
            read -r -p "$(echo -e "${white}Vigencia desde hoy en días (ej. 30): ${plain}")" d_set
            [[ ! "$d_set" =~ ^[0-9]+$ ]] && return
            patch_json=$(jq -n --argjson set_days "$d_set" '{set_days:$set_days}')
            ;;
        3)
            read -r -p "$(echo -e "${white}Nuevo límite de conexiones [1-100]: ${plain}")" n_lim
            [[ ! "$n_lim" =~ ^[0-9]+$ ]] && return
            patch_json=$(jq -n --argjson max_connections "$n_lim" '{max_connections:$max_connections}')
            ;;
        4)
            if [ -n "$u_hwid" ]; then
                read -r -p "$(echo -e "${white}Nuevo HWID: ${plain}")" n_hwid
                n_hwid=$(echo "$n_hwid" | tr -d '[:space:]')
                [ -z "$n_hwid" ] && return
                patch_json=$(jq -n --arg hwid "$n_hwid" '{hwid:$hwid}')
            else
                read -r -p "$(echo -e "${white}Nueva contraseña: ${plain}")" n_pass
                [ -z "$n_pass" ] && return
                patch_json=$(jq -n --arg password "$n_pass" '{password:$password}')
            fi
            ;;
        5)
            patch_json='{"reset_traffic":true}'
            ;;
        0|"") return ;;
        *) echo -e "${red}Opción inválida.${plain}"; sleep 1; return ;;
    esac

    joif_api_call "PATCH" "/api/users/${SELECTED_USER}" "$patch_json"
    if [ "$API_HTTP_CODE" = "200" ]; then
        echo -e "\n  ${green}✔ Cuenta actualizada correctamente.${plain}"
    else
        local err
        err=$(echo "$API_BODY" | jq -r '.error // empty' 2>/dev/null)
        echo -e "\n  ${red}✖ Error (HTTP ${API_HTTP_CODE}): ${err:-$API_BODY}${plain}"
    fi
    pause
}

bloquear_desbloquear_usuario() {
    ui_title "BLOQUEAR / DESBLOQUEAR CUENTA"
    seleccionar_usuario_desde_api || return

    local cur_status
    cur_status=$(echo "$SELECTED_JSON" | jq -r '.status')
    if [ "$cur_status" = "active" ]; then
        joif_api_call "POST" "/api/users/${SELECTED_USER}/revoke"
        if [ "$API_HTTP_CODE" = "200" ]; then
            echo -e "\n  ${yellow}✔ Cuenta ${SELECTED_USER} BLOQUEADA y sesiones cerradas.${plain}"
        else
            echo -e "\n  ${red}✖ Error bloqueando: ${API_BODY}${plain}"
        fi
    else
        joif_api_call "POST" "/api/users/${SELECTED_USER}/unlock"
        if [ "$API_HTTP_CODE" = "200" ]; then
            echo -e "\n  ${green}✔ Cuenta ${SELECTED_USER} DESBLOQUEADA y reactivada.${plain}"
        else
            local err
            err=$(echo "$API_BODY" | jq -r '.error // empty' 2>/dev/null)
            echo -e "\n  ${red}✖ ${err:-$API_BODY}${plain}"
        fi
    fi
    pause
}

eliminar_usuario() {
    ui_title "ELIMINAR USUARIOS"
    echo -e "  ${green}[1]${plain} Eliminar 1 usuario"
    echo -e "  ${green}[2]${plain} Eliminar solo usuarios vencidos"
    echo -e "  ${red}[3]${plain} Eliminar TODOS los usuarios (requiere confirmación)"
    echo -e "  ${white}[0]${plain} Volver"
    ui_subline
    read -r -p "$(echo -e "${white}Opción: ${plain}")" opt_del

    case "$opt_del" in
        1)
            ui_title "SELECCIONAR USUARIO A ELIMINAR"
            seleccionar_usuario_desde_api || return
            read -r -p "$(echo -e "${yellow}¿Eliminar permanentemente '${SELECTED_USER}'? [s/N]: ${plain}")" conf
            if [[ "$conf" =~ ^[SsYy]$ ]]; then
                joif_api_call "DELETE" "/api/users/${SELECTED_USER}"
                if [ "$API_HTTP_CODE" = "200" ]; then
                    echo -e "  ${green}✔ Usuario ${SELECTED_USER} eliminado del sistema y de la BD.${plain}"
                else
                    echo -e "  ${red}✖ Error (HTTP ${API_HTTP_CODE}): ${API_BODY}${plain}"
                fi
            fi
            pause
            ;;
        2)
            joif_api_call "GET" "/api/users"
            local now_sec removed=0
            now_sec=$(date +%s)
            while IFS=$'\t' read -r uname uexp; do
                local exp_sec
                exp_sec=$(date -d "$uexp" +%s 2>/dev/null || echo 0)
                if (( exp_sec > 0 && exp_sec <= now_sec )); then
                    joif_api_call "DELETE" "/api/users/${uname}"
                    if [ "$API_HTTP_CODE" = "200" ]; then
                        echo -e "  ${yellow}• Eliminado vencido:${plain} ${uname}"
                        ((removed++))
                    fi
                fi
            done < <(echo "$API_BODY" | jq -r '.[] | [.username, .expiration_date] | @tsv')
            echo -e "\n  ${green}✔ Limpieza completada (${removed} cuentas vencidas eliminadas).${plain}"
            pause
            ;;
        3)
            read -r -p "$(echo -e "${red}Escribe BORRAR para eliminar TODAS las cuentas: ${plain}")" conf_all
            if [ "$conf_all" = "BORRAR" ]; then
                joif_api_call "DELETE" "/api/users"
                echo -e "  ${green}✔ Todas las cuentas han sido eliminadas.${plain}"
            else
                echo -e "  ${yellow}Operación cancelada.${plain}"
            fi
            pause
            ;;
    esac
}

monitor_conectados() {
    ui_title "MONITOR DE USUARIOS CONECTADOS"
    joif_api_call "GET" "/api/users"
    if [ "$API_HTTP_CODE" != "200" ]; then
        echo -e "  ${red}✖ No se pudo consultar la API local.${plain}"
        pause
        return
    fi

    printf "  ${cyan}%-18s %-10s %-11s %s${plain}\n" "USUARIO" "CONEX" "TIEMPO" "CONSUMO"
    ui_subline

    local total_online=0
    while IFS=$'\t' read -r uname ualias uactive ulim utime ugb; do
        local label="${ualias:-$uname}"
        [ "${#label}" -gt 17 ] && label="${label:0:16}…"
        local c_col="$green"
        (( uactive > ulim )) && c_col="$red"
        printf "  ${white}%-18s${plain} ${c_col}%-10s${plain} %-11s %s\n" "$label" "${uactive}/${ulim}" "$utime" "$ugb"
        ((total_online++))
    done < <(echo "$API_BODY" | jq -r '.[] | select((.active_connections // 0) > 0) | [.username, (.alias // ""), ((.active_connections // 0)|tostring), (.max_connections|tostring), (.time_online // "00:00:00"), (.gb_used // "0.00 MB")] | @tsv')

    if [ "$total_online" -eq 0 ]; then
        echo -e "  ${gray}No hay clientes conectados en este instante.${plain}"
    fi
    ui_subline
    echo -e "  ${gray}Cuentas en línea:${plain} ${green}${total_online}${plain}"
    pause
}

gestionar_banner_estatico() {
    ui_title "BANNER SSH ESTÁTICO (/etc/issue.net)"
    local state="${red}[OFF]${plain}"
    grep -qE '^Banner\s+/etc/issue\.net' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null && state="${green}[ON]${plain}"
    echo -e "  Estado actual: ${state}"
    echo -e "  ${gray}(Los datos de cada cuenta se sirven en vivo vía API CheckUser)${plain}"
    ui_subline
    echo -e "  ${green}[1]${plain} Editar / Activar Banner SSH (nano /etc/issue.net)"
    echo -e "  ${red}[2]${plain} Desactivar y eliminar Banner SSH"
    echo -e "  ${white}[0]${plain} Volver"
    ui_subline
    read -r -p "$(echo -e "${white}Opción: ${plain}")" b_opt

    case "$b_opt" in
        1)
            [ -f /etc/issue.net ] && cp -a /etc/issue.net /etc/issue.net.bak
            touch /etc/issue.net
            nano /etc/issue.net
            mkdir -p /etc/ssh/sshd_config.d
            echo "Banner /etc/issue.net" > /etc/ssh/sshd_config.d/95-joif-banner.conf
            if safe_reload_ssh; then
                echo -e "  ${green}✔ Banner estático validado (sshd -t) y aplicado.${plain}"
            else
                rm -f /etc/ssh/sshd_config.d/95-joif-banner.conf
                echo -e "  ${yellow}⚠ Rollback aplicado para proteger SSH.${plain}"
            fi
            pause
            ;;
        2)
            rm -f /etc/ssh/sshd_config.d/95-joif-banner.conf
            sed -i '/^Banner /d' /etc/ssh/sshd_config 2>/dev/null || true
            if safe_reload_ssh; then
                echo -e "  ${green}✔ Banner SSH desactivado correctamente.${plain}"
            fi
            pause
            ;;
    esac
}

gestionar_multilogin() {
    while true; do
        local st="${red}[OFF]${plain}"
        systemctl is-active --quiet joif-limitador 2>/dev/null && st="${green}[ON]${plain}"
        ui_title "CONTROL MULTILOGIN (AUTO-KILLER) ${st}"
        echo -e "  ${green}[1]${plain} Iniciar Auto-Killer (revisa cada 10s)"
        echo -e "  ${red}[2]${plain} Detener Auto-Killer"
        echo -e "  ${cyan}[3]${plain} Ver últimas 20 desconexiones (log)"
        echo -e "  ${white}[0]${plain} Volver"
        ui_subline
        read -r -p "$(echo -e "${white}Opción: ${plain}")" opt_k
        case "$opt_k" in
            1)
                cat << 'EOF' > /etc/systemd/system/joif-limitador.service
[Unit]
Description=JOIF Cloud Multilogin Killer
After=network.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash /root/joif-core/limitador.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
                systemctl daemon-reload
                systemctl enable joif-limitador >/dev/null 2>&1
                systemctl restart joif-limitador
                echo -e "  ${green}✔ Auto-Killer iniciado.${plain}"
                sleep 1
                ;;
            2)
                systemctl stop joif-limitador 2>/dev/null || true
                systemctl disable joif-limitador 2>/dev/null || true
                echo -e "  ${yellow}✔ Auto-Killer detenido.${plain}"
                sleep 1
                ;;
            3)
                ui_title "REGISTRO MULTILOGIN"
                if [ -f /var/log/joif-limitador.log ]; then
                    tail -n 20 /var/log/joif-limitador.log
                else
                    echo -e "  ${gray}Sin registros todavía.${plain}"
                fi
                pause
                ;;
            0|"") break ;;
        esac
    done
}

gestionar_checkuser_y_seguridad() {
    while true; do
        local cur_port cur_st="${red}[OFF]${plain}"
        cur_port=$(get_api_port)
        systemctl is-active --quiet joif 2>/dev/null && cur_st="${green}[ON:${cur_port}]${plain}"
        ui_title "API CHECKUSER & PANEL WEB ${cur_st}"
        echo -e "  ${green}[1]${plain} Configurar puerto y reiniciar servicio joif.service"
        echo -e "  ${green}[2]${plain} Ver enlaces CheckUser y Panel Web"
        echo -e "  ${yellow}[3]${plain} Rotar SESSION_SECRET (cerrar todas las sesiones web)"
        echo -e "  ${yellow}[4]${plain} Rotar API_KEY del nodo (requiere actualizar Portal Central)"
        echo -e "  ${white}[0]${plain} Volver"
        ui_subline
        read -r -p "$(echo -e "${white}Opción: ${plain}")" opt_cu

        case "$opt_cu" in
            1)
                read -r -p "$(echo -e "${white}Puerto [3000-3500] (${cur_port}): ${plain}")" port_input
                port_input="${port_input:-$cur_port}"
                if [[ ! "$port_input" =~ ^[0-9]+$ ]] || (( port_input < 3000 || port_input > 3500 )); then
                    echo -e "  ${red}✖ El puerto debe estar entre 3000 y 3500.${plain}"; sleep 2; continue
                fi

                mkdir -p "$JOIF_DIR"
                if [ ! -f "$JOIF_ENV" ]; then
                    local new_key
                    new_key=$(generate_random_api_key)
                    cat << EOF > "$JOIF_ENV"
PORT=${port_input}
API_KEY=${new_key}
NODE_API_SECRET=${new_key}
EOF
                elif grep -q '^PORT=' "$JOIF_ENV"; then
                    sed -i "s/^PORT=.*/PORT=${port_input}/" "$JOIF_ENV"
                else
                    echo "PORT=${port_input}" >> "$JOIF_ENV"
                fi
                chmod 600 "$JOIF_ENV"

                if systemctl list-unit-files 2>/dev/null | grep -q '^joif-api\.service'; then
                    systemctl stop joif-api 2>/dev/null || true
                    systemctl disable joif-api 2>/dev/null || true
                    rm -f /etc/systemd/system/joif-api.service
                fi

                local node_bin
                node_bin=$(command -v node 2>/dev/null || echo "/usr/bin/node")
                cat << EOF > /etc/systemd/system/joif.service
[Unit]
Description=JOIF Web Panel and CheckUser API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${JOIF_DIR}
Environment=PORT=${port_input}
ExecStart=${node_bin} server.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
                systemctl daemon-reload
                systemctl enable joif >/dev/null 2>&1
                systemctl restart joif
                ensure_firewall_port "$port_input" "tcp"
                persist_firewall

                local ok=0
                for _ in 1 2 3 4 5; do
                    curl -fsS --max-time 2 "http://127.0.0.1:${port_input}/health" >/dev/null 2>&1 && { ok=1; break; }
                    sleep 1
                done
                if [ "$ok" -eq 1 ]; then
                    echo -e "  ${green}✔ API CheckUser activa y verificada en puerto ${port_input}.${plain}"
                else
                    echo -e "  ${red}✖ joif.service no respondió en /health. Revisa: journalctl -u joif -n 30${plain}"
                fi
                pause
                ;;
            2)
                get_sys_info
                echo -e "\n  ${yellow}Enlaces CheckUser:${plain}"
                echo -e "  • Directo  : ${green}http://${DOMAIN}:${cur_port}/api/check/[usuario]${plain}"
                echo -e "  • Universal: ${green}http://${DOMAIN}:${cur_port}/checkUser${plain}"
                echo -e "  • Proxy 80 : ${green}http://${DOMAIN}/api/check/[usuario]${plain}"
                echo -e "\n  ${yellow}Panel Web Admin:${plain}"
                echo -e "  • URL      : ${cyan}http://${DOMAIN}:${cur_port}/${plain}"
                pause
                ;;
            3)
                rm -f "${JOIF_DIR}/.session-secret"
                systemctl restart joif 2>/dev/null || true
                echo -e "  ${green}✔ Clave JWT rotada. Todas las sesiones web previas expiraron.${plain}"
                pause
                ;;
            4)
                local rk
                rk=$(generate_random_api_key)
                touch "$JOIF_ENV"
                sed -i '/^API_KEY=/d;/^NODE_API_SECRET=/d' "$JOIF_ENV"
                { echo "API_KEY=${rk}"; echo "NODE_API_SECRET=${rk}"; } >> "$JOIF_ENV"
                chmod 600 "$JOIF_ENV"
                systemctl restart joif 2>/dev/null || true
                echo -e "  ${green}✔ Nueva API_KEY generada:${plain} ${yellow}${rk}${plain}"
                pause
                ;;
            0|"") break ;;
        esac
    done
}

# Bucle principal del Módulo de Usuarios
while true; do
    draw_header
    local_port=$(get_api_port)
    cu_badge="${red}[OFF]${plain}"
    systemctl is-active --quiet joif 2>/dev/null && cu_badge="${green}[ON:${local_port}]${plain}"
    ml_badge="${red}[OFF]${plain}"
    systemctl is-active --quiet joif-limitador 2>/dev/null && ml_badge="${green}[ON]${plain}"

    echo -e "  ${yellow}GESTIÓN DE USUARIOS (SSH / HWID / CHECKUSER)${plain}"
    ui_subline
    echo -e "  ${green}[1]${plain} Crear usuario (SSH / Demo / HWID / Token)"
    echo -e "  ${green}[2]${plain} Listar usuarios registrados (con tráfico MB/GB)"
    echo -e "  ${green}[3]${plain} Editar / Renovar / Cambiar clave o HWID"
    echo -e "  ${green}[4]${plain} Bloquear / Desbloquear usuario"
    echo -e "  ${green}[5]${plain} Eliminar usuario(s)"
    echo -e "  ${green}[6]${plain} Monitor de usuarios conectados en vivo"
    echo -e "  ${green}[7]${plain} Banner SSH estático (/etc/issue.net)"
    echo -e "  ${green}[8]${plain} Control Multilogin Auto-Killer      ${ml_badge}"
    echo -e "  ${green}[9]${plain} API CheckUser y Seguridad Web       ${cu_badge}"
    echo -e "  ${red}[0]${plain} Volver al menú principal"
    ui_line
    read -r -p "$(echo -e "${white}Selecciona una opción: ${plain}")" opt_u

    case "$opt_u" in
        1) crear_usuario ;;
        2) listar_usuarios ;;
        3) editar_renovar_usuario ;;
        4) bloquear_desbloquear_usuario ;;
        5) eliminar_usuario ;;
        6) monitor_conectados ;;
        7) gestionar_banner_estatico ;;
        8) gestionar_multilogin ;;
        9) gestionar_checkuser_y_seguridad ;;
        0|00) break ;;
        *) echo -e "  ${red}Opción inválida.${plain}"; sleep 1 ;;
    esac
done
