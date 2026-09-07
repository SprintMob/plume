import ArgumentParser
import Foundation

enum InstallError: Error {
    /// No Plume.app anywhere and no usable executable to fall back on. The
    /// agent would name a binary that is not there.
    case binaryNotFound
}

/// Manage plume's LaunchAgent so the daemon starts at login.
///
/// Plume ships as a .app bundle now, so `SMAppService.mainApp` has become
/// available. It is still declined, for four reasons that are not the old one.
/// It gives no control over `KeepAlive: {SuccessfulExit: false}`, whose policy
/// is understood and deliberate, see the umask note below. It has no `Umask`
/// equivalent, and that was a shipped bug fixed on a real install. It cannot
/// set `ProcessType: Interactive`, which is what lets the daemon promote
/// itself to `.regular` under launchd and therefore what makes the settings
/// window work at all. And it has no `StandardOutPath`, which is the whole of
/// `--log-file` and the privacy argument around it. It also passes no
/// `ProgramArguments`, so `run --skip-doctor` is inexpressible.
///
/// See docs/adr/0008-ship-a-real-app-bundle.md.
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

    @Flag(name: .long, help: "Move models, settings, logs and the launch agent over from a parrot install.")
    var migrate: Bool = false

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
        if !launchAtLogin && !uninstall && !purgeLegacyLogs && !migrate {
            FileHandle.standardError.write(Data(
                "specify exactly one of --launch-at-login, --uninstall or --migrate\n".utf8
            ))
            throw ExitCode(64)
        }

        reportLegacyLogs()
        if purgeLegacyLogs {
            reportPurgedLegacyLogs()
        }
        if migrate {
            try runMigration()
            return
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
                reportWhatIsLeft()
            } else if launchAtLogin {
                try reportInstalled(Install.writeAgent(logFile: logFile))
            }
        } catch InstallError.binaryNotFound {
            FileHandle.standardError.write(Data(
                "couldn't find Plume.app. install it to /Applications or ~/Applications first.\n".utf8
            ))
            throw ExitCode(1)
        }
    }

    /// `--uninstall` removes the launch agent, which is all it has ever
    /// claimed to do. With a real .app there are two more things on disk and a
    /// directory of weights, and leaving someone to find those themselves is
    /// the kind of thing an open source release gets judged on. Printed rather
    /// than done: deleting an app and gigabytes of weights is a decision, and
    /// two of the three paths need root.
    private func reportWhatIsLeft() {
        let fm = FileManager.default
        var leftovers: [String] = []

        for bundle in Install.bundleSearchPaths where fm.fileExists(atPath: bundle) {
            let needsRoot = !fm.isWritableFile(atPath: (bundle as NSString).deletingLastPathComponent)
            leftovers.append("\(needsRoot ? "sudo " : "")rm -rf \(bundle)")
        }
        let shim = "/usr/local/bin/plume"
        if fm.fileExists(atPath: shim) {
            leftovers.append("sudo rm \(shim)")
        }
        let models = ModelWeights.root.path
        if fm.fileExists(atPath: models) {
            leftovers.append("rm -rf \(models)    # the downloaded models")
        }

        guard !leftovers.isEmpty else { return }
        print("\nstill on disk, if you want it gone:")
        for line in leftovers {
            print("  \(line)")
        }
    }

    /// Preconditions first, action second, and nothing in between. See
    /// `Migration` for why this is a command rather than something the daemon
    /// does at first launch or something `doctor` offers to fix.
    private func runMigration() throws {
        let migration = Migration()

        guard migration.isNeeded else {
            print("nothing to migrate: no parrot install found")
            return
        }

        let problems = migration.preflight()
        guard problems.isEmpty else {
            var msg = "migration stopped before moving anything:\n"
            for problem in problems {
                msg += "  ✗ \(problem)\n"
            }
            FileHandle.standardError.write(Data(msg.utf8))
            throw ExitCode(1)
        }

        let report = try migration.run()
        for line in report.done {
            print("✓ \(line)")
        }
        guard !report.manual.isEmpty else {
            print("\nmigration complete. run `plume doctor` to confirm.")
            return
        }
        print("\nstill to do, by hand:")
        for line in report.manual {
            print("  → \(line)")
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
            print("  logs:   discarded. pass --log-file to keep them")
        }
    }

    // MARK: -

    /// The bundle identifier, which is also the launchd label and the
    /// preferences domain. One string, and `packaging/Info.plist.in` is where
    /// it lives; the literal here is only the fallback for an unbundled
    /// development build.
    static let label = Bundle.main.bundleIdentifier ?? "com.sprintmob.plume"

    /// The label used before the rename. Kept indefinitely: it is the only way
    /// `doctor` can explain why two daemons are competing for the same event
    /// tap.
    static let legacyLabel = "com.digimata.parrot"

    static var legacyPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.legacyLabel).plist")
    }

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
            msg += "     \(path), \(size) bytes\n"
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

    /// The two places an installed Plume.app lives: system-wide, then the
    /// per-user one install-local.sh uses so a rebuild needs no sudo.
    static let bundleSearchPaths = [
        "/Applications/Plume.app",
        NSHomeDirectory() + "/Applications/Plume.app",
    ]

    /// The invariant this function exists to hold: **`ProgramArguments[0]` must
    /// be a path inside a `.app` bundle.** An unbundled binary takes its
    /// preferences domain from the process name rather than from
    /// `CFBundleIdentifier`, so the daemon would read a different domain than
    /// the one everything else writes, and every remembered choice made in the
    /// menu bar or the settings window would be invisible to it. That is a
    /// total, silent failure, and it is the mode ADR-0004 exists to prevent.
    /// `DoctorReport.checkLaunchAgentArgs` enforces it from the other side.
    ///
    /// `/usr/local/bin/plume` is deliberately absent from the list. It is a
    /// three-line shim that `exec`s the real binary: pointing launchd at it
    /// would have launchd supervise a `/bin/sh`, and would detach the TCC
    /// attribution from the bundle. The shim is for humans.
    static func resolveBinaryPath() throws -> String {
        let fm = FileManager.default

        // The bundle we are running from, whether that is /Applications,
        // ~/Applications or a dist/ directory in a checkout. It is the only
        // candidate that is certainly the code writing this agent.
        if Bundle.main.bundleURL.pathExtension == "app",
           let executable = Bundle.main.executableURL,
           fm.isExecutableFile(atPath: executable.path) {
            return executable.path
        }

        for bundle in bundleSearchPaths {
            let executable = bundle + "/Contents/MacOS/plume"
            if fm.isExecutableFile(atPath: executable) {
                return executable
            }
        }

        // Development: a bare SwiftPM build. Usable, and worth warning about,
        // because a daemon started from here has the process-name preferences
        // domain and none of the remembered choices reach it.
        let devBuild = FileManager.default.currentDirectoryPath + "/.build/release/plume"
        if fm.isExecutableFile(atPath: devBuild) {
            FileHandle.standardError.write(Data("""
                warning: no Plume.app found; pointing the agent at \(devBuild).
                         That binary is not bundled, so the daemon will use the
                         process-name preferences domain and ignore everything
                         you pick in the menu bar. Run ./scripts/install-local.sh.

                """.utf8))
            return devBuild
        }

        throw InstallError.binaryNotFound
    }

    private static func uid() -> uid_t { getuid() }

    /// Shared with `Migration`, which has to boot the pre-rename agent out
    /// before anything it could still be writing to is moved.
    static func runLaunchctl(_ args: [String]) -> (status: Int32, stderr: String) {
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
