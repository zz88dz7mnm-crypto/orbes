# Fases y criterios de aceptación

Resumen del §15 del informe. El avance real se sigue en [`PLAN.md`](PLAN.md).

| Fase | Contenido | Criterio de aceptación |
|---|---|---|
| **0 — Preparación** | Repo, docs, estructura, referencias | Todo en `docs/` y `design/` |
| **1 — Núcleo visual** | Isla con estados y morph, ORBEX con vida, Liquid Glass, sonidos base, Configuración básica, `.dmg` + ícono + acceso directo + iniciar con la Mac | Ver abajo |
| **2 — Asistente y utilidades** | Panel del asistente (Claude/OpenAI por API), abrir apps, notas, temporizadores y cronómetros | Responde con streaming; timers persisten; notas se guardan |
| **3 — Sesiones de código** | Hooks de Claude Code, aprobaciones, saltar a terminal; Codex si es viable | Aprobar/negar funciona y Claude Code nunca se bloquea |
| **4 — Reloj y memoria** | Reloj flotante, esferas, acciones programadas, memoria | Morph notch↔reloj fluido; acciones a hora exacta |
| **5 — Temas** | Y2K metálico/Winamp y macOS limpio, sistema de skins | Cambio de tema en vivo con sonidos propios |
| **6 — Integraciones** | Spotify, Stripe, n8n, GitHub, Vercel, Resend, Notion, Cal.com | Cada una apagable y con clave en Keychain |

## Criterios de aceptación de la Fase 1

Se marcan cuando se prueban en la Mac (el código los implementa; la prueba real la hace el dueño).

- [ ] 1. Mide el notch en vivo y coincide con AppKit, con ajuste fino disponible.
- [ ] 2. En estados normales la isla no supera notch + alitas; el asistente sí puede ensancharse.
- [ ] 3. Queda por encima de otras apps, incluidas las de pantalla completa, en todos los escritorios.
- [ ] 4. Nunca se siente muerto: siempre hay al menos una animación en curso.
- [ ] 5. Todos los estados (oculto, asomado, trabajando, te necesita, abierto, dormido) transicionan con resorte.
- [ ] 6. Funciona en monitor externo sin notch (notch simulado) y al cambiar de resolución.
- [ ] 7. Respeta reducir movimiento, reducir transparencia y modo claro/oscuro.
- [ ] 8. Consumo bajo en reposo (medido y anotado).
- [ ] 9. Instalación completa: `.dmg` → Aplicaciones, ícono, acceso directo en el Escritorio, inicio con la Mac.
- [ ] 10. Configuración básica con vista previa en vivo.
