# Contratos entre módulos — Etapa 2 (ORBEX sobre Coucou)

## Reglas comunes
- **Una fase a la vez.** Los subagentes trabajan SOLO en la fase actual y solo en sus archivos.
- **Sin pruebas durante las fases** (pedido del dueño): se escribe el código y se sube; como mucho
  `swiftc -parse`. Una pasada de verificación al final (E9).
- **Regla de corte:** terminar apenas los entregables estén subidos y revisados UNA vez. Sin extras.
- **Git:** commit + push de cada archivo o grupo chico (`git add <rutas>`); nunca `git add -A`,
  `checkout`, `restore`, `stash` ni borrar archivos ajenos. `git pull --rebase` antes de cada push.
- **Licencia:** el código de Coucou se reutiliza bajo MIT (`Sources/Orbex/Base/`, cabecera
  "Basado en Coucou © 2026 Louis Raillé — licencia MIT"). NUNCA sus assets (nombres Coucou/Mochi, el
  personaje Mochi —look, expresiones, animaciones—, íconos, sonidos, imágenes).
- Swift: tools 5.9, modo Swift 5, macOS 15. Llamar código `@MainActor` desde clausuras no aisladas
  (Timer, NotificationCenter, hilos) es ERROR: usar `MainActor.assumeIsolated {}` en el hilo principal
  o `Task { @MainActor in }`. `OrbexCore` solo importa Foundation (compila en Linux).
- Textos de UI en español rioplatense. Verificación de sintaxis:
  `docker run --rm -v /home/user/orbes:/src -w /src mirror.gcr.io/library/swift:6.1-noble swiftc -parse <archivo>`.

## Dueños de archivos por fase

| Fase | Quién | Archivos |
|---|---|---|
| E0, E1, E8, E9 | Principal | todo lo necesario para la fase |
| E2 | A · Motor | `Base/BotEngine.swift`, `Base/BotCanvasView.swift`, `Character/OrbexPainter.swift` |
| E2 | B · Saludo y subir | `Base/GreetingCanvasView.swift`, `Base/UploadCanvasView.swift`, `Base/UploadSequenceEngine.swift` |
| E3 | A · Animaciones | `Base/BotEngine.swift`, `Base/BotCanvasView.swift`, `Character/*`, `Base/IslandWindowController.swift` |
| E3 | B · Personalidad | `OrbexCore/Personality/*`, `Tests/OrbexCoreTests/Personality*`, `Base/PersonalityDirector.swift`, `Base/IslandRootView.swift` (solo el encabezado) |
| E4 | A · Sonidos | `System/SoundEngine.swift` |
| E4 | B · Español | textos en `Base/*.swift` excepto los de E4-A (sin tocar lógica) |
| E5 | A · Chat | `Base/IslandViewContent.swift`, `Assistant/*`, `Base/AppState.swift` (chat) |
| E5 | B · Utilidades | `Base/Views/*` (nuevos), `Base/IslandTypes.swift`, `Base/IslandRootView.swift`, `Utilities/*`, `Music/*` |
| E6 | A · Temas | `Themes/*` + estilos en `Base/IslandViewContent.swift` (`CardBackground`, botones, pastillas) |
| E6 | B · Sistema | `Base/IslandWindowController.swift`, `App/AppDelegate.swift`, `System/*` (menos SoundEngine), `Clock/*` |
| E7 | Sesiones | `Sessions/*`, `OrbexCore/Sessions/*`, vistas de aprobación/pregunta/terminado/error en `Base/IslandViewContent.swift` |

## Puentes y APIs clave
- `OrbexBus` (`App/OrbexBus.swift`): `play`, `react`, `setActivity`, `show`, `perform`, `requestTint`, `toast`.
- `OrbexBridge.shared` (`App/OrbexBridge.swift`, `@MainActor`): traduce el bus a la isla de la base y
  refleja `AppState.mode/view` en `AppModel.islandState`.
  - `attach(_ IslandWindowController)`, `updatePlacement()`.
  - `openIsland(_ view: IslandView? = nil)`, `close()`, `reveal()`, `show(page: IslandPage)`,
    `toggleAssistant()`, `toggleClock()`.
  - `showNote(_ text:, symbol:)`: aviso corto en la vista `note`; nunca tapa permiso/pregunta/chat.
  - `setAmbient(working:attention:sleepy:)` → `AppState.ambientState`; `react(_ OrbexReaction)` → emotes.
  - `AppState.autoCloseInterval` → `fsm.homeToPetitDelay` (mín. 5 s): "cerrarse sola" de Configuración › Isla.
- `SessionsBridge.shared` (`Sessions/SessionsBridge.swift`, `@MainActor`): sesiones de Claude Code → pastillas.
  - `start()` (lo llama el `AppDelegate`); una pastilla por sesión con id `"claude:" + sessionID`
    (`taskID(_:)`, `sessionID(fromTask:)`).
  - Permisos: `decide(_ ApprovalDecision)` (el primero de la cola; "Siempre" llega ya doblemente
    confirmado), `sendApprovalDecision("allow"|"deny"|"always")` (compatibilidad), `answerInTerminal()`.
  - `jumpToTerminal(sessionID: String? = nil)`, `openSessionsPage()`.
  - Consultas: `session(forTask:)`, `endedSession(for:)`, `task(forSession:)`; estáticos `pillName`,
    `botState`, `badge(for:)`, `color(for:)`, `durationText`, `lastPrompt`, `lastWork`.
- `PersonalityDirector.shared` (`Base/PersonalityDirector.swift`, `@MainActor`): `start()`/`stop()`;
  `@Published headerLine` (ya no se dibuja: la franja del notch queda vacía). Aplica lo que decide `PersonalityBrain` (OrbexCore)
  posteando `.triggerEmote`, `.botBlink`, `.botSetTgEs` y `.personalityGlance`. Sin permisos; timer de un
  disparo cada 2 s (5 s oculta, 8 s en bajo consumo).
- Notificaciones del personaje:
  - `.personalityGlance` — `userInfo`: `"dx"`/`"dy"` (`CGFloat`, −1…1, y hacia abajo), `"duration"`
    (`Double`, `0` = sostener hasta el próximo; `dx = dy = 0` suelta la mirada).
  - `.botPet` — `object`: `Bool` (empieza/termina la caricia; la postea `IslandWindowController` al
    dejar el mouse quieto sobre ORBEX, la escucha `BotCanvasView`).
  - `.triggerSlap` → cosquillas (`BotEngine.tickle()`; `slap()` queda como alias). `.triggerEmote` (`BotEmote`).
  - `.openFullSettings` — abre la ventana de Configuración (la vista `settings` de la isla la postea).
- `AppState.shared` (base): `mode`, `view`, `tasks`, `focusId`, `pendingApproval`, `noteMessage`,
  `noteSymbol`, `ambientState`, `soundEnabled`/`soundVolume` (sonido de la isla, en Configuración › Sonidos),
  `autoCloseInterval`, `activeIntegrations` (opcionales prendidas; por defecto ninguna) + `toggleIntegration(_:)`.
- Motor del personaje (`BotEngine`): API pública de Coucou intacta (`setState`, `triggerEmote`, `slap`,
  `blink`, `gulp`, `greet`, `anim`, `lookX/lookY`, `tgEs`, `morph`, `slotH*`, `bodyColor`, `isMini`, `draw…`),
  más `tickle()`.
- `SoundEngine.shared`:
  - `play(_ name: String)` — eventos de la isla por nombre ("peek", "open", "slap", "gulp", "love"…): cada
    uno de los 28 tiene su sonido sintetizado (`IslandSound`); nombres desconocidos no suenan. Respeta
    `AppState.soundEnabled`, el volumen relativo `soundVolume / 0,12` y los silencios por grupo
    (`SoundEngine.eventSounds` → `OrbexSound`).
  - `play(_ s: OrbexSound)` — sonidos de ORBEX por tema; `preview(_:theme:)` para Configuración.
- Configuración: `SettingsRootView` (secciones), `IntegrationsSettingsView` (`Base/SettingsView.swift`):
  integraciones opcionales Stripe, Cal.com y Notion (apagadas por defecto; su pastilla solo aparece si se
  prenden), claves solo en `KeychainStore` (`stripe-api-key`, `calcom-api-key`, `notion-api-key`). Resend,
  n8n, GitHub y Vercel se sacaron (Etapa 3), junto con la vista `mail`. Atajos fijos en
  `System/HotKeys.swift` (⌃⌥O/A/C/,).

## Etapa 3 — isla (V1/V2)
- **Tamaño de la isla: una sola fuente.** `islandSize(mode:view:progress:nw:nh:chatMessages:)`
  (`Base/IslandWindowController.swift`) + `IslandConst.chatHeight(messages:)`. La usan la forma y el
  contenido (`IslandGeometry` en `IslandContainer`), el área de clic (`IslandPanel.currentIslandFrame`) y el
  hit-test de ORBEX. Sin `@State` de tamaño: un solo resorte (`.animation(_:value: IslandGeometry)`) anima el
  morph; `setMode` ya no usa `withAnimation`. El contenido va recortado por la misma forma animada y entra con
  un fundido corto.
- **Encabezado:** la franja central (ancho del notch medido `state.notchWidth` + 12 pt por lado) queda vacía
  en todas las vistas; pestañas a la izquierda (se angostan si el notch es ancho), íconos a la derecha.
- **Isla compacta:** solo ORBEX a la izquierda; nada a la derecha del notch (sin mini-ORBEX ni textos).
- **Clic afuera:** monitor global de `leftMouseDown`/`rightMouseDown` en `IslandWindowController`: con la isla
  abierta, sin fijar (`isPinned`), sin arrastre de ORBEX ni de archivo, un clic fuera del rectángulo de la
  isla llama `collapse()`.
