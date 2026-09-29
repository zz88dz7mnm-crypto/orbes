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

---

## Etapa 2 — ORBEX sobre la base de Coucou (E0–E9)

`[x]` = implementado en el código · `[ ]` = falta. Todo lo de la app (AppKit/SwiftUI) solo pasó
`swiftc -parse`: **la prueba real es en la Mac** (lista al final). Avance y pesos: [`PLAN.md`](PLAN.md).

### E0 · Preparación
- [x] `THIRD_PARTY_NOTICES.md` (MIT de Coucou, sin assets), regla 13 en `CLAUDE.md`, decisiones, contratos, plan.

### E1 · Cascarón de Coucou
- [x] Código de Coucou en `Sources/Orbex/Base/` con cabecera MIT; ningún asset (nombres, Mochi, íconos, sonidos, imágenes).
- [x] Duplicados retirados, choques de nombres resueltos, marca ORBEX, `Package.swift` macOS 15.
- [x] `AppDelegate` único + `OrbexBridge` + `SoundEngine.play(nombre)`.

### E2 · Personaje ORBEX en el motor
- [x] `BotEngine` dibuja ORBEX con la misma API; mini-ORBEX; portal de vidrio.
- [x] Saludo propio y "tragar archivo" propio.

### E3 · Animaciones y personalidad
- [x] Caricia (`.botPet`), cosquillas (3 clics = mareo), timidez, globo al arrastrar, animaciones por estado, despertar, idles raros.
- [x] `PersonalityDirector`: saludo por nombre y hora, "te extrañé", rachas, frases, te ve tipear (`.personalityGlance`), mira la app nueva.

### E4 · Sonidos y español
- [x] 28 eventos de la isla con sonido sintetizado propio (`IslandSound`), por tema; silencios por grupo.
- [x] Textos de la UI de Coucou al español rioplatense (en curso en paralelo: revisar que no quede inglés).

### E5 · Asistente y utilidades
- [x] Chat de la isla con `claude` local (streaming), Clawd, ORBEX naranja, comandos, memoria.
- [x] Pestañas Timers, Notas y Música; avisos → vista nota; botón de reloj.

### E6 · Temas, reloj y sistema
- [x] Tarjetas, botones y pastillas con los 3 temas (Liquid Glass, macOS limpio, Y2K).
- [x] Notch configurable, reloj flotante, bienvenida, atajos fijos ⌃⌥O/A/C/,, inicio con la Mac, acceso directo (en curso en paralelo).

### E7 · Sesiones de Claude Code
- [x] Una pastilla por sesión, cola de permisos, "Siempre" con doble confirmación, pregunta/terminado/error reales, saltar a la terminal, limpieza de hooks viejos de Coucou.

### E8 · Configuración, empaquetado y docs
- [x] Configuración › Integraciones en español con Form/Section (claves en Keychain, filtros Vercel/n8n, máx. 4 pastillas); sonido de la isla → Sonidos; "cerrarse sola" → Isla; sin atajo configurable.
- [x] `Info.plist`: macOS 15, textos de Accesibilidad (título de la ventana) y Automatización (terminal, Mail, Spotify, Notas).
- [x] README, INSTALAR (primera vez / actualizar + prompt para Claude), fases, contratos.
- [x] `scripts/actualizar.sh`: instala encima, borra app/compilados/hooks viejos (con diff + backup), no toca tus datos.

### E9 · Verificación
- [ ] Pruebas de `OrbexCore`, sintaxis de toda la app, chequeo de símbolos, revisores.

### Qué falta probar en la Mac
- [ ] `bash scripts/actualizar.sh` sobre una instalación vieja: compila, instala y abre; no pierde notas/ajustes/claves.
- [ ] La isla calza con el notch real (y el simulado en un monitor externo); morph con resorte entre estados.
- [ ] Caricia, cosquillas/mareo, arrastrar sobre una ventana (pide Accesibilidad la primera vez y toma el título), soltar archivo.
- [ ] Sesión real de Claude Code: permiso Aprobar/Siempre/Denegar, pregunta, terminado; con ORBEX cerrado no se bloquea.
- [ ] Chat con `claude` local, timers, notas, música, reloj ⌃⌥C, cambio de tema en vivo con sus sonidos.
- [ ] Configuración: guardar/borrar claves (Keychain), filtros Vercel/n8n, límite de 4 pastillas, volumen de la isla, "cerrarse sola".
- [ ] Mandar un mail desde la isla (pide Automatización de Mail) y saltar a la terminal.
- [ ] CPU casi 0 % con la isla oculta; Modo de bajo consumo y "reducir movimiento".
