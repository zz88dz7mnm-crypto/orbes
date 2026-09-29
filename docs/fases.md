# Fases y criterios de aceptación

Resumen del §15 del informe. El avance real se sigue en [`PLAN.md`](PLAN.md).

| Fase | Contenido | Criterio de aceptación |
|---|---|---|
| **0 — Preparación** | Repo, docs, estructura, referencias | Todo en `docs/` y `design/` |
| **1 — Núcleo visual** | Isla con estados y morph, ORBEX con vida, Liquid Glass, sonidos base, Configuración básica, `.dmg` + ícono + acceso directo + iniciar con la Mac | Ver abajo |
| **2 — Asistente y utilidades** | Panel del asistente (solo Claude vía `claude` local), abrir apps, notas, temporizadores y cronómetros | Responde con streaming; timers persisten; notas se guardan |
| **3 — Sesiones de código** | Hooks de Claude Code, aprobaciones, saltar a terminal; Codex si es viable | Aprobar/negar funciona y Claude Code nunca se bloquea |
| **4 — Reloj y memoria** | Reloj flotante, esferas, acciones programadas, memoria | Morph notch↔reloj fluido; acciones a hora exacta |
| **5 — Temas** | Y2K metálico/Winamp y macOS limpio, sistema de skins | Cambio de tema en vivo con sonidos propios |
| **6 — Integraciones** | Spotify, Stripe, n8n, GitHub, Vercel, Resend, Notion, Cal.com | Cada una apagable y con clave en Keychain |

## Checklist final de criterios de aceptación

`[x]` = implementado en el código · la prueba real se hace en la Mac (ver `INSTALAR.md`).

### Fase 1 — Núcleo visual
- [x] Mide el notch en vivo (`NSScreen.safeAreaInsets` + áreas auxiliares), con ajuste fino ±10/±6 pt.
- [x] En estados normales no supera notch + alitas; el asistente sí se ensancha.
- [x] Por encima de todo, incluidas apps a pantalla completa, en todos los escritorios.
- [x] Nunca se siente muerto: respiración, parpadeo, microgestos, sorpresas.
- [x] Estados oculto / asomado / trabajando / te necesita / abierto / dormido con resorte.
- [x] Monitor sin notch: notch simulado; se recoloca al cambiar resolución o pantallas.
- [x] Respeta reducir movimiento, reducir transparencia y claro/oscuro.
- [x] Consumo bajo en reposo: sondeo a 10 Hz oculto, motor de sonido en pausa, FPS limitados. *(medir en la Mac)*
- [x] Instalación: `install.sh` → Aplicaciones, `.dmg`, ícono, acceso directo, inicio con la Mac.
- [x] Configuración con vista previa en vivo.

### Fase 2 — Asistente y utilidades
- [x] Asistente solo con Claude vía `claude` local, con streaming; ORBEX naranja + Clawd.
- [x] Comandos en español; abrir apps con niveles de autonomía y lista permitida.
- [x] Timers y cronómetro persisten (hora de fin guardada); notas en Markdown o Apple Notas.

### Fase 3 — Sesiones de código
- [x] Aprobar / Siempre / Denegar desde el notch.
- [x] Claude Code nunca se bloquea (relé probado: sin ORBEX sale al instante con 0).
- [x] Instalador con backup + diff; desinstalar; saltar a la terminal.

### Fase 4 — Reloj y memoria
- [x] Morph notch ↔ reloj; 3 esferas; acciones a hora exacta; memoria editable.

### Fase 5 — Temas
- [x] Cambio de tema en vivo con sonidos propios (Liquid Glass, macOS limpio, Y2K).

### Fase 6 — Integraciones
- [x] Spotify + baile; GitHub, Vercel, Stripe, n8n, Resend, Notion, Cal.com: cada una apagable y con clave en el Keychain.
