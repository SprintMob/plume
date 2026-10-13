import AppKit
import Darwin
import Foundation

/// flock is held until process exit: no stale pid-file can claim ownership.
/// The directory/file contain no audio or transcripts and are private to the user.
final class DaemonSingleton {
    static let reopen = Notification.Name("com.sprintmob.plume.reopen")
    private var descriptor: Int32 = -1

    func acquire(at directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/plume/runtime")) throws -> Bool {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let path = directory.appendingPathComponent("daemon.lock").path
        descriptor = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        _ = fchmod(descriptor, 0o600)
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return true }
        close(descriptor)
        descriptor = -1
        return false
    }

    static func requestReopen() {
        DistributedNotificationCenter.default().postNotificationName(
            reopen, object: String(getuid()), userInfo: nil, deliverImmediately: true)
        // Older bundles do not listen for our notification. An ordinary open
        // event can still reopen their settings without starting another daemon.
        for app in otherRunningBundles() { app.activate(options: []) }
    }

    static func otherRunningBundles() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.sprintmob.plume")
            .filter { $0.processIdentifier != getpid() && !$0.isTerminated }
    }

    deinit { if descriptor >= 0 { close(descriptor) } }
}
