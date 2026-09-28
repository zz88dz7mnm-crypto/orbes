import AppKit
import OrbexCore

/// Salta a la terminal donde corre una sesión de Claude Code / Codex (informe §9.8).
/// Terminal.app e iTerm2 por AppleScript (buscando la tty); el resto activando la app por su bundle id.
enum TerminalJumper {

    static func jump(to s: SessionInfo) {
        let preferred = UserDefaults.standard.string(forKey: "orbex.sessions.terminal") ?? "auto"
        let program = (s.termProgram ?? "").lowercased()
        let bundle = (s.bundleID ?? "").lowercased()

        let wantsITerm = preferred == "iterm" || (preferred == "auto" && (program.contains("iterm") || bundle.contains("iterm")))
        let wantsTerminal = preferred == "terminal" || (preferred == "auto" && (program == "apple_terminal" || bundle == "com.apple.terminal"))

        if let tty = s.tty, !tty.isEmpty {
            if wantsITerm { runScript(itermScript(tty: tty), fallback: s); return }
            if wantsTerminal { runScript(terminalScript(tty: tty), fallback: s); return }
        }
        if !activateApp(bundleID: s.bundleID, termProgram: s.termProgram) {
            openFolder(s.cwd)
        }
    }

    // MARK: - AppleScript

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func terminalScript(tty: String) -> String {
        """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(escape(tty))" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return "ok"
                    end if
                end repeat
            end repeat
            activate
        end tell
        return "notfound"
        """
    }

    private static func itermScript(tty: String) -> String {
        """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(escape(tty))" then
                            select w
                            select t
                            select s
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
            activate
        end tell
        return "notfound"
        """
    }

    private static func runScript(_ source: String, fallback s: SessionInfo) {
        let bundleID = s.bundleID
        let program = s.termProgram
        let cwd = s.cwd
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let ok = error == nil && result?.stringValue == "ok"
            if !ok {
                DispatchQueue.main.async {
                    if !activateApp(bundleID: bundleID, termProgram: program) { openFolder(cwd) }
                }
            }
        }
    }

    // MARK: - Activar por bundle id

    /// Bundle ids conocidos según `TERM_PROGRAM`.
    private static func bundleID(forTermProgram p: String?) -> String? {
        switch (p ?? "").lowercased() {
        case "apple_terminal": return "com.apple.Terminal"
        case "iterm.app": return "com.googlecode.iterm2"
        case "vscode": return "com.microsoft.VSCode"
        case "warpterminal": return "dev.warp.Warp-Stable"
        case "ghostty": return "com.mitchellh.ghostty"
        case "wezterm": return "com.github.wez.wezterm"
        case "tmux": return nil
        default: return nil
        }
    }

    @discardableResult
    private static func activateApp(bundleID: String?, termProgram: String?) -> Bool {
        let candidates = [bundleID, Self.bundleID(forTermProgram: termProgram)].compactMap { $0 }.filter { !$0.isEmpty }
        for id in candidates {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                app.activate()
                return true
            }
        }
        return false
    }

    private static func openFolder(_ path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
