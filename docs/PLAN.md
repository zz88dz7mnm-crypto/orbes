# ORBEX — Plan de acción y avance

> Archivo vivo: se actualiza en cada push.
> **Avance total: 5 %** ▓░░░░░░░░░░░░░░░░░░░

Pesos: Fase 0 = 5 % · Fase 1 = 30 % · Fase 2 = 20 % · Fase 3 = 15 % · Fase 4 = 12 % · Fase 5 = 8 % · Fase 6 = 7 % · Cierre = 3 %.

Leyenda: `[x]` hecho y subido · `[~]` en curso · `[ ]` pendiente.

---

## Cómo retomar (si se corta la sesión)
1. Leé este archivo: lo marcado `[x]` ya está en el repo; `[~]` quedó a medias.
2. Mirá `git log --oneline -20` para ver lo último que se subió.
3. Seguí por el primer `[~]` o `[ ]` de la lista, respetando `CLAUDE.md`.
4. Reparto de trabajo en paralelo (subagentes):
   - **Principal:** `Sources/OrbexCore/` (salvo `Sessions/`), `Sources/Orbex/{App,Island,Character,Themes,Settings,Clock,Assistant}`, `docs/PLAN.md`.
   - **Subagente A (empaquetado):** `scripts/`, `.github/workflows/`.
   - **Subagente B (sesiones de código):** `Sources/orbex-hook/`, `Sources/OrbexCore/Sessions/`, `Sources/Orbex/Sessions/`, `Tests/OrbexCoreTests/Sessions*`.

## Fase 0 — Preparación (5 %) ✅
- [x] README, CLAUDE.md, LICENSE, .gitignore, .gitattributes
- [x] `docs/00-informe-completo.md`, `docs/decisiones.md`, `docs/fases.md`, `docs/PLAN.md`
- [x] `design/character/hoja-personaje.webp` + especificación del personaje
- [x] `design/references/coucou-notes.md` (estudio de la referencia)

## Fase 1 — Núcleo visual (30 %)
- [~] Package.swift + OrbexCore (estados, geometría de isla, motor de vida, expresiones) + tests
- [ ] Medición del notch, panel de la isla, morph con resorte, hover/clic, sin notch, cambio de resolución
- [ ] Personaje ORBEX por código (vidrio, ojos que siguen el cursor, brazos, piernas, poses, colores, clics/mareo, dormido)
- [ ] Tema Liquid Glass + reducir movimiento/transparencia + claro/oscuro; sonidos base sintetizados
- [ ] Configuración básica con vista previa; primer arranque (acceso directo, inicio con la Mac)
- [~] Ícono generado por código; scripts build/dmg/install; workflow manual de GitHub Actions (subagente A)

## Fase 2 — Asistente y utilidades (20 %)
- [ ] Panel del asistente (Claude + OpenAI por API, streaming, selector de modelo, Keychain, atajo global)
- [ ] Parser de comandos en español: abrir apps (allowlist), notas, temporizadores
- [ ] Temporizadores y cronómetro con vueltas, persistentes, anillo de vidrio

## Fase 3 — Sesiones de código (15 %)
- [~] `orbex-hook` + servidor de socket Unix (nunca bloquea a Claude Code)
- [~] Instalador de hooks con backup + diff + desinstalar
- [~] Sesiones en vivo, aprobar Permitir/Siempre/Denegar, preguntas
- [~] Saltar a la terminal correcta (Terminal, iTerm2)
- [~] Codex CLI (experimental) (subagente B, toda la Fase 3)

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
