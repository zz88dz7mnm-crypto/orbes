# Contratos entre módulos (para trabajar en paralelo)

Cada módulo es autocontenido. El agente principal los conecta en `AppModel`, la isla y Configuración.

## Reglas comunes
- **Sin pruebas en el medio (pedido del dueño):** se codea y se sube; nada de `swift test` ni iterar sobre errores durante las fases. Al final del proyecto hay UNA pasada de corrección de errores.
- **Regla de corte (ahorro de tokens):** cada subagente termina apenas sus entregables están subidos y revisados UNA vez (`swiftc -parse` + lectura propia). Sin extras, sin pulir en bucle, sin esperar a otros agentes.
- Verificación disponible en la nube: Docker con Swift 6.1 (`mirror.gcr.io/library/swift:6.1-noble`): `swiftc -parse <archivo>` para la app; `swift test` para `OrbexCore` (copiando `Sources/OrbexCore` + `Tests/` a un paquete aparte).
- Swift 5 language mode (tools 5.9), macOS 14 mínimo, sin dependencias externas. **No se puede compilar en la nube**: revisar cada firma de API a mano.
- ⚠️ No usar nombres que choquen con Foundation/SwiftUI: `Expression`, `Predicate`, `Timer` (usar `OrbexTimer`), `Notification`, `Task`, `Color`, `Font`, `Text`, `Image`, `Label`, `Section`, `Group`, `Link`, `Menu`, `Picker`, `Toggle`, `Stepper`, `Gauge`, `Grid`.
- `OrbexCore` solo importa Foundation y debe compilar en Linux. Lógica ahí + pruebas XCTest.
- Stores de la app: `@MainActor final class XStore: ObservableObject` con `static let shared`. Si un callback viene de otro hilo, volver con `DispatchQueue.main.async { ... }` y, adentro, `MainActor.assumeIsolated { ... }` si hace falta tocar cosas `@MainActor`.
- Claves: `Keychain.get/set` (`Sources/Orbex/System/Keychain.swift`). Rutas: `AppPaths` (`Sources/Orbex/System/AppPaths.swift`). Ajustes propios del módulo: `UserDefaults.standard` con claves `orbex.<módulo>.<clave>`.
- Avisos a la app: `OrbexBus` (`Sources/Orbex/App/OrbexBus.swift`): `play(.timerDone)`, `react(.celebrate)`, `setActivity(source:working:attention:)`, `show(.timers)`, `perform("assistant")`, `requestTint(.green, source:)`, `toast("Nota guardada")`.
- Estilo: fondo de la isla negro, texto blanco, SF Rounded 10–13 pt. Tarjetas con `.orbexCard(cornerRadius:)`, botones con `OrbexActionButton` (en `Themes/Glass.swift`). Tema actual: `@Environment(\.orbexTheme)` (`accent`, `secondaryText`, `spring`).
- Personaje: `OrbexView(showLimbs:paused:fps:)` y `CharacterBrain.shared` (`celebrate()`, `worry()`, `show(.happy, for: 2)`).
- Tamaños: página de la isla abierta ≈ **270 × 230 pt**; panel del asistente ≈ **460 × 520 pt** (variable).
- Autosave: commit + push de **tus rutas** después de cada archivo o grupo chico (`git add <rutas>`; nunca `git add -A`). `git pull --rebase` antes del push; si hay `index.lock`, esperar 2 s y reintentar.

## Fase 3 — Sesiones de código (cerrada)

| Quién | Rutas | Entrega |
|---|---|---|
| F3-A · Hooks | `orbex-hook/`, `OrbexCore/Sessions/`, `Orbex/Sessions/{HookServer,HooksFiles,HooksCLI}.swift` | relé, servidor de socket, instalador con diff |
| F3-B · Sesiones UI | `Orbex/Sessions/{SessionsStore,TerminalJumper,SessionsViews,ClaudeCodeSettingsView}.swift` | store, aprobaciones, saltar a la terminal, vistas |

## Fase 2 — Asistente y utilidades (cerrada)

| Quién | Rutas | Entrega |
|---|---|---|
| Principal | integración en la isla (páginas Timers/Notas, panel del asistente), Configuración, `docs/` | — |
| F2-A · Utilidades | `OrbexCore/{Commands,Timers,Notes,Autonomy}/`, `Orbex/Utilities/` | `CommandParser`, `CommandExecutor`, `TimersStore`, `NotesStore`, `AppLauncher`, vistas y secciones de Configuración |
| F2-B · Asistente | `OrbexCore/Assistant/`, `Orbex/Assistant/` | `ClaudeCLI`, `AssistantStore`, `AssistantPanelView`, `ClaudePetView` (Clawd), `AssistantSettingsView` |

## Fase 1 — Núcleo visual (cerrada, en revisión final)
Regla: una fase a la vez. Los subagentes trabajan SOLO en la fase actual.

| Quién | Rutas | Entrega |
|---|---|---|
| Principal | `Package.swift`, `OrbexCore/`, `Orbex/{Island,Character,Themes}`, `Orbex/App/{AppModel,AppDelegate,OrbexBus,main}.swift`, `Orbex/System/{NotchDetector,Keychain,AppPaths}.swift`, `docs/` | Isla, personaje, conexión |
| F1-A · Empaquetado | `scripts/`, `.github/workflows/` | `install.sh`, `build-app.sh`, `make-dmg.sh`, `uninstall.sh`, ícono, workflow manual |
| F1-B · Servicios del sistema | `Orbex/System/{SoundEngine,HotKeys,LaunchAtLogin,DesktopShortcut,StatusBarIcon}.swift`, `Orbex/App/FirstRun*.swift` | `SoundEngine.shared.play(_:)`, `HotKeyCenter`, `LaunchAtLogin.set/isEnabled`, `DesktopShortcut.create/remove/exists`, `StatusBarIcon.image()`, `FirstRunWindowController.shared.showIfNeeded()` |
| F1-C · Configuración | `Orbex/Settings/` | `SettingsWindowController.shared.show()` con vista previa en vivo |

## Fases siguientes (referencia, NO empezar hasta cerrar la anterior)
| Fase | Módulo | Rutas | Entrega |
|---|---|---|---|
| 2 | Utilidades | `OrbexCore/{Commands,Timers,Notes,Autonomy}/`, `Orbex/Utilities/` | `CommandParser`, `CommandExecutor`, `TimersStore`, `NotesStore`, vistas |
| 2 | Asistente (solo Claude vía CLI `claude` local, naranja + mascota Clawd) | `OrbexCore/Assistant/`, `Orbex/Assistant/` | `AssistantStore.shared`, `AssistantPanelView`, `AssistantSettingsView` |
| 3 | Sesiones de código | `orbex-hook/`, `OrbexCore/Sessions/`, `Orbex/Sessions/` | `HookServer`, `SessionsStore`, vistas, instalador de hooks (ignora `ORBEX_INTERNAL=1`) |
| 4 | Reloj + planificador + memoria | `OrbexCore/{Clock,Scheduler,Memory}/`, `Orbex/Clock/` | `ClockController`, `SchedulerStore`, `MemoryStore` |
| 5 | Temas | `Orbex/Themes/` | skins + packs de sonido |
| 6 | Integraciones | `OrbexCore/Integrations/`, `Orbex/Integrations/` | `IntegrationsHub`, `MusicStore`, vistas |

## API acordada para la Fase 2 (comandos ↔ asistente)
```swift
// OrbexCore/Commands/CommandParser.swift
public enum OrbexCommand: Equatable, Sendable {
    case openApp(name: String)
    case openFolder(path: String)
    case note(text: String)
    case timer(seconds: TimeInterval, label: String?)
    case stopwatch
    case pomodoro
    case remind(at: Date, text: String)
    case scheduledAction(at: Date, actionName: String)
    case remember(fact: String)
    case showClock
}
public enum CommandParser {
    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> OrbexCommand?
}
// Orbex/Utilities/CommandExecutor.swift
struct CommandResult { let message: String; let needsConfirmation: Bool }
@MainActor final class CommandExecutor {
    static let shared: CommandExecutor
    func execute(_ command: OrbexCommand) async -> CommandResult
    func confirmPending() async -> CommandResult   // ejecuta lo que pidió confirmación
    func cancelPending()
}
// El asistente puede leer la memoria para dar contexto:
// MemoryStore.shared.facts: [String]
```
