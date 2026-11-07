# 🐲 JOIF Cloud (V1.5.0) 💥

**JOIF Cloud** es un gestor de servidores y clústeres VPN/SSH de alto rendimiento, diseñado para arquitecturas distribuidas, automatización de protocolos (WebSocket SSH, BadVPN UDP-GW, Stunnel SSL) y aprovisionamiento masivo de usuarios mediante API REST y Panel Web integrado.

---

## ⚡ Instalación en 1 Línea

En tu servidor VPS limpio (Ubuntu 20.04/22.04/24.04/26.04 o Debian 10/11/12):

```bash
curl -fsSL https://raw.githubusercontent.com/manuel3200/joif-script/main/setup -o setup && chmod +x setup && ./setup
```

Una vez instalado, escribe:
```bash
menu
```

---

## 🚀 Características Principales

* ⚡ **WebSocket Proxy Optimizado (Puerto 80 -> 22):**
  * Diseñado con Node.js `libuv`, TCP NoDelay (latencia cero para juegos), Keep-Alive agresivo cada 15s y soporte para encabezados `X-Real-Host` y `X-HWID`.
* 🎮 **BadVPN UDP-GW Nativo (Puertos 7300 y 7200):**
  * Servicios nativos de systemd independientes para juegos en línea y llamadas VoIP (WhatsApp, Discord, etc.).
* 🔒 **Stunnel SSL / TLS (Puerto 443 -> WS 80 / SSH 22):**
  * Certificados autofirmados automáticos y reenvío transparente de alta velocidad.
* 🌐 **API REST de Integración & CheckUser (Puerto 3000):**
  * Conecta tu sitio web, tienda online, panel de revendedores o bot de Telegram para dar de alta y controlar cuentas en tiempo real.
  * Compatible con el estándar CheckUser de aplicaciones móviles (SSHPLUS, DTunnel, HTTP Custom).
* 🛡️ **Seguridad PAM & Linux Real:**
  * Cada usuario se registra de forma nativa en Linux con shell `/bin/false` y caducidad automática en `/etc/shadow`.

---

## 📚 Documentación de la API REST

Para conectar tu página web, bot o sistema de facturación con tu VPS, consulta la guía completa:

👉 **[Documentación Oficial de la API REST (API_DOCUMENTATION.md)](API_DOCUMENTATION.md)**

### Resumen de Endpoints Principales:

| Método | Endpoint | Descripción | Acceso |
| :---: | :--- | :--- | :---: |
| `POST` | `/api/users` | Crear cuenta SSH o HWID en Linux y DB | `x-api-key` |
| `GET` | `/api/users` | Listar todos los usuarios registrados | `x-api-key` |
| `POST` | `/api/users/:target/revoke` | Suspender usuario y cerrar sesiones activas | `x-api-key` |
| `DELETE` | `/api/users/:target` | Eliminar usuario permanentemente | `x-api-key` |
| `GET` | `/check/:id` | CheckUser compatible con HTTP Custom / SSHPLUS | Público |
| `GET` | `/check` | Array simple de usuarios activos | Público |

---

## 🛠️ Comandos de Administración en la VPS

* `menu`: Abre el panel CLI interactivo en la terminal.
* `joif-update`: Sincroniza y actualiza los scripts y servicios con el repositorio central en 1 segundo.

---
© 2026 TheJOIF. Todos los derechos reservados.
