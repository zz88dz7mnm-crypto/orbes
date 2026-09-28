import XCTest
@testable import OrbexCore

final class HookEventTests: XCTestCase {
    private func event(_ json: String) -> HookEvent? {
        HookEvent.parse(Data(json.utf8))
    }

    func testKindMapping() {
        XCTAssertEqual(HookEventKind(hookName: "SessionStart"), .sessionStart)
        XCTAssertEqual(HookEventKind(hookName: "PreToolUse"), .preToolUse)
        XCTAssertEqual(HookEventKind(hookName: "PostToolUseFailure"), .postToolUseFailure)
        XCTAssertEqual(HookEventKind(hookName: "PermissionRequest"), .permissionRequest)
        XCTAssertEqual(HookEventKind(hookName: "StopFailure"), .stopFailure)
        XCTAssertEqual(HookEventKind(hookName: "SubagentStop"), .subagentStop)
        XCTAssertEqual(HookEventKind(hookName: "PreCompact"), .unknown)
        XCTAssertEqual(HookEventKind(hookName: ""), .unknown)
        XCTAssertEqual(HookEventKind.userPromptSubmit.hookName, "UserPromptSubmit")
    }

    func testParseReadWithTerminalData() throws {
        let e = try XCTUnwrap(event("""
        {"session_id":"abc","cwd":"/Users/ana/proyectos/orbes","hook_event_name":"PreToolUse",
         "tool_name":"Read","tool_input":{"file_path":"/Users/ana/proyectos/orbes/Sources/main.swift"},
         "term_program":"iTerm.app","tty":"/dev/ttys003","bundle_id":"com.googlecode.iterm2",
         "iterm_session_id":"w0t0p0:XYZ","source":"claude"}
        """))
        XCTAssertEqual(e.kind, .preToolUse)
        XCTAssertEqual(e.sessionID, "abc")
        XCTAssertEqual(e.projectName, "orbes")
        XCTAssertEqual(e.toolName, "Read")
        XCTAssertEqual(e.toolInputSummary, "/Users/ana/proyectos/orbes/Sources/main.swift")
        XCTAssertEqual(e.stepDescription, "Lee main.swift")
        XCTAssertEqual(e.termProgram, "iTerm.app")
        XCTAssertEqual(e.tty, "/dev/ttys003")
        XCTAssertEqual(e.bundleID, "com.googlecode.iterm2")
        XCTAssertEqual(e.itermSessionID, "w0t0p0:XYZ")
        XCTAssertEqual(e.source, .claude)
    }

    func testStepDescriptions() throws {
        let bash = try XCTUnwrap(event(#"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"swift build"}}"#))
        XCTAssertEqual(bash.stepDescription, "Ejecuta `swift build`")
        let edit = try XCTUnwrap(event(#"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"/a/b/X.swift"}}"#))
        XCTAssertEqual(edit.stepDescription, "Edita X.swift")
        let grep = try XCTUnwrap(event(#"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Grep","tool_input":{"pattern":"TODO"}}"#))
        XCTAssertEqual(grep.stepDescription, "Busca \"TODO\"")
        let ask = try XCTUnwrap(event(#"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"¿Seguimos?","options":[{"label":"Sí"},{"label":"No"}]}]}}"#))
        XCTAssertEqual(ask.stepDescription, "Pregunta: ¿Seguimos?")
        XCTAssertTrue(ask.isQuestion)
        XCTAssertEqual(ask.questionOptions, ["Sí", "No"])
        let mcp = try XCTUnwrap(event(#"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"mcp__github__create_issue","tool_input":{}}"#))
        XCTAssertEqual(mcp.stepDescription, "Usa github · create_issue")
        let stop = try XCTUnwrap(event(#"{"session_id":"s","hook_event_name":"Stop"}"#))
        XCTAssertEqual(stop.stepDescription, "Listo")
    }

    func testLongCommandIsTrimmed() throws {
        let long = String(repeating: "x", count: 200)
        let e = try XCTUnwrap(event(#"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"\#(long)"}}"#))
        XCTAssertTrue(e.stepDescription.hasSuffix("…`"))
        XCTAssertLessThan(e.stepDescription.count, 80)
    }

    func testCodexSourceAndInvalidInput() {
        let e = event(#"{"session_id":"c1","hook_event_name":"Stop","source":"codex","cwd":"/tmp/app"}"#)
        XCTAssertEqual(e?.source, .codex)
        XCTAssertEqual(e?.projectName, "app")
        XCTAssertNil(event("no es json"))
        XCTAssertNil(event(#"{"hook_event_name":"Stop"}"#))
        XCTAssertNil(event(#"{"session_id":"x"}"#))
    }
}

final class SessionTrackerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func ev(_ kind: HookEventKind, _ id: String = "s1", tool: String? = nil,
                    arg: String? = nil, notification: String? = nil) -> HookEvent {
        HookEvent(kind: kind, sessionID: id, cwd: "/Users/ana/orbes", toolName: tool,
                  toolInputSummary: arg, notificationType: notification)
    }

    func testFullTurn() {
        var t = SessionTracker()
        XCTAssertEqual(t.apply(ev(.sessionStart), now: t0), [.started])
        XCTAssertEqual(t.sessions["s1"]?.status, .idle)
        XCTAssertEqual(t.sessions["s1"]?.project, "orbes")

        XCTAssertEqual(t.apply(ev(.userPromptSubmit), now: t0), [.step])
        XCTAssertEqual(t.sessions["s1"]?.status, .thinking)
        XCTAssertTrue(t.isWorking)

        XCTAssertEqual(t.apply(ev(.preToolUse, tool: "Read", arg: "/x/main.swift"), now: t0), [.step])
        XCTAssertEqual(t.sessions["s1"]?.status, .working)
        XCTAssertEqual(t.sessions["s1"]?.currentStep, "Lee main.swift")

        XCTAssertEqual(t.apply(ev(.stop), now: t0), [.finished])
        XCTAssertEqual(t.sessions["s1"]?.status, .finished)
        XCTAssertFalse(t.isWorking)

        t.tick(now: t0.addingTimeInterval(5))
        XCTAssertEqual(t.sessions["s1"]?.status, .finished)
        t.tick(now: t0.addingTimeInterval(6))
        XCTAssertEqual(t.sessions["s1"]?.status, .idle)
        t.tick(now: t0.addingTimeInterval(31 * 60))
        XCTAssertNil(t.sessions["s1"])
    }

    func testPermissionFlowIsIdempotent() {
        var t = SessionTracker()
        _ = t.apply(ev(.preToolUse, tool: "Bash", arg: "rm -rf build"), now: t0)
        XCTAssertEqual(t.apply(ev(.permissionRequest, tool: "Bash", arg: "rm -rf build"), now: t0), [.needsPermission])
        XCTAssertEqual(t.sessions["s1"]?.status, .needsPermission)
        XCTAssertTrue(t.needsAttention)
        // El mismo pedido otra vez no vuelve a avisar ni duplica el paso.
        let steps = t.sessions["s1"]?.steps.count
        XCTAssertEqual(t.apply(ev(.permissionRequest, tool: "Bash", arg: "rm -rf build"), now: t0), [])
        XCTAssertEqual(t.sessions["s1"]?.steps.count, steps)
        // Otra herramienta en paralelo no borra el pedido.
        _ = t.apply(ev(.postToolUse, tool: "Read", arg: "/a"), now: t0)
        XCTAssertEqual(t.sessions["s1"]?.status, .needsPermission)

        t.resolvePermission(sessionID: "s1", allowed: true)
        XCTAssertEqual(t.sessions["s1"]?.status, .working)
        XCTAssertFalse(t.needsAttention)
    }

    func testPostToolUseResolvesPendingPermission() {
        var t = SessionTracker()
        _ = t.apply(ev(.permissionRequest, tool: "Write", arg: "/a/b.txt"), now: t0)
        _ = t.apply(ev(.postToolUse, tool: "Write", arg: "/a/b.txt"), now: t0)
        XCTAssertEqual(t.sessions["s1"]?.status, .working)
    }

    func testDeniedGoesBackToThinking() {
        var t = SessionTracker()
        _ = t.apply(ev(.permissionRequest, tool: "Bash", arg: "ls"), now: t0)
        t.resolvePermission(sessionID: "s1", allowed: false)
        XCTAssertEqual(t.sessions["s1"]?.status, .thinking)
        XCTAssertEqual(t.sessions["s1"]?.currentStep, "Permiso denegado")
    }

    func testQuestionAndFailure() {
        var t = SessionTracker()
        XCTAssertEqual(t.apply(ev(.preToolUse, tool: "AskUserQuestion", arg: "¿A o B?"), now: t0), [.started, .question])
        XCTAssertEqual(t.sessions["s1"]?.status, .question)
        XCTAssertEqual(t.apply(ev(.stopFailure), now: t0), [.failed])
        XCTAssertEqual(t.sessions["s1"]?.status, .failed)
    }

    func testNotificationPermissionPrompt() {
        var t = SessionTracker()
        _ = t.apply(ev(.userPromptSubmit), now: t0)
        XCTAssertEqual(t.apply(ev(.notification, notification: "permission_prompt"), now: t0), [.needsPermission])
        XCTAssertEqual(t.apply(ev(.notification, notification: "idle_prompt"), now: t0), [])
    }

    func testSessionEndRemovesAndStepsAreCapped() {
        var t = SessionTracker()
        for i in 0..<30 {
            _ = t.apply(ev(.preToolUse, tool: "Read", arg: "/f\(i).swift"), now: t0)
        }
        XCTAssertEqual(t.sessions["s1"]?.steps.count, SessionTracker.maxSteps)
        XCTAssertEqual(t.sessions["s1"]?.currentStep, "Lee f29.swift")
        XCTAssertEqual(t.apply(ev(.sessionEnd), now: t0), [])
        XCTAssertNil(t.sessions["s1"])
    }

    func testSortedPutsAttentionFirst() {
        var t = SessionTracker()
        _ = t.apply(ev(.stop, "a"), now: t0)
        _ = t.apply(ev(.preToolUse, "b", tool: "Read", arg: "/x"), now: t0.addingTimeInterval(1))
        _ = t.apply(ev(.permissionRequest, "c", tool: "Bash", arg: "ls"), now: t0)
        XCTAssertEqual(t.sorted.map(\.id), ["c", "b", "a"])
    }
}

final class HooksInstallerTests: XCTestCase {
    let command = "\"/Users/ana/Library/Application Support/ORBEX/orbex-hook\""

    func testInstallKeepsForeignHooksAndUninstallRestores() {
        let foreign: [String: Any] = [
            "model": "opus",
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "say listo"]]]]],
        ]
        XCTAssertFalse(HooksInstaller.isInstalled(in: foreign))
        let installed = HooksInstaller.install(into: foreign, command: command)
        XCTAssertTrue(HooksInstaller.isInstalled(in: installed))
        XCTAssertEqual(installed["model"] as? String, "opus")
        let stop = (installed["hooks"] as? [String: Any])?["Stop"] as? [Any]
        XCTAssertEqual(stop?.count, 2)

        // Instalar dos veces no duplica.
        let twice = HooksInstaller.install(into: installed, command: command)
        XCTAssertEqual(HooksInstaller.prettyJSON(twice), HooksInstaller.prettyJSON(installed))

        let removed = HooksInstaller.uninstall(from: installed)
        XCTAssertFalse(HooksInstaller.isInstalled(in: removed))
        XCTAssertEqual(HooksInstaller.prettyJSON(removed), HooksInstaller.prettyJSON(foreign))
    }

    func testInstallIntoEmptyAndDiff() {
        let installed = HooksInstaller.install(into: nil, command: command)
        let text = HooksInstaller.prettyJSON(installed)
        XCTAssertTrue(text.contains("PermissionRequest"))
        XCTAssertTrue(text.contains("120"))
        let d = HooksInstaller.diff(old: "a\nb\nc", new: "a\nc\nd")
        XCTAssertEqual(d, "  a\n- b\n  c\n+ d")
    }

    func testCodexInstaller() {
        let installed = CodexHooksInstaller.install(into: nil, command: command + " --codex")
        XCTAssertTrue(CodexHooksInstaller.isInstalled(in: installed))
        XCTAssertFalse(CodexHooksInstaller.isInstalled(in: CodexHooksInstaller.uninstall(from: installed)))
    }

    func testPermissionReply() throws {
        let allow = PermissionReply.json(allow: true)
        XCTAssertFalse(allow.contains("\n"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(allow.utf8)) as? [String: Any])
        let out = try XCTUnwrap(obj["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(out["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual((out["decision"] as? [String: Any])?["behavior"] as? String, "allow")

        let deny = PermissionReply.json(allow: false, message: "No, gracias")
        XCTAssertTrue(deny.contains("\"deny\""))
        XCTAssertTrue(deny.contains("No, gracias"))
    }
}
