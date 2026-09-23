// Compiled alongside the production sources by scripts/test-lifecycle.sh.
// Extensions share a generated file with those sources to exercise private
// lifecycle transitions without exposing test hooks in the application API.
import AppKit
import ScreenCaptureKit

extension MagnifierController {
    @MainActor static func verifyLifecycle() {
        let controller = MagnifierController()
        // Suppress permission dialogs; no capture is started by these checks.
        controller.hasShownPermissionAlert = true
        controller.skipCapture = true
        controller.toggleFromHotKey()
        precondition(controller.isActive, "Shortcut must activate in hold mode")
        precondition(!controller.followsMouseButton, "Shortcut must not follow mouse release")
        controller.handleButtonRelease()
        controller.pollButtonState()
        controller.displayLinkFired(controller.displayLink!)
        precondition(controller.isActive, "Mouse release/poll must preserve shortcut activation")
        controller.toggleFromHotKey()
        precondition(!controller.isActive, "Second shortcut must turn the lens off")
        print("PASS shortcut activation survives release, polling and display updates in hold mode")

        controller.skipCapture = true
        controller.handleButtonPress()
        precondition(controller.isActive && controller.followsMouseButton)
        controller.handleButtonRelease()
        precondition(!controller.isActive, "Mouse hold must still end on release")
        print("PASS mouse hold still ends on release")

        controller.skipCapture = true
        controller.toggleFromHotKey()
        let current = UUID()
        controller.captureRequestID = current
        let error = NSError(domain: "LifecycleTest", code: 1)
        controller.handleCaptureFailure(error, requestID: UUID())
        precondition(controller.isActive && controller.captureRequestID == current,
                     "An obsolete start failure must not stop the current activation")
        controller.handleCaptureFailure(error, requestID: current)
        precondition(!controller.isActive && controller.captureRequestID == nil,
                     "A current start failure must reset the active state")
        precondition(controller.window?.isVisible == false,
                     "A current start failure must hide the overlay")
        print("PASS stale start failure ignored; current failure hides and resets lens")
    }
}

extension ScreenCaptureEngine {
    @MainActor static func verifyLifecycle() async {
        let engine = ScreenCaptureEngine()
        let old = SCStream(filter: SCContentFilter(), configuration: SCStreamConfiguration(), delegate: nil)
        let current = SCStream(filter: SCContentFilter(), configuration: SCStreamConfiguration(), delegate: nil)
        let request = UUID()
        engine.stream = current
        engine.requestID = request
        engine.runningDisplayID = 1
        var notifications: [UUID] = []
        engine.onStreamStopped = { id, _ in notifications.append(id) }
        let error = NSError(domain: "LifecycleTest", code: 2)

        engine.stream(old, didStopWithError: error)
        try? await Task.sleep(nanoseconds: 30_000_000)
        precondition(notifications.isEmpty && engine.stream === current)
        print("PASS obsolete stream stop leaves current stream running")

        // Deliver a current-stream callback, but replace it before the queued
        // main-actor handler runs. Identity must be checked at delivery time.
        engine.stream(current, didStopWithError: error)
        engine.stream = old
        try? await Task.sleep(nanoseconds: 30_000_000)
        precondition(notifications.isEmpty && engine.stream === old)
        print("PASS replacement before queued error delivery is protected")

        engine.stream(old, didStopWithError: error)
        try? await Task.sleep(nanoseconds: 30_000_000)
        precondition(notifications == [request])
        precondition(engine.stream == nil && engine.requestID == nil && engine.runningDisplayID == nil)
        print("PASS current stream stop notifies once and clears state")
    }
}

@main struct LifecycleVerification {
    @MainActor static func main() async {
        // Use process-only overrides. Do not modify the installed app's settings.
        UserDefaults.standard.setVolatileDomain([
            "triggerMode": 1, "isEnabled": true, "mouseButton": 2,
        ], forName: UserDefaults.argumentDomain)
        _ = NSApplication.shared
        MagnifierController.verifyLifecycle()
        await ScreenCaptureEngine.verifyLifecycle()
        print("All lifecycle checks passed.")
    }
}
