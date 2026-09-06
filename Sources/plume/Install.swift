import ArgumentParser
import Foundation

enum InstallError: Error {
    /// Nothing executable at /usr/local/bin/plume and no usable argv[0]. The
    /// agent would name a binary that is not there.
    case binaryNotFound
}

/// Manage plume's LaunchAgent so the daemon starts at login.
///
/// We deliberately do NOT use SMAppService.mainApp here — that requires a full
/// .app bundle. Since plume ships as a single binary in /usr/local/bin, a
/// plain LaunchAgent plist is the simpler, more honest mechanism.
struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install or remove the launch-at-login LaunchAgent."
    )

    @Flag(name: .long, help: "Register plume to start at login.")
    var launchAtLogin: Bool = false

    @Flag(name: .long, help: "Remove the launch-at-login agent.")
    var uninstall: Bool = false

    @Flag(name: .long, help: "Keep daemon output in ~/Library/Logs/plume.log (mode 0600). Off by default; output is discarded.")
    var logFile: Bool = false

    @Flag(name: .long, help: "Delete the world-readable /tmp/parrot.{out,err}.log files left by earlier versions.")
    var purgeLegacyLogs: Bool = false

    @Option(name: .long, help: "Push-to-talk modifier to remember as the default.")
    var hotkey: HotkeyMonitor.Hotkey?

    @Option(name: .long, help: "Injection mode to remember as the default.")
    var injectMode: TextInjector.Mode?

    func run() throws {
        if launchAtLogin && uninstall {
            FileHandle.standardError.write(Data(
                "specify exactly one of --launch-at-login or --uninstall\n".utf8
            ))
            throw ExitCode(64)
        }
        if !launchAtLogin && !uninstall && !purgeLegacyLogs {
            FileHandle.standardError.write(Data(
                "specify exactly one of --launch-at-login or --uninstall\n".utf8
            ))
            throw ExitCode(64)
        }

        reportLegacyLogs()
        if purgeLegacyLogs {
            reportPurgedLegacyLogs()
        }

        // Recorded rather than baked into the agent's argv: a flag in
        // ProgramArguments wins over the remembered choice on every launch,
        // which would quietly undo anything picked in the menu bar.
        let settings = SettingsStore()
        if let hotkey { settings.hotkey = hotkey }
        if let injectMode { settings.injectMode = injectMode }

        do {
            if uninstall {
                let removed = try Install.removeAgent()
                print(removed
                    ? "✓ launch-at-login removed"
                    : "nothing to remove (no agent at \(Install.plistURL.path))")
            } else if launchAtLogin {
                try reportInstalled(Install.writeAgent(logFile: logFile))
            }
        } catch InstallError.binaryNotFound {
            FileHandle.standardError.write(Data(
                "couldn't locate the plume binary. install it to /usr/local/bin/plume first.\n".utf8
            ))
            throw ExitCode(1)
        }
    }

    private func reportInstalled(_ agent: Install.Agent) {
        let settings = SettingsStore()
        print("✓ launch-at-login installed")
        print("  plist:  \(agent.plistPath)")
        print("  binary: \(agent.binary)")
        print("  hotkey: \(settings.resolvedHotkey(flag: nil).rawValue)")
        print("  inject: \(settings.resolvedInjectMode(flag: nil).rawValue)")
        if logFile {
            print("  logs:   \(agent.logPath) (mode 0600)")
        } else {
            print("  logs:   discarded — pass --log-file to keep them")
        }
    }

    // MARK: -

    private static let label = "com.digimata.parrot"

    /// Applies to every file *and directory* the daemon creates, not just the
    /// log — launchd has no way to scope it. 0o077 gives files 0600 and
    /// directories 0700.
    ///
    /// It must keep the owner execute bit. 0o177 yields the same 0600 for
    /// files but 0600 for directories too, and a directory without `x` cannot
    /// be written into: the model downloader then fails every warmup with
    /// EACCES and `KeepAlive` turns that into a relaunch loop. That is what
    /// shipped from wave 1 until it was hit on a real install.
    static let logUmask = 0o077

    /// What `writeAgent` produced, so the caller can report it. The command
    /// prints these lines; the settings window shows the same facts as a row.
    struct Agent {
        let plistPath: String
        let binary: String
        let logPath: String
    }

    /// Shared with `DoctorReport.checkLaunchAgentArgs`, which reads the agent
    /// this writes.
    static var plistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.label).plist")
    }

    static var isAgentInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Writes the agent and bootstraps it. Prints nothing: both the command and
    /// the settings window call this, and only one of them has a terminal.
    @discardableResult
    static func writeAgent(logFile: Bool) throws -> Agent {
        let binary = try resolveBinaryPath()

        let logPath: String
        if logFile {
            logPath = try prepareLogFile()
        } else {
            logPath = "/dev/null"
        }

        // ProgramArguments deliberately omits --echo-transcripts: a background
        // daemon must never be configured to write transcript text to a log.
        // It also omits --hotkey and --inject-mode, which are remembered
        // instead, so the menu bar can change them and have it stick.
        var plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [binary, "run", "--skip-doctor"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false] as [String: Any],
            "ProcessType": "Interactive",
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
        ]
        if logFile {
            // launchd recreates a missing std-path file under its own umask
            // (0644), so the 0600 degrades the first time the log is deleted.
            plist["Umask"] = Self.logUmask
        }

        let url = Self.plistURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: .atomic)

        // Best-effort bootstrap; ignore failure if already loaded.
        _ = runLaunchctl(["bootout", "gui/\(uid())", url.path])
        let result = runLaunchctl(["bootstrap", "gui/\(uid())", url.path])
        if result.status != 0 {
            FileHandle.standardError.write(Data(
                "warning: launchctl bootstrap exited \(result.status):\n\(result.stderr)\n".utf8
            ))
        }

        return Agent(plistPath: url.path, binary: binary, logPath: logPath)
    }

    /// launchd appends to an existing std-path file and leaves its mode alone,
    /// but creates a missing one at 0644 — so create it 0600 before bootstrap.
    private static func prepareLogFile() throws -> String {
        let fm = FileManager.default
        let url = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
            .appendingPathComponent("plume.log")
        try fm.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fm.fileExists(atPath: url.path) {
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } else {
            _ = fm.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        }
        return url.path
    }

    /// Left as `parrot`, deliberately. These files were written by the old
    /// name; a plume path here would find nothing, and the people it would
    /// stop helping are precisely the ones migrating off parrot.
    static let legacyLogPaths = ["/tmp/parrot.out.log", "/tmp/parrot.err.log"]

    static func foundLegacyLogs() -> [String] {
        legacyLogPaths.filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Versions up to v0.0.5 pointed the daemon's stderr at /tmp and logged
    /// every transcript, so anyone who ran `--launch-at-login` has a plaintext
    /// record of everything they dictated, readable by any local user.
    private func reportLegacyLogs() {
        let fm = FileManager.default
        let found = Self.foundLegacyLogs()
        guard !found.isEmpty else { return }

        var msg = "\n⚠️  found logs from an earlier version, back when this was parrot:\n"
        for path in found {
            let attrs = try? fm.attributesOfItem(atPath: path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            msg += "     \(path) — \(size) bytes\n"
        }
        msg += "   these are world-readable and contain the text of every transcript\n"
        msg += "   it produced while the daemon was running.\n"
        if !purgeLegacyLogs {
            msg += "   review them, then delete with: plume install --purge-legacy-logs\n"
        }
        msg += "\n"
        FileHandle.standardError.write(Data(msg.utf8))
    }

    /// Deletes what it can and answers both halves, so the caller decides how
    /// to say it. Doctor flags these files; the settings window offers the same
    /// removal as the remediation for that check.
    static func purgeLegacyLogFiles() -> (removed: [String], failed: [String]) {
        let fm = FileManager.default
        var removed: [String] = []
        var failed: [String] = []
        for path in foundLegacyLogs() {
            do {
                try fm.removeItem(atPath: path)
                removed.append(path)
            } catch {
                failed.append(path)
                FileHandle.standardError.write(Data(
                    "couldn't remove \(path): \(error)\n".utf8
                ))
            }
        }
        return (removed, failed)
    }

    private func reportPurgedLegacyLogs() {
        let outcome = Self.purgeLegacyLogFiles()
        if outcome.removed.isEmpty && outcome.failed.isEmpty {
            print("no legacy /tmp logs to remove")
            return
        }
        for path in outcome.removed {
            print("✓ removed \(path)")
        }
    }

    /// Answers whether there was an agent to remove, so the caller can say so
    /// in its own words.
    @discardableResult
    static func removeAgent() throws -> Bool {
        let url = plistURL
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        _ = runLaunchctl(["bootout", "gui/\(uid())", url.path])
        try FileManager.default.removeItem(at: url)
        return true
    }

    private static func resolveBinaryPath() throws -> String {
        // /usr/local/bin/plume is the canonical install path. Honor a real
        // location if running from elsewhere (e.g. dev).
        let candidate = "/usr/local/bin/plume"
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        // Fall back to the running executable's resolved path.
        let argv0 = CommandLine.arguments.first ?? "plume"
        if argv0.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: argv0) {
            FileHandle.standardError.write(Data(
                "note: /usr/local/bin/plume not found; using \(argv0)\n".utf8
            ))
            return argv0
        }
        throw InstallError.binaryNotFound
    }

    private static func uid() -> uid_t { getuid() }

    private static func runLaunchctl(_ args: [String]) -> (status: Int32, stderr: String) {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = args
        let errPipe = Pipe()
        task.standardError = errPipe
        task.standardOutput = Pipe()
        do {
            try task.run()
        } catch {
            return (-1, "\(error)")
        }
        task.waitUntilExit()
        let err = String(
            data: errPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return (task.terminationStatus, err)
    }
}
