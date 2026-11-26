#!/bin/bash
# =========================================================================
# JOIF Cloud v2.0 — Backup Atómico SQLite (WAL-safe) y Restauración
# =========================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../core/utils.sh" 2>/dev/null || source /root/joif-core/core/utils.sh 2>/dev/null

DB_FILE="/root/joif-core/database.sqlite"
BACKUP_DIR="/root/joif-backups"
mkdir -p "$BACKUP_DIR"

while true; do
    draw_header
    echo -e "  ${yellow}BACKUP Y RESTAURACIÓN DE CUENTAS (SQLITE WAL-SAFE)${plain}"
    ui_subline
    echo -e "  ${green}[1]${plain} Crear copia de seguridad atómica ahora"
    echo -e "  ${green}[2]${plain} Restaurar copia de seguridad"
    echo -e "  ${green}[3]${plain} Listar copias guardadas"
    echo -e "  ${red}[0]${plain} Volver"
    ui_line
    read -r -p "$(echo -e "${white}Selecciona una opción: ${plain}")" opt_bk

    case "$opt_bk" in
        1)
            if [ ! -f "$DB_FILE" ]; then
                echo -e "\n  ${red}✖ No se encontró la base de datos en ${DB_FILE}.${plain}"
                pause; continue
            fi
            DEST="${BACKUP_DIR}/backup-joif-$(date +%Y%m%d_%H%M%S).sqlite"
            if sqlite3 "$DB_FILE" ".backup '${DEST}'" 2>/dev/null; then
                chmod 600 "$DEST"
                TOTAL_USERS=$(sqlite3 "$DEST" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")
                echo -e "\n  ${green}✔ Copia de seguridad atómica creada:${plain}"
                echo -e "    • Archivo : ${yellow}${DEST}${plain}"
                echo -e "    • Cuentas : ${white}${TOTAL_USERS} usuarios${plain}"
                echo -e "    • Tamaño  : $(du -h "$DEST" | cut -f1)"
            else
                echo -e "\n  ${red}✖ Error creando backup con sqlite3 .backup.${plain}"
            fi
            pause
            ;;
        2)
            mapfile -t files < <(ls -1t "${BACKUP_DIR}"/*.sqlite 2>/dev/null)
            if [ "${#files[@]}" -eq 0 ]; then
                echo -e "\n  ${yellow}No hay respaldos en ${BACKUP_DIR}.${plain}"
                pause; continue
            fi
            echo ""
            local idx=1
            for f in "${files[@]}"; do
                echo -e "  ${green}[${idx}]${plain} $(basename "$f") ${gray}($(du -h "$f" | cut -f1))${plain}"
                ((idx++))
            done
            echo ""
            read -r -p "$(echo -e "${white}Número del archivo a restaurar (0 cancelar): ${plain}")" sel_idx
            if [[ "$sel_idx" =~ ^[0-9]+$ ]] && (( sel_idx >= 1 && sel_idx <= ${#files[@]} )); then
                TARGET_FILE="${files[$((sel_idx - 1))]}"
                read -r -p "$(echo -e "${yellow}¿Confirmas sobrescribir la base de datos actual? [s/N]: ${plain}")" confirm_r
                if [[ "$confirm_r" =~ ^[SsYy]$ ]]; then
                    systemctl stop joif 2>/dev/null || true
                    rm -f "${DB_FILE}-wal" "${DB_FILE}-shm"
                    cp -f "$TARGET_FILE" "$DB_FILE"
                    chmod 600 "$DB_FILE"
                    systemctl restart joif 2>/dev/null || true
                    echo -e "\n  ${green}✔ Base de datos restaurada con éxito.${plain}"
                else
                    echo -e "\n  ${yellow}Operación cancelada.${plain}"
                fi
            fi
            pause
            ;;
        3)
            echo -e "\n  ${yellow}Respaldos guardados:${plain}"
            ls -lh "${BACKUP_DIR}"/*.sqlite 2>/dev/null || echo "  (Ninguno)"
            pause
            ;;
        0|00) break ;;
        *) echo -e "  ${red}Opción inválida.${plain}"; sleep 1 ;;
    esac
done
