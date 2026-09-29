# ORBEX

Un compañero de vidrio que vive en el notch de tu MacBook. ORBEX es una esfera translúcida con dos ojos ovalados negros, brazos en forma de gota y piernitas: respira, parpadea, te mira, reacciona, te asiste con IA, vigila tus sesiones de Claude Code y se transforma en un reloj flotante.

> **Para instalarla en tu Mac: [`INSTALAR.md`](INSTALAR.md)** (incluye un prompt listo para que Claude Code la compile e instale).
> Estado y avance: ver [`docs/PLAN.md`](docs/PLAN.md).
> Diseño completo: ver [`docs/00-informe-completo.md`](docs/00-informe-completo.md).

![Hoja del personaje](design/character/hoja-personaje.webp)

---

## Instalar (en tu Mac)

Requisitos: **macOS 15 o superior** y **Xcode 16 o superior** (o sus Command Line Tools: `xcode-select --install`). Con Xcode 26 en macOS 26 usa el Liquid Glass nativo.

- **Primera vez:** `bash scripts/install.sh` desde la carpeta del proyecto.
- **Ya tenías una versión anterior:** bajá el ZIP nuevo, descomprimilo y corré `bash scripts/actualizar.sh` (instala encima y limpia los restos de la vieja, sin tocar tus datos).

Todo paso a paso, con un prompt listo para pegarle a Claude: [`INSTALAR.md`](INSTALAR.md).

| Comando | Qué hace |
|---|---|
| `bash scripts/install.sh` | Compila, arma `ORBEX.app` + `dist/ORBEX.dmg`, la instala en Aplicaciones y la abre |
| `bash scripts/actualizar.sh` | Instala la versión nueva sobre la anterior y borra sus restos |
| `bash scripts/build-app.sh` | Solo compila y arma `dist/ORBEX.app` |
| `bash scripts/make-dmg.sh` | Genera `dist/ORBEX.dmg` a partir de `dist/ORBEX.app` |
| `bash scripts/uninstall.sh` | Borra la app, el acceso directo, los hooks y (con `--all`) tus datos |
| `swift test` | Corre las pruebas de la lógica (`OrbexCore`) |

---

## Qué es ORBEX ahora

ORBEX vive en una **isla de 640 pt** que sale del notch (medido en vivo, nunca hardcodeado) y se
transforma con resorte entre oculta, asomada, pastillas, abierta, asistente y reloj.

**Interacciones con el personaje**
- **Caricia:** dejá el mouse quieto sobre ORBEX y se derrite de gusto.
- **Cosquillas:** clic sobre ORBEX; tres clics rápidos y se marea.
- **Arrastrar sobre una ventana:** agarralo del notch y soltalo sobre cualquier ventana; ORBEX toma su título como contexto para el chat.
- **Soltar un archivo** en el notch: se lo "traga" y te pregunta qué hacer (adjuntarlo al chat, mandarlo por mail…).
- Personalidad: te saluda por tu nombre según la hora, te extraña, te mira tipear, sigue la app nueva.

**En la isla**
- **Sesiones de Claude Code:** una pastilla por sesión; aprobar / siempre / denegar permisos y responder preguntas desde el notch, o saltar a la terminal. Si ORBEX está cerrado, Claude Code sigue normal.
- **Chat** con Claude usando tu `claude` local (sin claves).
- **Timers, notas y música** (Spotify / Música, con baile al ritmo).
- **Reloj flotante** (el notch se convierte en reloj).
- **Temas:** Liquid Glass, macOS limpio y Y2K, cada uno con sus sonidos sintetizados.
- **Integraciones** (GitHub, Vercel, Stripe, n8n, Resend, Notion, Cal.com): hasta 4 pastillas, claves en el Keychain.

| Atajo | Acción |
|---|---|
| ⌃⌥O | Abrir la isla |
| ⌃⌥A | Asistente (Claude vía `claude` local) |
| ⌃⌥C | Reloj flotante |
| ⌃⌥, | Configuración |

---

## Cómo está hecho

- **Swift + SwiftUI + AppKit**, sin dependencias de terceros.
- Paquete de Swift con tres partes:
  - `Sources/OrbexCore` — lógica pura (estados de la isla, geometría, motor de vida, temporizadores, planificador, memoria, comandos, hooks). Con pruebas.
  - `Sources/Orbex` — la app. `Base/` es el cascarón de la isla, basado en el código de Coucou; el resto (personaje, reloj, asistente, sesiones, temas, configuración, sistema) es de ORBEX.
  - `Sources/orbex-hook` — ejecutable mínimo que conecta los hooks de Claude Code con la app por un socket Unix. Si ORBEX no está abierto, sale al instante: **nunca bloquea a Claude Code**.
- ORBEX está **dibujado por código**, no usa imágenes: se puede animar todo (ojos que siguen el cursor, respiración, parpadeo, poses).
- Los sonidos están **sintetizados por código** (originales, sin licencias de terceros).
- Las claves de API se guardan en el **Keychain** de macOS. Nunca en el repo.
- Sin telemetría, sin cuenta.

## Estructura

```
docs/        informe, decisiones, fases y plan con el avance
design/      hoja del personaje, referencias, logo, temas
Sources/     código (OrbexCore, Orbex, orbex-hook)
Tests/       pruebas de OrbexCore
scripts/     build, dmg, install, actualizar, uninstall, ícono
sounds/      notas sobre los sonidos (se generan por código)
```

## Licencia y créditos

Todos los derechos reservados. Ver [`LICENSE`](LICENSE).

La isla está **basada en el código MIT de [Coucou](https://github.com/louis-cfm/coucou)** (© 2026 Louis Raillé),
en `Sources/Orbex/Base/`. Solo el código: ni el personaje Mochi, ni nombres, íconos, sonidos o imágenes de
Coucou. Detalle y texto de la licencia en [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
