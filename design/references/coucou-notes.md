# Notas sobre Coucou (referencia)

Repo: https://github.com/louis-cfm/coucou — código **MIT** (se puede estudiar respetando el aviso de copyright), assets **todos los derechos reservados** (no se reutilizan: nombre, personaje "Mochi", ícono, sonidos).

Coucou es una app de macOS (Swift 6, SwiftUI + AppKit, ~11 000 líneas) con un personaje que vive en el notch, muestra sesiones de Claude Code e integraciones.

## Qué aprendimos y cómo lo usa ORBEX

| Tema | Cómo lo hace Coucou | Qué hace ORBEX |
|---|---|---|
| Ventana | `NSPanel` `[.borderless, .nonactivatingPanel]`, fondo transparente, sin sombra, nivel `mainMenuWindow + 3`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`. Sobrescribe `constrainFrameRect` para que macOS no la empuje debajo de la barra de menú | Igual (patrón probado) |
| Clics que pasan | Panel grande fijo (720×320) con `ignoresMouseEvents = true`; un timer a 60 Hz mira si el mouse está dentro del rect actual de la isla y lo activa/desactiva | Igual, pero el sondeo baja a ~10 Hz cuando la isla está oculta (ahorro de batería) |
| Medida del notch | `safeAreaInsets.top` y `frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width` | Igual + ajuste fino ±10/±6 pt + notch simulado si no hay |
| Máquina de estados | FSM pura: `hidden → petit → home`, `coucou` (saludo). Timers de colapso (15 s home→petit, 60 s petit→hidden) | FSM en `OrbexCore` con los estados del informe (oculto, asomado, activo, te necesita, abierto, asistente, reloj, dormido) y reloj inyectable para probarla |
| Teclado | Monitor global de `keyDown` para Esc y el atajo (requiere permiso de Accesibilidad) | Atajos con **Carbon `RegisterEventHotKey`** (no pide permisos) |
| Hooks de Claude Code | Script **Python** `nb-hook` → socket Unix en `~/Library/Application Support/NotchBuddy/nb.sock`. `PermissionRequest` mantiene el socket abierto hasta que el usuario decide (115 s). Si no hay app, **deniega** | Ejecutable Swift `orbex-hook` (no depende de Python). Si no hay app o se vence el tiempo, **no decide** y Claude Code pregunta en la terminal |
| Instalar hooks | Lee `~/.claude/settings.json`, backup con fecha, merge, muestra preview, escribe tras confirmar; desinstalar filtra por nombre del comando | Igual + diff línea por línea |
| Personaje | Dibujado por código (`Canvas` + `TimelineView`), sin imágenes | Igual |
| Sonidos | 28 WAV propios | Sintetizados por código |
| IA | `api.anthropic.com/v1/messages`, clave en Keychain | Claude + OpenAI, streaming, selector de modelo |
| Integraciones | *Pollers* por servicio (n8n, Vercel, Resend, GitHub, Stripe, Cal.com, Notion) | Igual, apagables, solo lectura, dormidos si nadie mira |
| Adjuntar ventana | Arrastrar al bot sobre una ventana (CGWindowList + Accesibilidad) | Fase posterior (extra) |

## Diferencias a propósito
- Coucou solo acepta eventos si la terminal es VS Code; ORBEX acepta cualquier terminal y usa `TERM_PROGRAM` para saber a cuál saltar.
- Coucou usa XcodeGen; ORBEX usa Swift Package + scripts para no requerir herramientas extra.
