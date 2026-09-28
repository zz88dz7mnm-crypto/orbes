# ORBEX — Plan de acción y avance

> Archivo vivo: se actualiza en cada push.
> **Avance total: 3 %** ▓░░░░░░░░░░░░░░░░░░░

Pesos: Fase 0 = 5 % · Fase 1 = 30 % · Fase 2 = 20 % · Fase 3 = 15 % · Fase 4 = 12 % · Fase 5 = 8 % · Fase 6 = 7 % · Cierre = 3 %.

Leyenda: `[x]` hecho y subido · `[~]` en curso · `[ ]` pendiente.

---

## Fase 0 — Preparación (5 %)
- [~] README, CLAUDE.md, LICENSE, .gitignore, .gitattributes
- [~] `docs/00-informe-completo.md`, `docs/decisiones.md`, `docs/fases.md`, `docs/PLAN.md`
- [~] `design/character/hoja-personaje.webp` + especificación del personaje
- [~] `design/references/coucou-notes.md` (estudio de la referencia)

## Fase 1 — Núcleo visual (30 %)
- [ ] Package.swift + OrbexCore (estados, geometría de isla, motor de vida, expresiones) + tests
- [ ] Medición del notch, panel de la isla, morph con resorte, hover/clic, sin notch, cambio de resolución
- [ ] Personaje ORBEX por código (vidrio, ojos que siguen el cursor, brazos, piernas, poses, colores, clics/mareo, dormido)
- [ ] Tema Liquid Glass + reducir movimiento/transparencia + claro/oscuro; sonidos base sintetizados
- [ ] Configuración básica con vista previa; primer arranque (acceso directo, inicio con la Mac)
- [ ] Ícono generado por código; scripts build/dmg/install; workflow manual de GitHub Actions

## Fase 2 — Asistente y utilidades (20 %)
- [ ] Panel del asistente (Claude + OpenAI por API, streaming, selector de modelo, Keychain, atajo global)
- [ ] Parser de comandos en español: abrir apps (allowlist), notas, temporizadores
- [ ] Temporizadores y cronómetro con vueltas, persistentes, anillo de vidrio

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
