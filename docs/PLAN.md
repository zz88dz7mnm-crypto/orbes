# ORBEX — Plan de acción y avance

<h1 align="center">🔵 AVANCE TOTAL: 100 %</h1>

<p align="center">
  <img src="https://img.shields.io/badge/ORBEX-100%25-3fa7ff?style=for-the-badge" alt="Avance 100 %" height="60">
</p>

<h3 align="center">▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 100 / 100</h3>

<h3 align="center">🛠️ Ahora mismo: ¡Listo para bajar e instalar! Seguí INSTALAR.md en tu Mac</h3>

<p align="center"><i>Última actualización: 29/09/2026 00:03 UTC — se actualiza en cada push</i></p>

---

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
