# Contratos entre módulos (para trabajar en paralelo)

Cada módulo es autocontenido. El agente principal los conecta en `AppModel`, la isla y Configuración.

## Reglas comunes
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

## Quién es dueño de qué
| Módulo | Rutas | Entrega para conectar |
|---|---|---|
| Principal | `Package.swift`, `OrbexCore/{Island,Character,Settings}`, `Orbex/{App,Island,Character,Themes,Settings,System}`, `docs/PLAN.md` | — |
| A · Empaquetado | `scripts/`, `.github/workflows/` | `install.sh`, `.dmg` |
| B · Sesiones de código | `orbex-hook/`, `OrbexCore/Sessions/`, `Orbex/Sessions/` | `HookServer.shared.start()`, `SessionsStore.shared` (`isWorking`, `needsAttention`, `onSignal`), `SessionsListView`, `ApprovalCardView`, `ClaudeCodeSettingsView`, `HooksCLI.uninstallAll()` |
| C · Utilidades | `OrbexCore/{Commands,Timers,Notes,Scheduler,Memory,Autonomy}/`, `Orbex/Utilities/` | `CommandParser.parse(_:now:)`, `CommandExecutor.shared.execute(_:)`, `TimersStore.shared`, `NotesStore.shared`, `SchedulerStore.shared`, `MemoryStore.shared`, vistas `TimersPageView`, `NotesPageView`, `TimerRingView`, secciones de Configuración |
| D · Asistente IA | `OrbexCore/Assistant/`, `Orbex/Assistant/` | `AssistantStore.shared`, `AssistantPanelView`, `AssistantSettingsView` |
| E · Reloj flotante | `OrbexCore/Clock/`, `Orbex/Clock/` | `ClockController.shared.show(from:)/hide()/isVisible`, `ClockSettingsView` |
| F · Integraciones | `OrbexCore/Integrations/`, `Orbex/Integrations/` | `IntegrationsHub.shared.start()`, `MusicStore.shared`, `MusicPageView`, `IntegrationsPageView`, `IntegrationsSettingsView`, `MusicStore.shared.isPlaying` (para el baile) |

## API acordada entre C y D (comandos)
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
