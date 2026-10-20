import AppKit
import os.log
import SwiftUI

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "AppLifecycle")

/// Owns Sawti's native status item for the lifetime of the app. The previous
/// SwiftUI `MenuBarExtra` scene was torn down by macOS while the process stayed
/// alive, leaving a running app with no visible control. A retained AppKit
/// status item avoids tying the primary interface to that scene lifecycle.
@MainActor
final class SawtiApplicationDelegate: NSObject, NSApplicationDelegate {
    private weak var appState: AppState?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var hostingController: NSHostingController<AnyView>?
    private var iconTimer: Timer?
    private var lastRenderedBadge: BadgeKind?
    private var animationFrame = 0
    private var didFinishLaunching = false

    /// Installs the native menu-bar item once, retaining the existing SwiftUI
    /// controls in a popover. The icon itself is updated from AppState so the
    /// official idle logo and animated recording states remain in sync.
    func installStatusItem(state: AppState, rootView: AnyView) {
        appState = state

        if hostingController == nil {
            let host = NSHostingController(rootView: rootView)
            host.view.frame = NSRect(x: 0, y: 0, width: 380, height: 600)
            hostingController = host
            popover.contentViewController = host
            popover.contentSize = NSSize(width: 380, height: 600)
            popover.behavior = .transient
            popover.animates = false
            // Load the SwiftUI hierarchy at launch so its notification and
            // permission observers are active before the first menu click.
            _ = host.view
        }

        // Keep status-bar installation on the post-launch side of AppKit's
        // lifecycle. SwiftUI may evaluate this scene body before
        // NSApplication finishes launching, so defer the one-time install.
        if didFinishLaunching {
            installStatusButton()
        }

        if iconTimer == nil {
            iconTimer = Timer.scheduledTimer(
                timeInterval: 0.4,
                target: self,
                selector: #selector(refreshStatusItemIcon),
                userInfo: nil,
                repeats: true,
            )
        }
        refreshStatusItemIcon()
    }

    func applicationDidFinishLaunching(_: Notification) {
        didFinishLaunching = true
        installStatusButton()
        refreshStatusItemIcon()
        logger.info("Sawti finished launching with menu-bar item installed")
    }

    private func installStatusButton() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else {
            logger.error("Could not create the Sawti menu-bar button")
            return
        }
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.image = MenuBarIcon.image(badge: .inactive)
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.toolTip = "Sawti — Idle"
        button.setAccessibilityLabel("Sawti, Idle")
        item.isVisible = true
        statusItem = item
        logger.info("Created Sawti's native menu-bar status item")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_: Notification) {
        guard let appState else { return }
        Task { await appState.permissions.check(minimumInterval: 3) }
    }

    func applicationWillTerminate(_: Notification) {
        iconTimer?.invalidate()
        iconTimer = nil
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        // The status item is retained directly by this delegate now; no
        // MenuBarExtra scene owns the app's lifetime. Honor AppKit's Quit,
        // logout and shutdown requests so the user can actually restart Sawti
        // after changing a macOS permission.
        return .terminateNow
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func refreshStatusItemIcon() {
        guard let appState, let button = statusItem?.button else { return }
        let badge = appState.currentBadge
        if badge != lastRenderedBadge {
            lastRenderedBadge = badge
            animationFrame = 0
        } else {
            animationFrame = MenuBarIcon.nextFrame(animationFrame, badge: badge)
        }
        let image = MenuBarIcon.image(
            badge: badge,
            animationFrame: animationFrame,
            permissionOverlay: appState.hasPermissionProblem,
            recordOnlyOverlay: appState.settings.recordOnly,
            micSilentOverlay: appState.micSilentOverlay,
            appSilentOverlay: appState.appSilentOverlay,
        )
        button.image = image
        button.image?.isTemplate = image.isTemplate
        button.toolTip = "Sawti — \(appState.currentStateLabel)"
        button.setAccessibilityLabel("Sawti, \(appState.currentStateLabel)")
    }
}
