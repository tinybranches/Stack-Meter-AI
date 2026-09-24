import SwiftUI
import AppKit

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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// Starts polling once the menu bar scene is alive.
enum AIBarBootstrap {
    @MainActor
    static func startIfNeeded(_ viewModel: UsageViewModel) {
        viewModel.start()
    }
}
