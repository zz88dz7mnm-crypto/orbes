import Foundation

/// `Orbex --uninstall-hooks` (lo usa scripts/uninstall.sh): quita los hooks de ORBEX de
/// Claude Code y de Codex (con backup) y sale.
enum HooksCLI {
    static func uninstallAll() {
        do {
            if ClaudeHooksFile.isInstalled {
                try ClaudeHooksFile.uninstall()
                print("ORBEX: hooks quitados de \(ClaudeHooksFile.url.path) (quedó un backup al lado).")
            } else {
                print("ORBEX: no había hooks de ORBEX en Claude Code.")
            }
        } catch {
            print("ORBEX: no pude quitar los hooks de Claude Code: \(error.localizedDescription)")
        }
        do {
            if CodexHooksFile.isInstalled {
                try CodexHooksFile.uninstall()
                print("ORBEX: hooks quitados de \(CodexHooksFile.url.path).")
            }
        } catch {
            print("ORBEX: no pude quitar los hooks de Codex: \(error.localizedDescription)")
        }
    }
}
