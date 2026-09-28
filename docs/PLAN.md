# ORBEX — Plan de acción y avance

<h1 align="center">🔵 AVANCE TOTAL: 33 %</h1>

<p align="center">
  <img src="https://img.shields.io/badge/ORBEX-33%25-3fa7ff?style=for-the-badge" alt="Avance 33 %" height="60">
</p>

<h3 align="center">▓▓▓▓▓▓▓░░░░░░░░░░░░░ 33 / 100</h3>

<h3 align="center">🛠️ Ahora mismo: Fase 2 en marcha: utilidades (F2-A) + asistente Claude CLI con Clawd (F2-B); revisión final de la Fase 1 en paralelo</h3>

<p align="center"><i>Última actualización: 28/09/2026 23:18 UTC — se actualiza en cada push</i></p>

---

Pesos: Fase 0 = 5 % · Fase 1 = 30 % · Fase 2 = 20 % · Fase 3 = 15 % · Fase 4 = 12 % · Fase 5 = 8 % · Fase 6 = 7 % · Cierre = 3 %.

Leyenda: `[x]` hecho y subido · `[~]` en curso · `[ ]` pendiente.

---

## Verificación automática (en la nube)
- `OrbexCore` se compila y se prueba con **Swift 6.1 en Linux** (Docker `mirror.gcr.io/library/swift:6.1-noble`): **34/34 pruebas OK** (28/09/2026).
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

## Fase 1 — Núcleo visual (30 %) ✅ escrita
- [x] Package.swift + OrbexCore (estados, geometría de isla, motor de vida, expresiones) + tests
- [x] Medición del notch, panel de la isla, morph con resorte, hover/clic, sin notch, cambio de resolución
- [x] Personaje ORBEX por código (vidrio, ojos que siguen el cursor, brazos, piernas, poses, colores, clics/mareo, dormido)
- [x] Tema Liquid Glass + reducir movimiento/transparencia + claro/oscuro; sonidos base sintetizados
- [x] Configuración básica con vista previa; primer arranque (acceso directo, inicio con la Mac)
- [x] Ícono generado por código; scripts build/dmg/install; workflow manual de GitHub Actions

- [ ] Compilación real en macOS (tu Mac con `./scripts/install.sh` o GitHub Actions) — pendiente

## Fase 2 — Asistente y utilidades (20 %)
- [~] Panel del asistente: **solo Claude vía `claude` CLI local** (sin claves de API), chat interactivo, ORBEX se pone naranja y aparece la mascota de Claude Code, atajo global
- [~] Parser de comandos en español: abrir apps (allowlist), notas, temporizadores
- [~] Temporizadores y cronómetro con vueltas, persistentes, anillo de vidrio

## Fase 3 — Sesiones de código (15 %)
- [ ] `orbex-hook` + servidor de socket Unix (nunca bloquea a Claude Code)
- [ ] Instalador de hooks con backup + diff + desinstalar
- [ ] Sesiones en vivo, aprobar Permitir/Siempre/Denegar, preguntas
- [ ] Saltar a la terminal correcta (Terminal, iTerm2)
- [ ] Codex CLI (experimental)

## Fase 4 — Reloj y memoria (12 %)
- [ ] Reloj flotante: esferas Rolex, retro de pared, ORBIT futurista; morph notch↔reloj
- [ ] Acciones a hora puntual (planificador persistente)
- [ ] Memoria local editable

## Fase 5 — Temas (8 %)
- [ ] Sistema de skins (tema × esfera) con sonidos por tema
- [ ] macOS limpio
- [ ] Y2K metálico / Winamp

## Fase 6 — Integraciones (7 %)
- [ ] Spotify (AppleScript + baile por FFT del audio del sistema)
- [ ] GitHub, Vercel, Stripe, n8n, Resend, Notion, Cal.com (solo lectura, Keychain, interruptor)

## Cierre (3 %)
- [ ] Revisión completa del código
- [ ] Checklist de criterios de aceptación por fase
- [ ] Instrucciones finales de instalación

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
