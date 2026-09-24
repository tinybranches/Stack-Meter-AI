import SwiftUI
import AppKit
import CoreServices

@main
struct AIBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(viewModel: viewModel)
        } label: {
            MenuBarLabelView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: viewModel.settings, viewModel: viewModel)
        }

        Window("Stack Meter AI Settings", id: "settings") {
            SettingsView(settings: viewModel.settings, viewModel: viewModel)
        }
        .defaultSize(width: 420, height: 720)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Icon first, then hide Dock — required so Notifications/System Settings
        // pick up AppIcon (LSUIElement in Info.plist leaves a blank placeholder).
        AppIcon.applyToRunningApplication()
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIcon.applyToRunningApplication()
        // Refresh Launch Services so System Settings re-reads the icon.
        let url = Bundle.main.bundleURL as CFURL
        LSRegisterURL(url, true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

enum AppIcon {
    /// Sets the live app icon from AppIcon.icns / asset catalog.
    @MainActor
    static func applyToRunningApplication() {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url)
        {
            NSApp.applicationIconImage = image
            return
        }
        if let image = NSImage(named: NSImage.applicationIconName) {
            NSApp.applicationIconImage = image
        }
    }
}

/// Starts polling once the menu bar scene is alive.
enum AIBarBootstrap {
    @MainActor
    static func startIfNeeded(_ viewModel: UsageViewModel) {
        viewModel.start()
    }
}
