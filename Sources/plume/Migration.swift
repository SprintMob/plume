import Foundation

/// Moving what parrot left behind to where plume looks for it.
///
/// Six places hold state, and a rename orphans all six: the launch agent, the
/// model weights, the capture cache, the log, the remembered choices, and the
/// old binary. The weights are the reason this exists rather than telling
/// people to download again; they run to gigabytes.
///
/// **Not on first launch.** The daemon runs under launchd with no terminal, no
/// way to report a partial failure and no way to ask a question, and it may
/// have been started by the *old* agent while this runs. Moving several
/// gigabytes is exactly the operation that must not be silent.
///
/// **Not in `doctor` either.** `doctor` is read-only by construction: it
/// returns `[Check]` and has no side effects. This follows the pattern the repo
/// already has, where `Doctor.checkLegacyLogs` detects and
/// `install --purge-legacy-logs` acts.
struct Migration {
    /// Every path the migration touches, injected so the whole thing can run
    /// against a temporary directory. `DoctorLaunchAgentTests` established the
    /// seam; this widens it.
    struct Paths {
        var legacyAgent: URL
        var legacyModels: URL
        var models: URL
        var legacyCaches: URL
        var caches: URL
        var legacyLog: URL
        var log: URL
        var legacyPreferences: URL
        var legacyBinary: URL
        var launchAgents: URL

        static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Paths {
            let library = home.appendingPathComponent("Library", isDirectory: true)
            let support = library.appendingPathComponent("Application Support", isDirectory: true)
            let caches = library.appendingPathComponent("Caches", isDirectory: true)
            let logs = library.appendingPathComponent("Logs", isDirectory: true)
            let launchAgents = library.appendingPathComponent("LaunchAgents", isDirectory: true)
            return Paths(
                legacyAgent: launchAgents.appendingPathComponent("\(Install.legacyLabel).plist"),
                legacyModels: support.appendingPathComponent("parrot", isDirectory: true),
                models: support.appendingPathComponent("plume", isDirectory: true),
                legacyCaches: caches.appendingPathComponent("parrot", isDirectory: true),
                caches: caches.appendingPathComponent("plume", isDirectory: true),
                legacyLog: logs.appendingPathComponent("parrot.log"),
                log: logs.appendingPathComponent("plume.log"),
                legacyPreferences: library
                    .appendingPathComponent("Preferences", isDirectory: true)
                    .appendingPathComponent("parrot.plist"),
                legacyBinary: URL(fileURLWithPath: "/usr/local/bin/parrot"),
                launchAgents: launchAgents
            )
        }
    }

    /// The keys carried across, assembled from the stores rather than listed
    /// here, so a store that gains a key gains migration with it.
    ///
    /// It has to be more than `SettingsStore`'s five. Losing `modelID` means
    /// re-downloading gigabytes of weights for the sake of one missing string,
    /// which is the whole failure this migration exists to avoid.
    enum Keys {
        static let all: [String] =
            SettingsStore.migratableKeys
            + ModelStore.migratableKeys
            + InputDeviceStore.migratableKeys
    }

    struct Report {
        /// What happened, in order, for the caller to print.
        var done: [String] = []
        /// What the user has to do themselves, because a GUI daemon must not
        /// attempt `sudo`.
        var manual: [String] = []
    }

    let paths: Paths
    let defaults: UserDefaults

    /// Both of these reach outside the process, and a test that booted a real
    /// launch agent out of the session running it, or registered one, would be
    /// worse than no test. Seams, not conveniences.
    let launchctl: ([String]) -> Void
    let registerAgent: (Bool) throws -> Install.Agent

    private let fm = FileManager.default

    init(
        paths: Paths = .standard(),
        defaults: UserDefaults = .standard,
        launchctl: @escaping ([String]) -> Void = { _ = Install.runLaunchctl($0) },
        registerAgent: @escaping (Bool) throws -> Install.Agent = Install.writeAgent(logFile:)
    ) {
        self.paths = paths
        self.defaults = defaults
        self.launchctl = launchctl
        self.registerAgent = registerAgent
    }

    /// True when there is anything at all to migrate. `doctor` asks the
    /// narrower question about the launch agent; this is what makes
    /// `--migrate` a no-op rather than a mess on a clean machine.
    var isNeeded: Bool {
        [paths.legacyAgent, paths.legacyModels, paths.legacyCaches,
         paths.legacyLog, paths.legacyPreferences]
            .contains { fm.fileExists(atPath: $0.path) }
    }

    /// Every precondition, checked before a single byte moves.
    ///
    /// The dangerous half-state is step 1 booting the old agent out and step 2
    /// then failing: the user is left with no daemon *and* no weights where the
    /// new binary looks. So everything that can be known in advance is known in
    /// advance, and a single failure aborts before any write.
    func preflight() -> [String] {
        var problems: [String] = []

        if fm.fileExists(atPath: paths.legacyModels.path),
           fm.fileExists(atPath: paths.models.path) {
            problems.append("""
                both \(paths.legacyModels.path) and \(paths.models.path) exist. \
                Merging two model roots is a question about data, not a rename: \
                move or delete one of them and run this again.
                """)
        }

        // A cross-volume move is a multi-gigabyte copy that can fill a disk;
        // a same-volume one is rename(2), which is atomic and instant. If this
        // takes minutes rather than milliseconds, this check is what failed.
        if fm.fileExists(atPath: paths.legacyModels.path),
           let from = device(of: paths.legacyModels),
           let to = device(of: paths.models.deletingLastPathComponent()),
           from != to {
            problems.append("""
                \(paths.legacyModels.path) and \(paths.models.path) are on \
                different volumes, so this would be a copy of every weight \
                rather than a rename. Move them by hand.
                """)
        }

        if fm.fileExists(atPath: paths.launchAgents.path),
           !fm.isWritableFile(atPath: paths.launchAgents.path) {
            problems.append("\(paths.launchAgents.path) is not writable")
        }

        if !fm.isExecutableFile(atPath: "/bin/launchctl") {
            problems.append("/bin/launchctl is missing")
        }

        return problems
    }

    /// Preconditions are the caller's job to check first. Steps are ordered so
    /// the only process that could write to anything below runs out first, and
    /// the agent is re-registered at the end **unconditionally**: a user left
    /// with a running daemon and no weights can download them again, a user
    /// left with neither cannot do anything.
    func run() throws -> Report {
        var report = Report()

        let keptLogs = bootOutLegacyAgent(&report)
        moveModels(&report)
        moveCaches(&report)
        moveLog(&report)
        movePreferences(&report)
        reportLegacyBinary(&report)

        do {
            let agent = try registerAgent(keptLogs)
            report.done.append("registered \(agent.plistPath) pointing at \(agent.binary)")
        } catch {
            report.manual.append("""
                could not register the new launch agent (\(error)). \
                Run `plume install --launch-at-login` once Plume.app is in place.
                """)
        }

        return report
    }

    // MARK: - 1. The launch agent

    /// First, because it is the only process that could still be writing to
    /// anything below. Answers whether `--log-file` was in effect, so the new
    /// agent is registered the way the old one was rather than resetting a
    /// choice the user made.
    private func bootOutLegacyAgent(_ report: inout Report) -> Bool {
        guard fm.fileExists(atPath: paths.legacyAgent.path) else { return false }

        var keptLogs = false
        if let data = try? Data(contentsOf: paths.legacyAgent),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let path = (plist as? [String: Any])?["StandardErrorPath"] as? String {
            keptLogs = path != "/dev/null"
        }

        launchctl(["bootout", "gui/\(getuid())/\(Install.legacyLabel)"])
        do {
            try fm.removeItem(at: paths.legacyAgent)
            report.done.append("removed the \(Install.legacyLabel) agent")
        } catch {
            report.manual.append("could not remove \(paths.legacyAgent.path): \(error)")
        }
        return keptLogs
    }

    // MARK: - 2. The weights

    private func moveModels(_ report: inout Report) {
        guard fm.fileExists(atPath: paths.legacyModels.path) else { return }
        do {
            try fm.createDirectory(
                at: paths.models.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fm.moveItem(at: paths.legacyModels, to: paths.models)
            report.done.append("moved the model weights to \(paths.models.path)")
        } catch {
            report.manual.append("""
                could not move \(paths.legacyModels.path) to \(paths.models.path): \(error). \
                The daemon will re-download what it needs.
                """)
        }
    }

    // MARK: - 3. The cache

    /// Holds `last-capture.wav` and nothing else. A debug artefact, not user
    /// data, so a failure to move it is a reason to delete it rather than a
    /// reason to stop.
    private func moveCaches(_ report: inout Report) {
        guard fm.fileExists(atPath: paths.legacyCaches.path) else { return }
        if (try? fm.moveItem(at: paths.legacyCaches, to: paths.caches)) != nil {
            report.done.append("moved the capture cache to \(paths.caches.path)")
        } else {
            try? fm.removeItem(at: paths.legacyCaches)
            report.done.append("removed the old capture cache")
        }
    }

    // MARK: - 4. The log

    private func moveLog(_ report: inout Report) {
        guard fm.fileExists(atPath: paths.legacyLog.path) else { return }
        guard !fm.fileExists(atPath: paths.log.path) else {
            report.manual.append("\(paths.log.path) already exists; \(paths.legacyLog.path) left alone")
            return
        }
        do {
            try fm.moveItem(at: paths.legacyLog, to: paths.log)
            // The mode travels with a rename, but say it out loud: this file
            // was world-readable once and that was a shipped privacy bug.
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.log.path)
            report.done.append("moved the log to \(paths.log.path) (mode 0600)")
        } catch {
            report.manual.append("could not move \(paths.legacyLog.path): \(error)")
        }
    }

    // MARK: - 5. The remembered choices

    /// Read out of the file and written through `UserDefaults`, not moved.
    /// `~/Library/Preferences/parrot.plist` belongs to `cfprefsd`, which caches
    /// it; moving it behind that daemon's back loses writes.
    ///
    /// Reading the file directly rather than `UserDefaults(suiteName: "parrot")`
    /// removes an uncertainty, and **step 1 is what makes that read safe**: the
    /// old daemon has been booted out, so no `cfprefsd` client is holding a
    /// newer copy.
    ///
    /// The legacy domain is deliberately **not** deleted. A few hundred bytes,
    /// and it is the only way to replay this if the new install is thrown away.
    private func movePreferences(_ report: inout Report) {
        guard let data = try? Data(contentsOf: paths.legacyPreferences),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any]
        else { return }

        var carried: [String] = []
        for key in Keys.all {
            // Idempotent, which is what makes a retry after a partial failure
            // safe: a key already migrated is never overwritten by a stale one.
            guard let value = dict[key], defaults.object(forKey: key) == nil else { continue }
            defaults.set(value, forKey: key)
            carried.append(key)
        }
        if carried.isEmpty {
            report.done.append("no remembered choices left to carry over")
        } else {
            report.done.append("carried over \(carried.joined(separator: ", "))")
        }
    }

    // MARK: - 6. The old binary

    /// Needs root, and a GUI daemon must not attempt `sudo`. Detect, print the
    /// command, and never fail the migration over it.
    private func reportLegacyBinary(_ report: inout Report) {
        guard fm.fileExists(atPath: paths.legacyBinary.path) else { return }
        report.manual.append("remove the old binary yourself: sudo rm \(paths.legacyBinary.path)")
    }

    // MARK: -

    /// `st_dev`, which is the thing `rename(2)` actually requires to match.
    /// Asking the filesystem directly beats any URL resource value here,
    /// because the question is precisely "is this one syscall or a multi-gig
    /// copy".
    private func device(of url: URL) -> dev_t? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return info.st_dev
    }
}
