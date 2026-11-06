#!/bin/bash
# =========================================================
# JOIF CLOUD - Limitador de Multilogin (Auto-Killer)
# Frecuencia: 10 segundos
# =========================================================

DB_PATH="/root/joif-core/database.sqlite"

if [ ! -f "$DB_PATH" ]; then
    echo "Base de datos no encontrada. Saliendo..."
    exit 1
fi

while true; do
    unset conn_count
    declare -A conn_count
    
    # 1. Contar conexiones activas (Ignorando zombies si el keepalive hizo su trabajo)
    while read -r linuxUser etimes; do
        conn_count["$linuxUser"]=$((conn_count["$linuxUser"] + 1))
    done < <(ps -eo etimes,command | awk '/sshd:|dropbear/ && !/root/ && !/grep/ && !/\\[priv\\]/ && !/listener/ {
        user = $3
        sub(/@.*/, "", user)
        if (user != "") {
            print user, $1
        }
    }')
    
    # 2. Verificar contra la base de datos (Bulk Fetch para evitar O(n) overhead)
    unset db_limits
    declare -A db_limits
    while read -r line; do
        db_uname=$(echo "$line" | cut -d'|' -f1)
        db_hwid=$(echo "$line" | cut -d'|' -f2)
        db_max=$(echo "$line" | cut -d'|' -f3)
        if [ -n "$db_uname" ]; then db_limits["$db_uname"]=$db_max; fi
        if [ -n "$db_hwid" ]; then db_limits["$db_hwid"]=$db_max; fi
    done < <(sqlite3 -separator '|' "$DB_PATH" "SELECT username, hwid, max_connections FROM users;")

    for l_user in "${!conn_count[@]}"; do
        c_count=${conn_count[$l_user]}
        
        # Buscar límite en memoria RAM (O(1))
        db_limit=${db_limits[$l_user]}
        
        if [ -n "$db_limit" ]; then
            if [ "$c_count" -gt "$db_limit" ]; then
                # ¡EXCESO DETECTADO! 
                echo "$(date '+%Y-%m-%d %H:%M:%S') - TUMBANDO: $l_user ($c_count/$db_limit)" >> /var/log/joif-limitador.log
                
                # Asesinar procesos SSH del usuario
                pkill -u "$l_user" sshd
            fi
        fi
    done
    
    # Dormir 10 segundos antes del próximo escaneo
    sleep 10
done
