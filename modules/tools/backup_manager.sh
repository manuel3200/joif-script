#!/bin/bash
# =========================================================
# JOIF Cloud - Gestor de Backup y Restauración de Usuarios
# =========================================================

source /root/joif-core/core/utils.sh 2>/dev/null

DB_FILE="/root/joif-core/database.sqlite"
BACKUP_DIR="/root/joif-backups"
mkdir -p "$BACKUP_DIR"

while true; do
    clear
    draw_header
    echo -e "${yellow}        [ BACKUP Y RESTAURACIÓN DE CUENTAS JOIF ]${plain}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e " ${green}[1]${plain} > 💾 Crear Copia de Seguridad Actual (Backup)"
    echo -e " ${green}[2]${plain} > ♻️  Restaurar Copia de Seguridad desde Archivo"
    echo -e " ${green}[3]${plain} > 📋 Listar Copias de Seguridad Guardadas"
    echo -e " ${white}[0]${plain} > Volver"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    read -p "$(echo -e ${white}"Selecciona una opción: "${plain})" opt_bk

    case $opt_bk in
        1)
            if [ ! -f "$DB_FILE" ]; then
                echo -e "\n${red}❌ No se encontró la base de datos en $DB_FILE.${plain}"
                pause
                continue
            fi
            FILENAME="backup-joif-$(date +%Y%m%d_%H%M%S).sqlite"
            DEST="$BACKUP_DIR/$FILENAME"
            cp -f "$DB_FILE" "$DEST"
            TOTAL_USERS=$(sqlite3 "$DEST" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")
            echo -e "\n${green}✅ Copia de seguridad creada exitosamente:${plain}"
            echo -e "  • Archivo : ${yellow}$DEST${plain}"
            echo -e "  • Cuentas : ${white}$TOTAL_USERS usuarios guardados${plain}"
            echo -e "  • Tamaño  : $(du -h "$DEST" | cut -f1)"
            pause
            ;;
        2)
            echo -e "\n${yellow}Archivos disponibles en $BACKUP_DIR:${plain}"
            mapfile -t files < <(ls -1 "$BACKUP_DIR"/*.sqlite 2>/dev/null)
            if [ ${#files[@]} -eq 0 ]; then
                echo -e "${red}No hay respaldos disponibles en $BACKUP_DIR.${plain}"
                pause
                continue
            fi

            idx=1
            for f in "${files[@]}"; do
                echo -e "  ${green}[$idx]${plain} $(basename "$f") ($(du -h "$f" | cut -f1))"
                ((idx++))
            done
            echo ""
            read -p "Ingresa el número del archivo a restaurar (o 0 para cancelar): " sel_idx

            if [[ "$sel_idx" =~ ^[0-9]+$ ]] && [ "$sel_idx" -ge 1 ] && [ "$sel_idx" -le "${#files[@]}" ]; then
                TARGET_FILE="${files[$((sel_idx - 1))]}"
                read -p "¿Confirmas sobreescribir la base de datos actual con este respaldo? [s/N]: " confirm_r
                if [[ "$confirm_r" =~ ^[SsYy]$ ]]; then
                    systemctl stop joif 2>/dev/null
                    cp -f "$TARGET_FILE" "$DB_FILE"
                    systemctl restart joif 2>/dev/null
                    echo -e "\n${green}✅ ¡Base de datos restaurada con éxito!${plain}"
                else
                    echo -e "\n${yellow}Operación cancelada.${plain}"
                fi
            fi
            pause
            ;;
        3)
            echo -e "\n${yellow}Respaldos existentes:${plain}"
            ls -lh "$BACKUP_DIR"/*.sqlite 2>/dev/null || echo "Ninguno."
            pause
            ;;
        0)
            break
            ;;
        *)
            echo -e "${red}Opción inválida.${plain}"
            sleep 1
            ;;
    esac
done
