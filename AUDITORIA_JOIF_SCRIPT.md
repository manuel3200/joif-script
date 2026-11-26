# Auditoría Integral y Plan de Refactorización — `joif-script` (`edge-node-manager`)

**Fecha de auditoría:** 2026-11-26  
**Repositorio auditado:** `F:\mivpnv2.0\edge-node-manager` (`https://github.com/manuel3200/joif-script`)  
**Alcance:** Revisión completa (100% de archivos) cubriendo Seguridad, Bugs Funcionales / Ubuntu 26.04 LTS, Arquitectura y Deuda Técnica, Rendimiento, y Diseño Visual / UX (Consola CLI + Panel Web).

---

## Resumen Ejecutivo

`joif-script` ya cuenta con una base funcional sólida en sus módulos más recientes (`proxy.js`, `smartdns_client.sh`, `network_tuning.sh`, `joif.js` y el motor CheckUser con conteo de tráfico `/proc/<pid>/io`). Sin embargo, la evolución orgánica del proyecto dejó **vulnerabilidades críticas de seguridad**, **bugs silenciosos en `menu.sh`**, **dos fuentes de verdad compitiendo sobre SQLite y Linux**, y **tres identidades visuales distintas** mezcladas entre la terminal y el panel web.

| Categoría | Críticos (`P0`) | Altos (`P1`) | Medios / Deuda (`P2`) | Visual / UX (`P3`) |
| :--- | :---: | :---: | :---: | :---: |
| **Seguridad** | 2 | 4 | 2 | — |
| **Confiabilidad / Bugs** | 3 | 5 | 3 | — |
| **Arquitectura y Código** | — | 2 | 6 | — |
| **Interfaz CLI + Web** | — | 2 | — | 8 |

---

## 1. Auditoría de Seguridad (`P0` y `P1`)

### 🔴 [P0-SEC-01] Clave maestra fija y pública (`API_KEY=joif2026`) con API expuesta a Internet
- **Ubicación:** [setup](file:///F:/mivpnv2.0/edge-node-manager/setup#L184-L191), [menu.sh](file:///F:/mivpnv2.0/edge-node-manager/menu.sh#L26-L27), [menu.sh](file:///F:/mivpnv2.0/edge-node-manager/menu.sh#L1217-L1224), [menu.sh](file:///F:/mivpnv2.0/edge-node-manager/menu.sh#L1391-L1393).
- **Problema:** Todos los servidores instalan por defecto `API_KEY=joif2026` y `NODE_API_SECRET=joif2026`, valor visible públicamente en el repositorio de GitHub. Como `setup` abre el puerto `3000` en el firewall y `proxy.js` reenvía `/api/*` por el puerto `80`, **cualquier persona en internet puede enviar el header `x-api-key: joif2026` a `http://<IP_VPS>/api/users` para listar usuarios, crear cuentas SSH o ejecutar `DELETE /api/users` y borrar todas las cuentas del VPS**.
- **Además:** En [menu.sh](file:///F:/mivpnv2.0/edge-node-manager/menu.sh#L1248) existe un fallback `portal_key="${input_token:-Admin12345!}"`.
- **Solución:** Generar `API_KEY` aleatoria criptográficamente (`openssl rand -hex 24`) durante `setup` si no existe, eliminar el fallback `joif2026` del código y exigir token real en Auto-Link.

### 🔴 [P0-SEC-02] Inyección SQL, JSON y Python en scripts Bash
- **Ubicación:**
  - **SQL Injection:** [menu.sh](file:///F:/mivpnv2.0/edge-node-manager/menu.sh#L300) (`WHERE username='$l_user'`), líneas `543`, `578`, `620`, `661`, `681`, `819`, `876`; y [mivpn_web.sh](file:///F:/mivpnv2.0/edge-node-manager/mivpn_web.sh#L119-L120).
  - **JSON Injection:** [menu.sh](file:///F:/mivpnv2.0/edge-node-manager/menu.sh#L98), línea `165` y líneas `1295–1314` (interpola variables directo en strings JSON para `curl`; una comilla `"` o `\` rompe o altera el payload).
  - **Python Code Injection:** [protocol_manager.sh](file:///F:/mivpnv2.0/edge-node-manager/modules/network/protocol_manager.sh#L158-L179) y líneas `219–236` (interpola `$u_alias`, `$final_uid` y `$del_num` directo dentro de código fuente `python3 -c "..."` en vez de pasarlos como argumentos `sys.argv`).
- **Solución:** Canalizar toda escritura de usuarios por la API local de Node.js (que usa consultas parametrizadas `?`), construir JSON con `jq -n --arg ...`, y pasar argumentos a Python mediante `sys.argv`.

### 🟠 [P1-SEC-03] Endpoint público de enumeración masiva de usuarios (`GET /check`)
- **Ubicación:** [server.js](file:///F:/mivpnv2.0/edge-node-manager/server.js#L196-L204).
- **Problema:** `GET /check` y `GET /api/check` son públicos sin autenticación y devuelven el array completo con todos los `username` activos del VPS (incluyendo HWIDs).
- **Solución:** Proteger `/check` global con `authMiddleware` (dejando público únicamente `/check/:id` y `/checkUser` para consulta individual) o deshabilitarlo si ninguna app cliente lo requiere.

### 🟠 [P1-SEC-04] Sin Rate-Limiting en Login Web ni en CheckUser
- **Ubicación:** [server.js](file:///F:/mivpnv2.0/edge-node-manager/server.js#L50-L72) y líneas `216–285`.
- **Problema:** `POST /api/auth/login` permite intentos ilimitados de fuerza bruta por segundo; `/check/:id` permite escaneo masivo de nombres de usuario sin límite por IP.
- **Solución:** Añadir un limitador ligero en memoria por IP (ej. máx. 5 intentos fallidos de login cada 15 min, y 60 req/min en CheckUser, considerando `127.0.0.1` cuando pasa por `proxy.js` o inyectando `X-Forwarded-For` desde `proxy.js`).

### 🟠 [P1-SEC-05] Permisos de archivos sensibles y contraseñas en texto plano
- **Ubicación:** [db.js](file:///F:/mivpnv2.0/edge-node-manager/db.js#L8), [protocol_manager.sh](file:///F:/mivpnv2.0/edge-node-manager/modules/network/protocol_manager.sh#L421), [mivpn_web.sh](file:///F:/mivpnv2.0/edge-node-manager/mivpn_web.sh#L120).
- **Problema:**
  - `database.sqlite` y `.env` no fuerzan `chmod 600`.
  - `protocol_manager.sh` ejecuta `chmod -R 777 /var/log/xray`.
  - `mivpn_web.sh` guarda `admin_pass` en texto plano al restablecer credenciales (sin hash `scrypt$`).
- **Solución:** Aplicar `0600` a `database.sqlite*` y `.env`, `0750` a `/var/log/xray`, y hashear siempre `admin_pass` con `backend-security.js`.

### 🟡 [P2-SEC-06] Consulta HTTP sin cifrar a API externa y archivos temporales predecibles
- **Ubicación:** [menu.sh](file:///F:/mivpnv2.0/edge-node-manager/menu.sh#L788-L802) (`/tmp/active_users.txt`, `/tmp/banned_users.txt`) y línea `1135` (`http://ip-api.com/json/...`).
- **Solución:** Usar `mktemp` (o arrays en memoria sin archivos `/tmp`) y un endpoint HTTPS para geolocalización (`https://ipwho.is/` o `https://ipapi.co/json/`).

---

## 2. Auditoría de Bugs Funcionales y Compatibilidad Ubuntu 26.04 LTS

### 🔴 [P0-BUG-01] El Gestor de Bloqueos (`[08]`) de `menu.sh` está 100% roto por subshell de pipe
- **Ubicación:** [menu.sh](file:///F:/mivpnv2.0/edge-node-manager/menu.sh#L787-L811), líneas `844–868` y `897–915`.
- **Problema:** Se inicializa `idx=1` (o `count=0`) y luego se hace `sqlite3 ... | while read -r line; do ... idx=$((idx + 1)); done`. En Bash, el pipe `|` ejecuta el `while` en un **subshell**, por lo que al terminar el bucle **`idx` sigue valiendo `1` y `count` sigue valiendo `0`**. Justo abajo, `if [ "$idx" -eq 1 ]` se cumple **siempre**, imprime `"No hay usuarios activos para bloquear"` y hace `continue`, haciendo **imposible bloquear o desbloquear usuarios desde el menú**.
- **Solución:** Usar redirección de sustitución de procesos `done < <(sqlite3 ...)` (igual que en `menu_mostrar_conectados`) o delegarlo a la API.

### 🔴 [P0-BUG-02] Corrupción de cuentas al cambiar HWID desde `menu.sh`
- **Ubicación:** [menu.sh](file:///F:/mivpnv2.0/edge-node-manager/menu.sh#L649-L676).
- **Problema:** Al cambiar el HWID de un cliente desde `[03] EDITAR` → `[3] CAMBIAR HWID`:
  1. Renombra el usuario Linux (`usermod -l "$n_hwid" "$uhwid"`), pero en SQLite **solo actualiza `hwid` y deja `username` con el HWID viejo**, rompiendo la sincronización con `account-reconciler.js` y `server.js`.
  2. Asigna como contraseña un hash MD5 truncado (`md5sum | cut -c 1-8`) en lugar del propio `$n_hwid`, rompiendo la conexión automática HWID en HTTP Custom y JOIF VPN (donde `usuario == contraseña == hwid`).

### 🔴 [P0-BUG-03] Reinicio de OpenSSH sin validación `sshd -t` en 3 puntos fuera de `network_tuning.sh`
- **Ubicación:** [setup](file:///F:/mivpnv2.0/edge-node-manager/setup#L238-L250), [setup](file:///F:/mivpnv2.0/edge-node-manager/setup#L270-L272), [menu.sh](file:///F:/mivpnv2.0/edge-node-manager/menu.sh#L245-L247) (`menu_banner`) y [menu.sh](file:///F:/mivpnv2.0/edge-node-manager/menu.sh#L1166-L1178) (`ejecutar_autolink`).
- **Problema:** Modifican `/etc/ssh/sshd_config` directamente con `sed` y reinician `sshd` sin asegurar `/run/sshd` ni validar con `sshd -t`. Además, `menu_banner()` reemplaza `{fecha_actual}` por `\d`, `\t`, `\s` (códigos de `agetty` que OpenSSH no soporta y muestra como texto literal).
- **Solución:** Centralizar toda recarga SSH en una única función `safe_reload_ssh()` en `core/utils.sh` (backup + `mkdir -p /run/sshd` + `sshd -t` + rollback automático) y usar archivos limpios en `/etc/ssh/sshd_config.d/` en lugar de editar `/etc/ssh/sshd_config` con `sed`.

### 🟠 [P1-BUG-04] `pkill -u <user> sshd` NO desconecta usuarios en Ubuntu 26.04 LTS ni Dropbear
- **Ubicación:** [server.js](file:///F:/mivpnv2.0/edge-node-manager/server.js#L188), [account-reconciler.js](file:///F:/mivpnv2.0/edge-node-manager/account-reconciler.js#L18), [limitador.sh](file:///F:/mivpnv2.0/edge-node-manager/limitador.sh#L52), [menu.sh](file:///F:/mivpnv2.0/edge-node-manager/menu.sh#L829).
- **Problema:** En Ubuntu 26.04 LTS (OpenSSH 10), las sesiones activas corren bajo el binario **`sshd-session`** (no `sshd`), y en Dropbear bajo `dropbear`. Por eso, al revocar una cuenta, vencer su fecha o superar el límite de conexiones en `limitador.sh`, **`pkill -u <user> sshd` no mata la sesión activa y el usuario sigue conectado gratis**.
- **Solución:** Usar `pkill -KILL -u "$nativeName"` (dado que son cuentas exclusivas VPN con `/bin/false` y UID >= 1000).

### 🟠 [P1-BUG-05] Desincronización entre Renovación/Bloqueo CLI (`menu.sh`) y SQLite
- **Ubicación:** [menu.sh](file:///F:/mivpnv2.0/edge-node-manager/menu.sh#L620-L624) y líneas `828–886`.
- **Problema:**
  - Al renovar una cuenta vencida desde `menu.sh`, se actualiza `expiration_date` y `chage -E`, pero **no se reactiva `status = 'active'` en SQLite ni se ejecuta `usermod -U`**, dejando al cliente renovado bloqueado tanto en SSH como en CheckUser (`HTTP 403`).
  - Al bloquear desde `menu.sh`, se hace `usermod -L` pero `status` sigue `'active'` en SQLite (CheckUser sigue diciendo `ACTIVO`), y en el siguiente ciclo `account-reconciler.js` o el panel web muestran datos inconsistentes.

### 🟠 [P1-BUG-06] Cabecera principal (`CLIENTES ONLINE`) marca `0` en Ubuntu 26.04
- **Ubicación:** [core/utils.sh](file:///F:/mivpnv2.0/edge-node-manager/core/utils.sh#L53-L59).
- **Problema:** `get_online_users()` sigue usando el filtro antiguo `/sshd:|dropbear/` en lugar del conteo por propietario `ps -eo user:32,args` que ya se corrigió en `backend-security.js` y `menu.sh`.

### 🟠 [P1-BUG-07] Conflicto de configuración de BadVPN (`10` vs `500` conexiones UDP)
- **Ubicación:** [protocol_manager.sh](file:///F:/mivpnv2.0/edge-node-manager/modules/network/protocol_manager.sh#L776-L793) vs [network_tuning.sh](file:///F:/mivpnv2.0/edge-node-manager/modules/system/network_tuning.sh#L166-L183).
- **Problema:** `network_tuning.sh` configura `--max-connections-for-client 500 --client-socket-sndbuf 65536`, pero `protocol_manager.sh` lo sobrescribe con `--max-connections-for-client 10` (demasiado bajo para llamadas WhatsApp/juegos modernos y QUIC).

### 🟠 [P1-BUG-08] Cambio de contraseña inicial falla sin mensaje claro en el Panel Web
- **Ubicación:** [change-password.html](file:///F:/mivpnv2.0/edge-node-manager/public/change-password.html#L23-L53) vs [server.js](file:///F:/mivpnv2.0/edge-node-manager/server.js#L77).
- **Problema:** El HTML pone `minlength="5"`, pero el backend exige mínimo **12 caracteres**. Si el administrador ingresa entre 5 y 11 caracteres, el frontend ignora el mensaje JSON del backend y lanza un `alert('Error cambiando contraseña')` genérico.

### 🟡 [P2-BUG-09] Opciones fantasma / inconclusas y desinstalador incompleto
- **Ubicación:**
  - `menu_crear_usuario()` ([menu.sh](file:///F:/mivpnv2.0/edge-node-manager/menu.sh#L37-L43)): ofrece `[01] DEMO`, `[04] TOKEN` y `[05] MODIFICAR CONTRASEÑA TOKEN`, pero todas ejecutan exactamente el flujo de cuenta SSH normal por días.
  - `protocol_manager.sh` ([líneas 91–583](file:///F:/mivpnv2.0/edge-node-manager/modules/network/protocol_manager.sh#L91-L583)) contiene 490 líneas de Xray VLESS inaccesibles desde el menú, mientras `update.sh` ([líneas 44–47](file:///F:/mivpnv2.0/edge-node-manager/update.sh#L44-L47)) fuerza la detención de `xray` en cada update.
  - `uninstall.sh` ([líneas 63–80](file:///F:/mivpnv2.0/edge-node-manager/modules/system/uninstall.sh#L63-L80)) no limpia `joif-smartdns-client.service`, `/usr/local/bin/joif-smartdns`, `/usr/bin/joif-bbr`, `/usr/bin/bbr`, `/etc/ssh/sshd_config.d/99-vpn-speed.conf`, `/etc/sysctl.d/99-vpn-tuning.conf` ni la cadena `JOIF_SMARTDNS_OUT`.
  - `iptables -I INPUT 1 ...` en `setup`, `menu.sh` y `protocol_manager.sh` no comprueba `-C` antes de insertar, acumulando reglas repetidas en cada ejecución.

---

## 3. Arquitectura, Rendimiento y Refactorización (`P2`)

### 3.1. Problema central: Dos fuentes de verdad y un monolito de 1,578 líneas
Actualmente las operaciones sobre cuentas están partidas en dos caminos incompatibles:
- **Alta y Baja:** pasan por `server.js` (`POST /api/users`, `DELETE /api/users/:username`).
- **Edición, Renovación, Cambio de Clave, Cambio de HWID y Bloqueo:** `menu.sh` ataca directamente `database.sqlite` y comandos Linux (`usermod`, `chage`, `chpasswd`), saltándose `backend-security.js` y dejando al Panel Web sin esas funciones.

#### Arquitectura objetivo recomendada
Convertir **`server.js` + `backend-security.js`** en la **única fuente de verdad** para cuentas (tanto para el CLI como para el Panel Web y la Tienda Central):
1. Añadir endpoints REST internos en `server.js` (protegidos por `authMiddleware`):
   - `PATCH /api/users/:username` → renovar/ajustar fecha, cambiar contraseña, cambiar límite `max_connections`, cambiar `hwid` (renombrando Linux + clave + DB atómicamente) o reiniciar `bytes_used`.
   - `POST /api/users/:username/unlock` → desbloquear (`usermod -U`, restaurar `chage -E` y `status = 'active'`).
   - `GET /api/system/status` → métricas reales del nodo (CPU, RAM, uptime, conexiones activas reales, estado de `sshd`, `joif-proxy`, `badvpn-7300`, `stunnel4`, `joif-limitador`, `smartdns` y BBR) para alimentar el Panel Web en vivo.
2. **Dividir `menu.sh` (97 KB → módulos limpios de < 200 líneas):**
   ```text
   edge-node-manager/
   ├── core/
   │   ├── ui.sh                 # Tema visual unificado, cajas, tablas, badges, prompts e inputs seguros
   │   ├── sys.sh                # Métricas rápidas (/proc), caché de IP pública, firewall idempotente, safe_reload_ssh()
   │   └── api_client.sh         # Wrapper curl + jq hacia 127.0.0.1:$PORT con manejo uniforme de errores
   ├── modules/
   │   ├── users/
   │   │   └── user_manager.sh   # CRUD, renovación, bloqueo, conectados, multilogin y banner estático seguro
   │   ├── network/
   │   │   ├── protocol_manager.sh  # WS Proxy, BadVPN (unificado a 500 conn), Stunnel SSL
   │   │   └── smartdns_client.sh   # Mini-script independiente Smart DNS (ya modularizado)
   │   ├── system/
   │   │   ├── network_tuning.sh    # BBR + sysctl + OpenSSH tuning (con validación sshd -t)
   │   │   ├── swap_manager.sh      # Crear/ajustar/eliminar SWAP en 1 paso automático
   │   │   ├── cleaner.sh           # Limpieza RAM/APT/logs
   │   │   ├── autostart_manager.sh
   │   │   └── uninstall.sh         # Desinstalación completa y limpia
   │   └── tools/
   │       ├── autolink.sh          # Vinculación con Portal/Tienda Web
   │       └── backup_manager.sh    # Backup seguro con sqlite3 ".backup" (sin corrupción WAL)
   └── menu.sh                      # Router principal ligero (~120 líneas)
   ```

### 3.2. Limpieza de archivos muertos y dependencias
- **Eliminar o archivar:**
  - `mivpn_web.sh` (script heredado que apunta a `/root/mivpn/edge-node-manager` y `mivpn-web.service`; migrar sus 2 funciones útiles —**rotar `SESSION_SECRET`** y **restringir puerto 3000 por IP**— a `modules/tools/`).
  - `modules/tools/extras_menu.sh` (menú duplicado oculto bajo la opción `30`).
  - Bloque muerto `startUdpgw()` en `server.js` (líneas `256–289`) y las 490 líneas huérfanas de Xray en `protocol_manager.sh` (o separarlas a un módulo opcional si algún día se reactiva).
  - `schema.sql` (es de PostgreSQL de otro proyecto; reemplazar por documentación real del esquema SQLite o eliminarlo).
  - Dependencia `"body-parser"` en `package.json` (no se usa; Express 5 ya lo incluye nativamente).
- **Backups seguros de SQLite en modo WAL (`backup_manager.sh`):**
  - Actualmente `cp -f database.sqlite` copia en caliente una base en modo `WAL` sin copiar `-wal`/`-shm`, pudiendo perder las últimas transacciones. Cambiar a `sqlite3 "$DB_FILE" ".backup '$DEST'"` que es atómico en caliente.

### 3.3. Optimización de velocidad del menú (`draw_header` instantáneo)
- **Ubicación:** [core/utils.sh](file:///F:/mivpnv2.0/edge-node-manager/core/utils.sh#L22-L51).
- **Problema:** Cada vez que el usuario entra o vuelve a cualquier pantalla, `get_sys_info()` hace una petición de red externa `curl -s ifconfig.me` **sin timeout** + `top -bn1` + 4 ejecuciones separadas de `free -m`. En redes lentas el menú tarda entre **1 y 5 segundos por pulsación**.
- **Mejora:**
  - Cachear la IP pública en `/run/joif_public_ip` (con `--max-time 2`, refrescando solo si no existe).
  - Leer RAM en una sola pasada de `/proc/meminfo` y carga de CPU desde `/proc/loadavg` (o diferencial corto de `/proc/stat`).
  - **Resultado:** Renderizado del menú en **< 15 ms** en lugar de ~1,500 ms.

---

## 4. Auditoría Visual y de Experiencia de Usuario (CLI + Panel Web)

### 4.1. Consola CLI (Terminal TUI)

#### Problemas actuales
1. **Tres estilos gráficos chocando entre sí:**
   - *Estilo heredado ChumoGH* en `menu.sh`: `=====>>►► 🐲 JOIF 💥 Cloud 🐲 ◄◄<<=====`, banderas ajenas (`🇪🇨`), íconos inconexos (`🥨`, `#OFFICIAL`), dobles líneas `━━━` seguidas y textos en mayúsculas gritadas.
   - *Estilo crudo sin diseño* en `swap_manager.sh`: líneas `====` rojas, obliga al usuario a ejecutar **4 pasos manuales separados** (1 crear → 3 dar formato → 4 activar → 5 prioridad) y tiene errores ortográficos visibles (`"Comprovar"`, `"comprueve"`, `"Desactvar"`, `"asta"`, `"swappines"`, `"ESCOJE"`).
   - *Estilo limpio moderno* en `smartdns_client.sh` y `network_tuning.sh`.
2. **Desalineación de columnas y anchos variables:**
   - Unas pantallas usan separadores de 50 columnas y otras de 60 columnas.
   - En `MOSTRAR USUARIOS REGISTRADOS` ([menu.sh](file:///F:/mivpnv2.0/edge-node-manager/menu.sh#L714-L748)), fechas ISO largas (`2026-12-23T15:04:02+00:00`) desbordan las columnas `%-13s` y muestran la contraseña en texto plano sin truncar.
   - No muestra la columna **CONSUMO (MB/GB)** pese a que SQLite ya almacena `bytes_used`.
3. **Opciones repetidas y opciones con candado `🔒`:**
   - *Backup* aparece en 3 menús distintos; *Auto-Link* en 3; *BBR* en 2.
   - En `menu_usuarios`, 5 de las 14 opciones están marcadas con `🔒` y no hacen nada, generando sensación de script inacabado.
4. **Instalador `setup` lento y confuso:**
   - Contiene ~9 segundos de `sleep` artificiales, mensajes falsos (`"INTENTANDO RECONFIGURAR UPDATER"`) y un logo ASCII que dice **`MVPN`** ([setup](file:///F:/mivpnv2.0/edge-node-manager/setup#L61-L65)) en vez de **`JOIF`**.

#### Propuesta de Rediseño Visual CLI ("JOIF TUI v2")
- **Ancho único estándar de 60 columnas** con bordes Unicode limpios (`╭───╮`, `│`, `╰───╯` o líneas simples `━`) y paleta coherente: Cian (`#38bdf8` / `\e[1;36m`) para bordes/marca, Verde para `[ON]`/éxito, Ámbar para advertencias, Rojo para `[OFF]`/errores, Gris tenue (`\e[0;90m`) para etiquetas secundarias.
- **Dashboard superior compacto y en tiempo real:**
  - Línea 1: Logo limpio **JOIF CLOUD v2.0** + Host/Dominio + IP enmascarable.
  - Línea 2: SO • Kernel/BBR badge • CPU • RAM con barra visual compacta `[████░░░░] 42%`.
  - Línea 3: Badges de servicios activos en dos columnas alineadas (`SSH:22 ●`, `WS:80 ●`, `SSL:443 ○`, `API:3000 ●`, `UDPGW:7300 ●`, `SmartDNS ●`).
  - Línea 4: Resumen rápido de cuentas (`Activas: 24` | `Online ahora: 9` | `Vencidas: 3`).
- **Simplificación de menús (cero opciones muertas, cero duplicados):**
  - Eliminar todas las opciones `🔒` sin implementar.
  - En `SWAP`: reemplazar los 5 pasos manuales por un asistente de **1 solo paso** (*"Crear y activar SWAP de 2 GB / 4 GB / 8 GB con swappiness=20"* o *"Desactivar y eliminar SWAP"*).
  - En `Tabla de Usuarios`: formatear fechas como `DD/MM/YYYY`, agregar columna **`TRÁFICO`** (`bytes_used` formateado en MB/GB) y ocultar/resumir contraseñas salvo en vista de detalle.

---

### 4.2. Panel Web Local (`public/`)

#### Problemas actuales
1. **Tres nombres de marca e idiomas mezclados:**
   - `login.html` → *"MiVPN Cloud"* (español, fuente Outfit).
   - `change-password.html` → *"MiVPN Cloud"* (estilos planos distintos, sin validación de 12 caracteres).
   - `index.html` → *"CyberShell - Admin Node"* (mitad en inglés `"User Management" / "Create User"` y mitad en español `"Borrar Todo" / "Revocar" / "Remover"`).
2. **Componentes decorativos o con datos falsos en `public/index.html`:**
   - **Tarjeta `"Active Connections"` (línea 486):** muestra la cantidad de usuarios con `status === 'active'` en la base de datos, **no** las sesiones conectadas en vivo.
   - **Pestaña `"VPS Services"` (líneas 250–314):** es una maqueta estática (los switches de BadVPN y OpenSSH no están conectados a ningún endpoint).
   - **Pestaña `"Config Generator"` (línea 342):** etiqueta el cifrado como `AES-256-GCM (Simulated)` cuando en realidad es cifrado real `JOIF_VPN_V1`.
   - **Navegación móvil rota:** en pantallas chicas (`< 768px`), el ícono `menu` superior no abre el sidebar y el botón `Logout` desaparece (`hidden md:flex`), dejando al administrador sin poder cambiar de vista ni cerrar sesión desde el celular.
   - **Gestión incompleta en la tabla:** falta buscador, columna de **Consumo (MB/GB)**, columna de **Conexiones en vivo (`1 / 3`)**, botón **Renovar (+días)**, **Editar límite/clave** y **Reactivar** cuentas revocadas/vencidas.
   - **Tailwind por CDN (`cdn.tailwindcss.com`):** descarga un runtime pesado desde internet en cada carga y falla si el navegador del admin tiene bloqueadores o mala red.

#### Propuesta de Rediseño Visual del Panel Web ("JOIF Node Panel v2")
1. **Unificar marca e idioma 100% en español bajo "JOIF Cloud — Panel de Nodo"** en las 3 páginas (`login.html`, `change-password.html`, `index.html`) usando un único archivo CSS local (`public/styles.css`) sin depender de `cdn.tailwindcss.com`.
2. **Dashboard real conectado a `GET /api/system/status` y `GET /api/users`:**
   - **4 KPIs reales:** *Usuarios Activos*, *Conectados Ahora (sesiones reales)*, *Tráfico Total Acumulado*, *Uso de RAM / CPU + Estado Smart DNS*.
   - **Tabla completa y responsive (tarjetas en móvil, tabla en escritorio):**
     - Buscador instantáneo + filtro (`Todos`, `Activos`, `Online`, `Por vencer`, `Vencidos/Revocados`).
     - Columnas: *Cliente / Alias*, *Conexiones (`online / límite`)*, *Consumo (`MB/GB`)*, *Vencimiento (con badge semáforo igual que la app Android)*, *Estado*, y acciones rápidas (*Renovar*, *Editar*, *Bloquear/Reactivar*, *Copiar Config / Link CheckUser*, *Eliminar*).
3. **Pestaña "Servicios del Nodo" funcional (o de lectura real):**
   - Mostrar el estado real de `OpenSSH`, `WS-Proxy (80)`, `BadVPN (7300/7200)`, `Stunnel (443)`, `Limitador` y `Smart DNS` con opción segura de reiniciar servicios permitidos.
4. **Navegación móvil completa:** barra inferior o drawer funcional en celular con botón de cerrar sesión siempre accesible.

---

## 5. Plan de Trabajo Recomendado (Orden de Ejecución por Fases)

Para refactorizar sin romper producción ni perder compatibilidad con los `15/15` tests actuales y con la app Android:

### Fase 1 — Seguridad Crítica y Corrección de Bugs `P0`/`P1` (Backend + Core)
1. Generar `API_KEY` aleatoria en instalaciones nuevas (manteniendo la existente en `.env` al actualizar para no romper nodos ya vinculados al portal).
2. Corregir `pkill -KILL -u <user>` en `server.js`, `account-reconciler.js` y `limitador.sh` (soporte real `sshd-session` + `dropbear` en Ubuntu 26.04).
3. Agregar rate-limiting en `/api/auth/login` y proteger `GET /check` global.
4. Crear `safe_reload_ssh()` y helper `ensure_firewall_port()` idempotente (`iptables -C` antes de `-I`).
5. Unificar parámetros de BadVPN (`500` conexiones, buffer `65536`) y corregir `get_online_users()` en `core/utils.sh`.

### Fase 2 — API Única de Gestión de Usuarios (`server.js`)
1. Añadir endpoints `PATCH /api/users/:username`, `POST /api/users/:username/unlock` y `GET /api/system/status` con sus tests unitarios e integración en `edge.test.js` y `edge-api.test.js`.
2. Migrar backups a `sqlite3 ".backup"` atómico.

### Fase 3 — Modularización y Rediseño Visual del CLI (`JOIF TUI v2`)
1. Crear `core/ui.sh`, `core/sys.sh` (caché IP + lectura `/proc` en < 15 ms) y `core/api_client.sh`.
2. Extraer `modules/users/user_manager.sh` y `modules/tools/autolink.sh`, reduciendo `menu.sh` a ~120 líneas y corrigiendo los bugs de subshell (`[08] Bloqueos`), renovación y cambio de HWID.
3. Rediseñar `setup`, `swap_manager.sh` (1 paso, ortografía corregida) y `uninstall.sh` (limpieza total), y eliminar archivos muertos (`mivpn_web.sh`, `extras_menu.sh`, opciones `🔒`).

### Fase 4 — Rediseño Visual y Funcional del Panel Web (`public/`)
1. Unificar diseño e idioma ("JOIF Cloud") con CSS local ligero, navegación móvil funcional y validación clara en `change-password.html` (mínimo 12 caracteres con mensaje real del servidor).
2. Conectar métricas reales en vivo, columna de **GB Utilizados**, buscador y modales de **Renovar / Editar / Reactivar** usuarios.
