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
            checkMicrophone(),
            checkAccessibility(),
        ]
        if hotkey == .fn {
            checks.append(checkFnKeyMapping())
        }
        checks.append(checkLegacyLogs())
        checks.append(checkLaunchAgentArgs())
        return checks
    }

    /// Versions up to v0.0.6 baked --hotkey and --inject-mode into the launch
    /// agent's ProgramArguments. A flag still wins over the remembered choice,
    /// so an agent left from one of those installs silently overrides every
    /// pick made in the menu bar.
    static func checkLaunchAgentArgs(at url: URL = Install.plistURL) -> Check {
        let name = "launch agent"
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let arguments = (plist as? [String: Any])?["ProgramArguments"] as? [String]
        else {
            return Check(name: name, status: .ok, remediation: nil)
        }
        let remembered = ["--hotkey", "--inject-mode"]
        let stale = remembered.filter(arguments.contains)
        guard !stale.isEmpty else {
            return Check(name: name, status: .ok, remediation: nil)
        }
        return Check(
            name: name,
            status: .warn("\(list(stale)) baked in — overrides the remembered choice"),
            remediation: "re-run `parrot install --launch-at-login`"
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
    static func checkLegacyLogs() -> Check {
        let paths = ["/tmp/parrot.out.log", "/tmp/parrot.err.log"]
        let found = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !found.isEmpty else {
            return Check(name: "legacy logs", status: .ok, remediation: nil)
        }
        return Check(
            name: "legacy logs",
            status: .warn("world-readable transcript logs present: \(found.joined(separator: ", "))"),
            remediation: "review them, then run `parrot install --purge-legacy-logs`"
        )
    }

    static func checkMicrophone() -> Check {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return Check(name: "microphone", status: .ok, remediation: nil)
        case .notDetermined:
            return Check(
                name: "microphone",
                status: .warn("not yet requested — will prompt on first recording"),
                remediation: "run parrot and hold Fn once; macOS will prompt"
            )
        case .denied, .restricted:
            return Check(
                name: "microphone",
                status: .fail("denied"),
                remediation: "System Settings → Privacy & Security → Microphone → enable for your terminal"
            )
        @unknown default:
            return Check(name: "microphone", status: .fail("unknown state"), remediation: nil)
        }
    }

    static func checkAccessibility() -> Check {
        if AXIsProcessTrusted() {
            return Check(name: "accessibility", status: .ok, remediation: nil)
        }
        let parent = parentProcessName() ?? "your terminal"
        return Check(
            name: "accessibility",
            status: .fail("not granted"),
            remediation: "System Settings → Privacy & Security → Accessibility → enable for \(parent)"
        )
    }

    /// macOS routes Fn (🌐) to one of: Do Nothing / Change Input Source / Show Emoji / Start Dictation.
    /// We need "Do Nothing" so Fn is a clean modifier.
    static func checkFnKeyMapping() -> Check {
        let raw = readDefault(domain: "com.apple.HIToolbox", key: "AppleFnUsageType")
        guard let raw, let value = Int(raw) else {
            return Check(
                name: "fn key mapping",
                status: .warn("unset — system default may intercept Fn"),
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

    /// True only if every check passed cleanly (used by `parrot doctor` exit code).
    static func allClean(_ checks: [Check]) -> Bool {
        checks.allSatisfy {
            if case .ok = $0.status { return true }
            return false
        }
    }
}
