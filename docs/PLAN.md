# ORBEX — Plan de acción y avance

<h1 align="center">🟢 ETAPA 4 · Orbi habla + modo inteligente: 70 %</h1>

# Etapa 4 — Orbi responde con voz natural y "modo inteligente"

Pedido del dueño (30/09/2026): que Orbi **responda hablando** ("hola" → "¡Hola! ¿Cómo estás?") con una voz
natural como la de OpenJarvis (Kokoro, Apache 2.0), no robótica; y "Orbi, activar modo inteligente" despliega
un panel con toda la interacción al estilo fullstack-agent (cara que escucha/piensa/habla, conversación,
memoria), con diseño de Orbi. fullstack-agent es AGPL: se toma solo la idea, sin copiar código.

- [x] W1 · Voz de salida: Kokoro local (voz en español, `ef_dora`) + Cartesia opcional (clave en Keychain) + voz de macOS de respaldo
- [ ] W2 · Conversación: Orbi contesta hablando (charla corta, confirma acciones), comando "activar/desactivar modo inteligente"
- [x] W3 · Panel "modo inteligente": cara grande de Orbi, conversación en vivo, memoria, acciones, micrófono
- [x] W4 · Orbi hablando: animación sincronizada con la voz (brillo y ondas al ritmo)
- [ ] W5 · Verificación y docs

---

<h1 align="center">🟣 ETAPA 3 · Limpieza, arreglos y voz: 100 % ✅</h1>

<h3 align="center">🛠️ Listo: bajar e instalar con scripts/actualizar.sh (ver INSTALAR.md) · 90 archivos OK · 149/149 pruebas</h3>

# Etapa 3 — Asistente por voz ("Orbex, …") y limpieza

Pedido del dueño (30/09/2026): sacar Resend, n8n, GitHub y Vercel; sacar los 4 personajitos a la derecha
del notch y el texto que queda debajo de la cámara; arreglar que la isla quede abierta al hacer clic
afuera y los saltos de forma/íconos; y **hablarle**: "Orbex/Orbi, …" → ORBEX hace la acción (sin
responder hablando), con color y gesto propios mientras escucha.

- [x] V1 · Limpieza: fuera Resend, n8n, GitHub, Vercel (pollers, tarjetas, pastillas, claves, ajustes); sin minis a la derecha del notch; sin frase debajo de la cámara
- [x] V2 · Arreglos de la isla: clic afuera cierra; forma e íconos sin saltos
- [x] V3 · Voz (lógica, OrbexCore): palabra de activación con variantes, extracción del pedido, fin de frase, con pruebas
- [x] V4 · Voz (app): escucha en el dispositivo (Speech), permisos en el primer uso, pedido → comandos de ORBEX o Claude, Configuración › Voz
- [x] V5 · Gesto y color de escucha (magenta #E040FB): ORBEX pone la mano en la oreja, ondas según tu voz
- [x] V6 · Verificación (sintaxis, pruebas, símbolos) y docs

---

<h1 align="center">🔵 ETAPA 2 · ORBEX sobre Coucou: 100 %</h1>

<p align="center">
  <img src="https://img.shields.io/badge/ETAPA_2-100%25-3fa7ff?style=for-the-badge" alt="Etapa 2: 100 %" height="60">
</p>

<h3 align="center">▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 100 / 100</h3>

<h3 align="center">🛠️ Ahora mismo: Listo: bajar e instalar con scripts/actualizar.sh (ver INSTALAR.md)</h3>

<p align="center"><i>Última actualización: 29/09/2026 02:16 UTC — se actualiza en cada push</i></p>

<p align="center">Etapa 1 (ORBEX propio, fases 0–6): <b>100 % ✅</b> — versión previa en el commit <code>ab818d5</code></p>

---

# Etapa 2 — ORBEX sobre la base de Coucou

Se clona el código de Coucou (MIT) como cascarón de la app, Mochi se reemplaza por ORBEX con animaciones
nuevas, y se le aplica todo lo de ORBEX. Plan completo y decisiones: `docs/decisiones.md`; reparto de
archivos por fase: `docs/CONTRATOS.md`.

Pesos: E0 3 % · E1 17 % · E2 20 % · E3 15 % · E4 5 % · E5 15 % · E6 10 % · E7 7 % · E8 3 % · E9 5 %.

## E0 · Preparación (3 %) ✅
- [x] Avisos de licencia (THIRD_PARTY_NOTICES, LICENSE), CLAUDE.md regla 13, decisiones, contratos, plan

## E1 · Clonar Coucou y unificar el cascarón (17 %)
- [x] Código de Coucou en `Sources/Orbex/Base/` con cabecera MIT; sin assets
- [x] Retirar duplicados de ORBEX y de Coucou; resolver 13 choques de nombres
- [x] Marca ORBEX (bundle, carpetas, logs, textos); `Package.swift` macOS 15
- [x] `AppDelegate` único + `OrbexBridge` + `SoundEngine.play(nombre)`
- [x] Sintaxis OK + chequeo de símbolos

## E2 · Personaje ORBEX en el motor (20 %)
- [x] `BotEngine` dibuja ORBEX (misma API), mini-ORBEX, portal de vidrio, bugs del motor arreglados
- [x] Saludo propio de ORBEX y "tragar archivo" propio

## E3 · Animaciones nuevas y personalidad (15 %)
- [ ] Caricia, cosquillas, globo al arrastrar, burbujas, órbitas, confeti, empañado, dormir/despertar, estornudo…
- [ ] Personalidad: saludo por nombre y hora, "te extrañé", rachas, frases, te ve tipear

## E4 · Sonidos y español (5 %)
- [ ] 28 sonidos sintetizados nuevos para los eventos de Coucou (por tema)
- [ ] Textos de la UI de Coucou al español

## E5 · Asistente y utilidades en la isla (15 %)
- [ ] Chat de la isla con `claude` local + Clawd + ORBEX naranja + comandos + memoria
- [ ] Pestañas Timers, Notas, Música; avisos → vista nota; botón de reloj

## E6 · Temas, reloj, música, notch y sistema (10 %)
- [ ] Temas Liquid Glass / macOS limpio / Y2K sobre la UI de Coucou
- [ ] Notch configurable, reloj flotante, bienvenida, atajos, inicio con la Mac, acceso directo

## E7 · Sesiones de Claude Code (7 %)
- [ ] Motor de ORBEX detrás de la UI de Coucou: aprobaciones y preguntas reales, una pastilla por sesión

## E8 · Configuración, empaquetado y docs (3 %)
- [ ] Configuración unificada, Info.plist, README, INSTALAR, fases
- [ ] `scripts/actualizar.sh`: instala la versión nueva sobre la anterior y borra sus restos (app vieja, compilados, hooks viejos de ORBEX/Coucou), sin tocar tus datos sin preguntar; prompt listo para Claude en tu Mac

## E9 · Verificación (5 %)
- [ ] Pruebas de OrbexCore, sintaxis, símbolos, revisores

---

# Etapa 1 — ORBEX propio (completa)

Pesos: Fase 0 = 5 % · Fase 1 = 30 % · Fase 2 = 20 % · Fase 3 = 15 % · Fase 4 = 12 % · Fase 5 = 8 % · Fase 6 = 7 % · Cierre = 3 %.

Leyenda: `[x]` hecho y subido · `[~]` en curso · `[ ]` pendiente.

---

## Verificación automática (en la nube)
- `OrbexCore` se compila y se prueba con **Swift 6.1 en Linux** (Docker `mirror.gcr.io/library/swift:6.1-noble`): **116/116 pruebas OK** (cierre, 29/09/2026).
- El código de la app (AppKit/SwiftUI) se revisa con `swiftc -parse` (sintaxis). La compilación completa necesita macOS (tu Mac o GitHub Actions).

## Cómo retomar (si se corta la sesión)
1. Leé este archivo: lo marcado `[x]` ya está en el repo; `[~]` quedó a medias.
2. Mirá `git log --oneline -20` para ver lo último que se subió.
3. Seguí por el primer `[~]` o `[ ]` de la lista, respetando `CLAUDE.md`.
4. **Regla de trabajo:** una fase a la vez. Todos los subagentes trabajan SOLO en la fase actual; la siguiente arranca cuando la actual está cerrada. Reparto de la fase actual en `docs/CONTRATOS.md`.

## Fase 0 — Preparación (5 %) ✅
- [x] README, CLAUDE.md, LICENSE, .gitignore, .gitattributes
- [x] `docs/00-informe-completo.md`, `docs/decisiones.md`, `docs/fases.md`, `docs/PLAN.md`
- [x] `design/character/hoja-personaje.webp` + especificación del personaje
- [x] `design/references/coucou-notes.md` (estudio de la referencia)

## Fase 1 — Núcleo visual (30 %) ✅
- [x] Package.swift + OrbexCore (estados, geometría de isla, motor de vida, expresiones) + tests
- [x] Medición del notch, panel de la isla, morph con resorte, hover/clic, sin notch, cambio de resolución
- [x] Personaje ORBEX por código (vidrio, ojos que siguen el cursor, brazos, piernas, poses, colores, clics/mareo, dormido)
- [x] Tema Liquid Glass + reducir movimiento/transparencia + claro/oscuro; sonidos base sintetizados
- [x] Configuración básica con vista previa; primer arranque (acceso directo, inicio con la Mac)
- [x] Ícono generado por código; scripts build/dmg/install; workflow manual de GitHub Actions


## Fase 2 — Asistente y utilidades (20 %) ✅
- [x] Comandos en español, timers/cronómetro/pomodoro, notas, autonomía y apps permitidas
- [x] Pantallas de Timers y Notas en la isla, abrir apps, ejecutor de comandos
- [x] Asistente: solo Claude vía `claude` local, chat interactivo, ORBEX naranja, Clawd animado
- [x] Soltar un archivo en el notch lo adjunta al asistente
- [x] Configuración: Asistente, Timers, Notas, Acciones y apps

## Fase 3 — Sesiones de código (15 %) ✅
- [x] `orbex-hook`: relé por socket Unix, espera permisos, nunca bloquea a Claude Code, ignora al asistente propio
- [x] Servidor del socket + lectura de eventos + seguimiento de sesiones
- [x] Instalador de hooks: merge sin tocar hooks ajenos, diff para confirmar, backup con fecha, desinstalar
- [x] Sesiones en vivo en la isla (pestaña Código) + aprobar Permitir / Siempre / Denegar
- [x] Saltar a la terminal correcta (Terminal, iTerm2, VS Code, Warp, Ghostty…)
- [x] Codex CLI (experimental, a validar)
- [x] Configuración › Claude Code

## Fase 4 — Reloj y memoria (12 %) ✅
- [x] Reloj flotante: esferas Clásica (Rolex), Retro de pared y ORBIT futurista, con ORBEX vivo en la esfera
- [x] Morph notch ↔ reloj, arrastrar, pegarse a bordes, tamaños, opacidad, click-through (⌥), tic-tac, anillo del timer
- [x] Acciones a hora puntual ("a las 21 recordame…", "a las 9 abrime mi setup"), vencidas al despertar
- [x] Memoria local editable ("acordate que…"), contexto del asistente
- [x] Configuración: Reloj, Acciones programadas, Memoria

## Fase 5 — Temas (8 %) ✅
- [x] Sistema de skins: tema × esfera; cada tema con su pack de sonido sintetizado (vidrio / clics suaves / chiptune)
- [x] Liquid Glass: vidrio nativo en macOS 26+, respaldo en anteriores, control propio de transparencia
- [x] macOS limpio: tarjetas sólidas, ORBEX sólido, bordes sobrios
- [x] Y2K metálico (Winamp): ORBEX cromado, botones gelatina, pantallita LCD, ecualizador, bisel cromado en la isla
- [x] Cambio de tema en vivo (con saludo en el pack nuevo); respeta reducir transparencia y movimiento

## Fase 6 — Integraciones (7 %) ✅
- [x] Spotify / Música: qué suena, portada, controles, ORBEX verde y bailando (sin abrir las apps)
- [x] Baile al ritmo: audio del sistema (ScreenCaptureKit) → energía de graves (opcional, con permiso)
- [x] GitHub, Vercel, Stripe, n8n, Resend, Notion, Cal.com: solo lectura, clave en Keychain, interruptor, color de ORBEX
- [x] Página Servicios y Música en la isla; Configuración › Música e Integraciones

## Cierre (3 %) ✅
- [x] `OrbexCore` compila con Swift 6.1 y pasan **116/116 pruebas** (Linux, Docker)
- [x] `orbex-hook` compila y nunca bloquea a Claude Code (probado en Linux)
- [x] Revisión automática: sintaxis OK en los 67 archivos, sin tipos duplicados, todas las llamadas entre módulos (`X.shared.algo`) apuntan a algo que existe
- [ ] Compilación real en macOS: la hace Claude en tu Mac siguiendo `INSTALAR.md` (corrige lo que marque el compilador)
- [x] `INSTALAR.md`: instrucciones paso a paso + prompt para que Claude la instale en tu Mac
- [x] Checklist final de criterios de aceptación por fase (`docs/fases.md`)
- [x] README final

---

## Historial
| Fecha | Avance | Qué se subió |
|---|---|---|
| 28/09/2026 | 3 % | Plan inicial y estructura del repo |
| 28/09/2026 | 5 % | Fase 0 completa: decisiones, fases, especificación del personaje, notas de Coucou |
| 28/09/2026 | 14 % | OrbexCore + pruebas, tema Liquid Glass, cerebro del personaje, Info.plist |
| 28/09/2026 | 16 % | Dibujo de ORBEX por código: vidrio, ojos, brazos-gota, piernas, extras |
| 28/09/2026 | 17 % | Contratos entre módulos + 4 subagentes nuevos |
| 28/09/2026 | 18 % | AppModel, marcador de orbex-hook, subagentes de la Fase 1 |
| 28/09/2026 | 22 % | Isla en el notch: panel, clics que pasan, hover, estados, página de inicio, menú de barra, arranque |
| 28/09/2026 | 22 % | Swift 6.1 en Linux (Docker): OrbexCore compila, 34/34 pruebas OK |
| 28/09/2026 | 24 % | Empaquetado completo: build-app, install, make-dmg, uninstall, ícono y workflow manual |
| 28/09/2026 | 28 % | Servicios del sistema: sonidos sintetizados, atajos, inicio con la Mac, acceso directo, ícono de barra, bienvenida |
| 28/09/2026 | 33 % | Configuración completa con vista previa en vivo; toda la Fase 1 escrita |
| 28/09/2026 | 33 % | Arranca la Fase 2 con 2 subagentes |
| 28/09/2026 | 39 % | Fase 2: comandos en español y lógica del chat listos; Clawd dibujado |
| 28/09/2026 | 42 % | Fase 1 cuenta completa; timers/cronómetro/pomodoro listos |
| 28/09/2026 | 45 % | Fase 2: notas y autonomía listas; conexión en la isla y Configuración |
| 28/09/2026 | 55 % | Fase 2 completa: asistente con Claude CLI + Clawd, comandos, timers, notas |
| 28/09/2026 | 70 % | Fase 3 completa: hooks de Claude Code, aprobaciones desde el notch, saltar a la terminal |
| 28/09/2026 | 82 % | Fase 4 completa: reloj flotante con 3 esferas, acciones programadas, memoria |
| 28/09/2026 | 90 % | Fase 5 completa: temas Liquid Glass, macOS limpio y Y2K con sus sonidos |
| 28/09/2026 | 97 % | Fase 6 completa: Spotify + baile al ritmo + 7 integraciones |
| 28/09/2026 | 98 % | Cierre: OrbexCore compila y pasan 116/116 pruebas |
| 29/09/2026 | 99 % | INSTALAR.md, checklist final, README |
| 29/09/2026 | 100 % | Cierre: revisión automática OK; listo para descargar e instalar |
| 29/09/2026 | E2: 3 % | E0: licencia, reglas, decisiones, contratos y plan de la Etapa 2 |
| 29/09/2026 | E2: 20 % | E1 completa: cascarón de Coucou + puente con ORBEX |
| 29/09/2026 | E2: 40 % | E2 completa: ORBEX en el motor, saludo y portal |
| 29/09/2026 | E2: 85 % | E5 completa: chat con claude y utilidades en la isla |
| 29/09/2026 | E2: 92 % | E6 completa |
| 29/09/2026 | E2: 95 % | E4 completa |
| 29/09/2026 | E2: 97 % | E8 completa |
| 29/09/2026 | E2: 100 % | Etapa 2 completa |
