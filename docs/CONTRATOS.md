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
  `App/OrbexBridge.swift` los conecta con `AppState`/`IslandWindowController` de Coucou.
- `AppState.shared` (Coucou): `mode`, `view`, `tasks`, `focusId`, `pendingApproval`, `noteMessage`…
- Motor del personaje (`BotEngine`): API pública de Coucou intacta (`setState`, `triggerEmote`, `slap`,
  `blink`, `gulp`, `greet`, `anim`, `lookX/lookY`, `tgEs`, `morph`, `slotH*`, `bodyColor`, `isMini`, `draw…`).
- `SoundEngine.shared.play(_ name: String)` (nombres de Coucou) y `play(_ s: OrbexSound)` (ORBEX).
