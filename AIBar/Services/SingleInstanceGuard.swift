import AppKit
import Darwin

/// Ensures only one Stack Meter AI process stays alive.
enum SingleInstanceGuard {
    private static var lockFileHandle: FileHandle?

    struct Peer: Equatable {
        let app: NSRunningApplication
        let marketingVersion: String
        let build: Int
    }

    enum Decision: Equatable {
        case proceed
        case alreadyRunning(version: String)
        case olderRunning(version: String, peers: [NSRunningApplication])
        case newerRunning(version: String)
    }

    static func evaluate() -> Decision {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.stackmeter.ai"
        let myBuild = buildNumber(from: Bundle.main)

        let peers: [Peer] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.bundleIdentifier == bundleID,
                  app != NSRunningApplication.current,
                  !app.isTerminated
            else { return nil }
            guard let url = app.bundleURL, let bundle = Bundle(url: url) else {
                return Peer(app: app, marketingVersion: "?", build: 0)
            }
            let marketing = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
            return Peer(app: app, marketingVersion: marketing, build: buildNumber(from: bundle))
        }

        guard let first = peers.first else { return .proceed }

        let maxBuild = peers.map(\.build).max() ?? first.build
        let representative = peers.first(where: { $0.build == maxBuild }) ?? first
        let versionLabel = representative.marketingVersion

        if maxBuild > myBuild {
            return .newerRunning(version: versionLabel)
        }
        if maxBuild < myBuild {
            return .olderRunning(version: versionLabel, peers: peers.map(\.app))
        }
        return .alreadyRunning(version: versionLabel)
    }

    /// Call as early as possible. Returns `false` if this process should exit.
    @discardableResult
    static func enforceOrAlert() -> Bool {
        switch evaluate() {
        case .proceed:
            return acquireLockOrAlert()

        case .alreadyRunning(let version):
            activateExistingInstance()
            presentAlert(
                title: L10n.tr("instance.alreadyTitle"),
                body: L10n.tr("instance.alreadyBody", version),
                buttons: [L10n.tr("instance.ok")]
            )
            return false

        case .newerRunning(let version):
            activateExistingInstance()
            presentAlert(
                title: L10n.tr("instance.newerTitle"),
                body: L10n.tr("instance.newerBody", version),
                buttons: [L10n.tr("instance.ok")]
            )
            return false

        case .olderRunning(let version, let peers):
            let choice = presentAlert(
                title: L10n.tr("instance.olderTitle"),
                body: L10n.tr("instance.olderBody", version),
                buttons: [
                    L10n.tr("instance.quitOlder"),
                    L10n.tr("common.cancel"),
                ]
            )
            if choice == .alertFirstButtonReturn {
                for peer in peers {
                    peer.terminate()
                }
                let deadline = Date().addingTimeInterval(3)
                while Date() < deadline {
                    if peers.allSatisfy(\.isTerminated) { break }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                for peer in peers where !peer.isTerminated {
                    peer.forceTerminate()
                }
                return acquireLockOrAlert()
            }
            return false
        }
    }

    private static func acquireLockOrAlert() -> Bool {
        if tryAcquireLock() { return true }
        activateExistingInstance()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        presentAlert(
            title: L10n.tr("instance.alreadyTitle"),
            body: L10n.tr("instance.alreadyBody", version),
            buttons: [L10n.tr("instance.ok")]
        )
        return false
    }

    private static func tryAcquireLock() -> Bool {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return true
        }
        let dir = support.appendingPathComponent("com.stackmeter.ai", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let lockURL = dir.appendingPathComponent("instance.lock")
        if !fm.fileExists(atPath: lockURL.path) {
            fm.createFile(atPath: lockURL.path, contents: Data())
        }
        guard let handle = try? FileHandle(forUpdating: lockURL) else { return true }
        if flock(handle.fileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            try? handle.close()
            return false
        }
        // Keep the handle open for the process lifetime so the lock is held.
        lockFileHandle = handle
        return true
    }

    private static func buildNumber(from bundle: Bundle) -> Int {
        if let number = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? NSNumber {
            return number.intValue
        }
        let raw = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return Int(raw) ?? 0
    }

    private static func activateExistingInstance() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.stackmeter.ai"
        let current = NSRunningApplication.current
        guard let other = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID && $0 != current && !$0.isTerminated
        }) else { return }
        other.activate()
    }

    @discardableResult
    private static func presentAlert(title: String, body: String, buttons: [String]) -> NSApplication.ModalResponse {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        for title in buttons {
            alert.addButton(withTitle: title)
        }
        return alert.runModal()
    }
}
