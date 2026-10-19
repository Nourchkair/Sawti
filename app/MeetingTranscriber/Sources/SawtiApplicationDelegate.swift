import AppKit
import Carbon.HIToolbox
import os.log

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "AppLifecycle")

/// SwiftUI's MenuBarExtra can ask AppKit to terminate a menu-bar-only app when
/// its status-item scene is removed. Sawti's status item is the app's primary
/// interface, so that automatic request must not end the process. The explicit
/// Quit command opts into termination before calling `NSApplication.terminate`.
@MainActor
final class SawtiApplicationDelegate: NSObject, NSApplicationDelegate {
    private(set) var userRequestedTermination = false

    override init() {
        super.init()
        // A normal app quit and macOS logout arrive as the standard Quit Apple
        // event. Preserve those explicit exits while rejecting only SwiftUI's
        // internal terminate request when it tears down the status-item scene.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleQuitAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEQuitApplication),
        )
    }

    func allowUserRequestedTermination() {
        userRequestedTermination = true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard userRequestedTermination else {
            logger.warning("Ignored an implicit termination request while the menu-bar app is active")
            return .terminateCancel
        }
        return .terminateNow
    }

    @objc private func handleQuitAppleEvent(
        _: NSAppleEventDescriptor,
        withReplyEvent _: NSAppleEventDescriptor,
    ) {
        userRequestedTermination = true
        NSApp.terminate(nil)
    }
}
