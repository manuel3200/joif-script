#!/bin/bash
# =========================================================================
# JOIF CLOUD v2.0 — Limitador Inteligente de Multilogin
# - Ventana de gracia de 1 ciclo (~10s) para cambios WiFi <-> 4G
# - Recorte quirúrgico: conserva las N sesiones más antiguas (dueño) y
#   desconecta únicamente los PIDs nuevos excedentes
# =========================================================================

DB_PATH="/root/joif-core/database.sqlite"
LOG_FILE="/var/log/joif-limitador.log"
SCAN_INTERVAL=10

if [ ! -f "$DB_PATH" ]; then
    echo "Base de datos no encontrada en ${DB_PATH}. Saliendo..."
    exit 1
fi

declare -A grace_seen

trim_log() {
    if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)" -gt 350 ]; then
        tail -n 250 "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null && mv -f "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null || true
    fi
}

while true; do
    unset conn_count
    unset user_sessions
    declare -A conn_count
    declare -A user_sessions

    # 1. Recolectar PID, propietario y antigüedad (etimes) de sesiones SSH/sshd-session/Dropbear
    while read -r pid linuxUser etimes; do
        [ -z "$pid" ] || [ -z "$linuxUser" ] && continue
        conn_count["$linuxUser"]=$(( ${conn_count["$linuxUser"]:-0} + 1 ))
        user_sessions["$linuxUser"]+="${etimes}:${pid}"$'\n'
    done < <(ps -eo pid=,user:32,etimes=,args= | awk '$2 != "root" && ($0 ~ /sshd|dropbear/) && $0 !~ /\[(priv|net|accepted)\]|listener|awk/ { print $1, $2, $3 }')

    # 2. Cargar límites en RAM en una sola lectura SQLite (O(1) lookup)
    unset db_limits
    declare -A db_limits
    while IFS='|' read -r db_uname db_hwid db_max; do
        [ -n "$db_uname" ] && [ -n "$db_max" ] && db_limits["$db_uname"]="$db_max"
        [ -n "$db_hwid" ] && [ -n "$db_max" ] && db_limits["$db_hwid"]="$db_max"
    done < <(sqlite3 -separator '|' "$DB_PATH" "SELECT username, hwid, max_connections FROM users;" 2>/dev/null)

    # 3. Limpiar usuarios en ventana de gracia que ya volvieron a su cupo o se desconectaron
    for g_user in "${!grace_seen[@]}"; do
        c_now=${conn_count["$g_user"]:-0}
        lim_now=${db_limits["$g_user"]:-0}
        if [ "$c_now" -le "$lim_now" ] || [ "$lim_now" -le 0 ]; then
            unset 'grace_seen["$g_user"]'
        fi
    done

    # 4. Evaluar excesos con ventana de gracia y recorte quirúrgico
    for l_user in "${!conn_count[@]}"; do
        c_count=${conn_count["$l_user"]}
        db_limit=${db_limits["$l_user"]:-}

        if [ -n "$db_limit" ] && [[ "$db_limit" =~ ^[0-9]+$ ]] && [ "$db_limit" -gt 0 ] && [ "$c_count" -gt "$db_limit" ]; then
            # Primera detección: otorgar ventana de gracia (~10s) para handoff WiFi <-> 4G
            if [ -z "${grace_seen["$l_user"]:-}" ]; then
                grace_seen["$l_user"]=1
                continue
            fi

            # Exceso confirmado en 2 ciclos consecutivos:
            # Ordenar de más antiguo (mayor etimes) a más nuevo (menor etimes),
            # conservar los primeros $db_limit y matar únicamente los PIDs sobrantes.
            idx=0
            killed_list=()
            while IFS=':' read -r s_etimes s_pid; do
                [ -z "$s_pid" ] && continue
                idx=$((idx + 1))
                if [ "$idx" -gt "$db_limit" ]; then
                    kill -9 "$s_pid" 2>/dev/null || true
                    killed_list+=("$s_pid")
                fi
            done < <(printf '%s' "${user_sessions["$l_user"]}" | sort -t: -k1,1nr)

            if [ "${#killed_list[@]}" -gt 0 ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') - EXCESO: ${l_user} (${c_count}/${db_limit}) -> PIDs desconectados: [${killed_list[*]}] (conservados ${db_limit} más antiguos)" >> "$LOG_FILE"
                trim_log
            fi
            unset 'grace_seen["$l_user"]'
        fi
    done

    sleep "$SCAN_INTERVAL"
done
