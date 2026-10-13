import AVFoundation
import AppKit
import ApplicationServices
import Foundation

enum CheckStatus {
    case ok
    case warn(String)
    case fail(String)
}

struct Check {
    let name: String
    let status: CheckStatus
    let remediation: String?
}

enum DoctorReport {
    /// `hotkey` is required rather than defaulted so no caller can quietly
    /// assume Fn: the Fn mapping is only worth checking when Fn is the modifier
    /// actually being watched, and its failures otherwise block startup for a
    /// user who never asked for it.
    static func run(hotkey: HotkeyMonitor.Hotkey) -> [Check] {
        var checks = [
            checkMicrophone(hotkey: hotkey),
            checkAccessibility(),
        ]
        if hotkey == .fn {
            checks.append(checkFnKeyMapping())
        }
        checks.append(checkLegacyLogs())
        checks.append(checkLaunchAgentArgs())
        checks.append(checkLegacyLaunchAgent())
        return checks
    }

    /// The pre-rename agent, left behind by an install that has not migrated.
    /// Two agents each holding a `CGEventTap` on the same modifier is a tap
    /// collision, and nothing else in the app is in a position to say so.
    ///
    /// This detects; `install --migrate` acts. Same split as `checkLegacyLogs`
    /// and `install --purge-legacy-logs`, and for the same reason: `doctor` is
    /// read-only by construction, and moving gigabytes of weights is not
    /// something to do as a side effect of a status command.
    static func checkLegacyLaunchAgent(at url: URL = Install.legacyPlistURL) -> Check {
        let name = "legacy launch agent"
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Check(name: name, status: .ok, remediation: nil)
        }
        return Check(
            name: name,
            status: .warn("\(Install.legacyLabel) is still registered. Two daemons will fight over the event tap"),
            remediation: "run `plume install --migrate`"
        )
    }

    /// Versions up to v0.0.6 baked --hotkey and --inject-mode into the launch
    /// agent's ProgramArguments. A flag still wins over the remembered choice,
    /// so an agent left from one of those installs silently overrides every
    /// pick made in the menu bar or the settings window.
    ///
    /// --no-overlay and --mute-output joined the list when they became
    /// remembered choices too: hand-edited agents carry them, and they fail the
    /// same way.
    ///
    /// Two more checks arrived with the .app bundle, both on
    /// `ProgramArguments[0]`. They are reported before the stale-flag warning
    /// because either one means the agent is not running plume at all, which
    /// makes a note about flag precedence beside the point.
    static func checkLaunchAgentArgs(at url: URL = Install.plistURL) -> Check {
        let name = "launch agent"
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let arguments = (plist as? [String: Any])?["ProgramArguments"] as? [String]
        else {
            return Check(name: name, status: .ok, remediation: nil)
        }

        // A stale agent naming a binary that no longer exists used to be
        // completely invisible here, and the move into a bundle is exactly the
        // kind of change that deletes the binary an old agent points at.
        if let program = arguments.first {
            if !FileManager.default.isExecutableFile(atPath: program) {
                return Check(
                    name: name,
                    status: .fail("points at \(program), which is not there"),
                    remediation: "re-run `plume install --launch-at-login`"
                )
            }
            // The daemon takes its preferences domain from CFBundleIdentifier,
            // which it only has inside a bundle. Outside one it falls back to
            // the process name and reads a domain nothing writes, so every
            // remembered choice is invisible to it: the menu bar and the
            // settings window both appear to do nothing at all.
            if !program.contains(".app/Contents/MacOS/") {
                return Check(
                    name: name,
                    status: .fail("\(program) is not inside a .app, so the daemon ignores every remembered choice"),
                    remediation: "re-run `plume install --launch-at-login` with Plume.app installed"
                )
            }
        }

        let remembered = ["--hotkey", "--inject-mode", "--no-overlay", "--mute-output"]
        let stale = remembered.filter(arguments.contains)
        guard !stale.isEmpty else {
            return Check(name: name, status: .ok, remediation: nil)
        }
        return Check(
            name: name,
            status: .warn("\(list(stale)) baked in, overriding the remembered choice"),
            remediation: "re-run `plume install --launch-at-login`"
        )
    }

    /// "a", "a and b", "a, b and c" — the warning names up to four flags and
    /// reads as a sentence at every length.
    private static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }

    /// Versions up to v0.0.5 sent the daemon's stderr, which included every
    /// transcript, to world-readable paths in /tmp.
    ///
    /// The paths keep the old name on purpose: these files were written by
    /// parrot, and renaming them to plume would silently drop the remediation
    /// for exactly the people who need it, the ones migrating.
    static func checkLegacyLogs() -> Check {
        let found = Install.foundLegacyLogs()
        guard !found.isEmpty else {
            return Check(name: "legacy logs", status: .ok, remediation: nil)
        }
        return Check(
            name: "legacy logs",
            status: .warn("world-readable transcript logs present: \(found.joined(separator: ", "))"),
            remediation: "review them, then run `plume install --purge-legacy-logs`"
        )
    }

    /// Takes the hotkey for one line of copy, and that line was wrong before:
    /// it said "hold Fn" to everyone, including the people who had changed the
    /// key, who are exactly the people least able to guess what it meant. The
    /// modifier was already resolved one call up.
    static func checkMicrophone(hotkey: HotkeyMonitor.Hotkey) -> Check {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return Check(name: "microphone", status: .ok, remediation: nil)
        case .notDetermined:
            return Check(
                name: "microphone",
                status: .warn("not yet requested"),
                remediation: "open Plume and choose Allow Microphone in setup, or run `plume setup`"
            )
        case .denied, .restricted:
            return Check(
                name: "microphone",
                status: .fail("denied"),
                remediation: "System Settings → Privacy & Security → Microphone → enable for Plume"
            )
        @unknown default:
            return Check(name: "microphone", status: .fail("unknown state"), remediation: nil)
        }
    }

    /// Bundled, the grant belongs to Plume and the remediation can simply say
    /// so. Unbundled, which is a development build, macOS still attributes the
    /// request to whatever launched the process, so the old guess at the parent
    /// name is kept for that case rather than telling a lie that reads better.
    static func checkAccessibility() -> Check {
        if AXIsProcessTrusted() {
            return Check(name: "accessibility", status: .ok, remediation: nil)
        }
        let grantee: String
        if Bundle.main.bundleIdentifier != nil {
            grantee = "Plume"
        } else {
            grantee = (parentProcessName() ?? "your terminal")
                + " (this build is not bundled, so the grant goes to its parent)"
        }
        return Check(
            name: "accessibility",
            status: .fail("not granted"),
            remediation: "System Settings → Privacy & Security → Accessibility → enable for \(grantee)"
        )
    }

    /// macOS routes Fn (🌐) to one of: Do Nothing / Change Input Source / Show Emoji / Start Dictation.
    /// We need "Do Nothing" so Fn is a clean modifier.
    static func checkFnKeyMapping() -> Check {
        let raw = readDefault(domain: "com.apple.HIToolbox", key: "AppleFnUsageType")
        guard let raw, let value = Int(raw) else {
            return Check(
                name: "fn key mapping",
                status: .warn("unset, the system default may intercept Fn"),
                remediation: "System Settings → Keyboard → Press 🌐 key to → Do Nothing"
            )
        }
        switch value {
        case 0:
            return Check(name: "fn key mapping", status: .ok, remediation: nil)
        case 1:
            return Check(
                name: "fn key mapping",
                status: .fail("set to Change Input Source"),
                remediation: "System Settings → Keyboard → Press 🌐 key to → Do Nothing"
            )
        case 2:
            return Check(
                name: "fn key mapping",
                status: .fail("set to Show Emoji & Symbols"),
                remediation: "System Settings → Keyboard → Press 🌐 key to → Do Nothing"
            )
        case 3:
            return Check(
                name: "fn key mapping",
                status: .fail("set to Start Dictation"),
                remediation: "System Settings → Keyboard → Press 🌐 key to → Do Nothing"
            )
        default:
            return Check(
                name: "fn key mapping",
                status: .warn("unknown value \(value)"),
                remediation: "System Settings → Keyboard → Press 🌐 key to → Do Nothing"
            )
        }
    }

    private static func readDefault(domain: String, key: String) -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["read", domain, key]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return nil
        }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parentProcessName() -> String? {
        let ppid = getppid()
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-p", String(ppid), "-o", "comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return nil
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        return (s as NSString).lastPathComponent
    }

    static func print(_ checks: [Check]) {
        for c in checks {
            let (mark, label): (String, String) = {
                switch c.status {
                case .ok: return ("✓", "ok")
                case .warn(let msg): return ("!", msg)
                case .fail(let msg): return ("✗", msg)
                }
            }()
            Swift.print("\(mark) \(c.name): \(label)")
            if let r = c.remediation {
                Swift.print("    → \(r)")
            }
        }
    }

    /// True if no checks are in a hard-fail state. Warnings don't block.
    static func allOK(_ checks: [Check]) -> Bool {
        checks.allSatisfy {
            if case .fail = $0.status { return false }
            return true
        }
    }

    /// True only if every check passed cleanly (used by `plume doctor` exit code).
    static func allClean(_ checks: [Check]) -> Bool {
        checks.allSatisfy {
            if case .ok = $0.status { return true }
            return false
        }
    }
}
