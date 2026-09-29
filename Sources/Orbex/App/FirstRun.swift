import AppKit
import SwiftUI
import OrbexCore

/// Ventana de bienvenida del primer arranque (informe §13.4–13.5): saludo de ORBEX, dónde vive,
/// atajos, acceso directo en el Escritorio, iniciar con la Mac y elección de tema.
/// También se puede abrir desde el menú ("Bienvenida…") con `show()`.
@MainActor
final class FirstRunWindowController {
    static let shared = FirstRunWindowController()

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    /// Muestra la bienvenida solo si todavía no se completó.
    func showIfNeeded() {
        guard !AppModel.shared.settings.firstRunDone else { return }
        show()
    }

    /// Muestra la bienvenida (la trae al frente si ya estaba abierta).
    func show() {
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let win = window ?? makeWindow()
        let model = AppModel.shared
        let settings = model.settings
        // Primera vez: acceso directo prendido por defecto (se crea recién al tocar "¡Listo!").
        let initialShortcut = settings.firstRunDone ? (settings.desktopShortcut || DesktopShortcut.exists) : true
        let root = FirstRunView(model: model,
                                initialShortcut: initialShortcut,
                                initialLaunchAtLogin: settings.launchAtLogin,
                                onDone: { FirstRunWindowController.shared.close() })
            .environment(\.hostWindow, HostWindowRef(win))
        win.contentView = NSHostingView(rootView: root)
        win.center()
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    // MARK: - Internos

    private func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                           styleMask: [.titled, .closable, .fullSizeContentView],
                           backing: .buffered,
                           defer: false)
        win.title = "Bienvenida a ORBEX"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.tabbingMode = .disallowed
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = .black
        win.collectionBehavior = [.moveToActiveSpace]
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                               object: win, queue: .main) { _ in
            MainActor.assumeIsolated {
                FirstRunWindowController.shared.windowWillClose()
            }
        }
        window = win
        return win
    }

    private func windowWillClose() {
        // Cerrar la ventana cuenta como "ya la vi": no vuelve a aparecer sola en cada arranque.
        if !AppModel.shared.settings.firstRunDone {
            AppModel.shared.settings.firstRunDone = true
        }
        // Soltar el contenido para que la animación de ORBEX no gaste CPU con la ventana cerrada.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let controller = FirstRunWindowController.shared
                guard let win = controller.window, !win.isVisible else { return }
                win.contentView = NSView()
            }
        }
    }
}

/// Contenido de la bienvenida.
@MainActor
struct FirstRunView: View {
    @ObservedObject private var model: AppModel
    @State private var createShortcut: Bool
    @State private var launchAtLogin: Bool
    private let onDone: () -> Void

    init(model: AppModel, initialShortcut: Bool, initialLaunchAtLogin: Bool, onDone: @escaping () -> Void) {
        _model = ObservedObject(wrappedValue: model)
        _createShortcut = State(initialValue: initialShortcut)
        _launchAtLogin = State(initialValue: initialLaunchAtLogin)
        self.onDone = onDone
    }

    var body: some View {
        let theme = model.themeStyle
        VStack(spacing: 12) {
            OrbexView(showLimbs: true, paused: false, fps: model.characterFPS)
                .frame(width: 120, height: 120)
                .padding(.top, 14)

            VStack(spacing: 6) {
                Text("¡Hola! Soy ORBEX")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.text)
                Text("Vivo en el notch de tu Mac. Pasá el mouse por arriba y me asomo; hacé clic y me abro. También me encontrás en la barra de menú.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            shortcutsRow

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Crear acceso directo en el Escritorio", isOn: $createShortcut)
                Toggle("Iniciar ORBEX con la Mac", isOn: $launchAtLogin)
                HStack {
                    Text("Tema")
                    Spacer(minLength: 12)
                    Picker("Tema", selection: $model.settings.theme) {
                        ForEach(ThemeID.allCases, id: \.self) { id in
                            Text(id.label).tag(id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 270)
                }
            }
            .toggleStyle(.switch)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(theme.text)
            .padding(14)
            .orbexCard(cornerRadius: 14)

            Text("Podés cambiar todo esto cuando quieras en Configuración.")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(theme.tertiaryText)

            Spacer(minLength: 0)

            Button {
                finish()
            } label: {
                Text("¡Listo!")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(theme.accent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(width: 460, height: 520)
        .background(Color.black)
        .tint(theme.accent)
        .environment(\.orbexTheme, theme)
        .preferredColorScheme(.dark)
        .onAppear {
            CharacterBrain.shared.greet()
            OrbexBus.play(.greet)
        }
        .onChange(of: model.settings.theme) { _, newTheme in
            SoundEngine.shared.preview(.answered, theme: newTheme)
        }
    }

    /// Atajos globales (los mismos que registra `OrbexHotKeys`).
    private var shortcutsRow: some View {
        let theme = model.themeStyle
        let items = OrbexHotKeys.descriptions
        return HStack(spacing: 8) {
            ForEach(0..<items.count, id: \.self) { i in
                VStack(spacing: 2) {
                    Text(items[i].0)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.accent)
                    Text(items[i].1)
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .orbexCard(cornerRadius: 10)
            }
        }
    }

    private func finish() {
        var s = model.settings
        s.desktopShortcut = createShortcut
        s.launchAtLogin = launchAtLogin
        s.firstRunDone = true
        // AppModel aplica los cambios (crea/quita el alias, registra el inicio con la Mac).
        model.settings = s
        if createShortcut && !DesktopShortcut.exists {
            DesktopShortcut.create()
        }
        OrbexBus.react(.celebrate)
        OrbexBus.play(.sessionDone)
        // Mostrar dónde vive ORBEX: sale del notch y saluda.
        OrbexBridge.shared.island?.fsm.launch()
        onDone()
    }
}
