import AppKit
import Combine
import CoreGraphics
import QuartzCore

/// Wires the mouse button, the screen capture and the overlay window together.
///
/// The magnifier can either follow the mouse button (hold) or be toggled on and
/// off by it. While it is on, the display under the cursor is captured and a
/// lens centered on the cursor shows the area around it magnified.
@MainActor
final class MagnifierController: ObservableObject {
    static let shared = MagnifierController()

    /// Whether the magnifier is currently shown.
    @Published private(set) var isActive = false
    /// Set when the global shortcut could not be registered.
    @Published private(set) var hotKeyError: String?

    private let settings = SettingsStore.shared
    private let permissions = PermissionMonitor.shared
    private let monitor = MouseButtonMonitor()
    private let engine = ScreenCaptureEngine()
    private let hotKey = GlobalHotKey()

    private var window: OverlayWindow?
    private var hostView: OverlayHostView?
    private var renderer: LensRenderer?
    private var displayLink: CADisplayLink?

    private var isForced = false
    private var followsMouseButton = false
    private var captureRequestID: UUID?
    private var skipCapture = false
    private var activeDisplay: DisplayGeometry?
    private var hasShownPermissionAlert = false
    private var pollTimer: Timer?
    private var releaseWatchdog: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private init() {}

    func start() {
        engine.onFrame = { [weak self] frame in
            self?.handle(frame: frame)
        }
        engine.onStreamStopped = { [weak self] requestID, error in
            guard let self, self.captureRequestID == requestID else { return }
            Log.capture.error("capture stopped unexpectedly: \(error.localizedDescription, privacy: .public)")
            self.turnOff(reason: "capture stopped")
        }

        monitor.onPress = { [weak self] in self?.handleButtonPress() }
        monitor.onRelease = { [weak self] in self?.handleButtonRelease() }
        monitor.start(button: settings.mouseButton)

        settings.$mouseButton
            .dropFirst()
            .sink { [weak self] button in
                Task { @MainActor in
                    guard let self else { return }
                    self.turnOff(reason: "button changed")
                    self.monitor.start(button: button)
                }
            }
            .store(in: &cancellables)

        settings.$isEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                Task { @MainActor in
                    guard let self, !enabled else { return }
                    self.turnOff(reason: "disabled")
                }
            }
            .store(in: &cancellables)

        // Capture related settings can only be applied by restarting the stream.
        settings.$showsCursor
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.restartCaptureIfActive() } }
            .store(in: &cancellables)
        settings.$frameRate
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.restartCaptureIfActive() } }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                              object: nil,
                                              queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.screenParametersDidChange()
            }
        }

        settings.$hotKey
            .dropFirst()
            .sink { [weak self] shortcut in
                Task { @MainActor in
                    self?.updateHotKey(shortcut)
                }
            }
            .store(in: &cancellables)
        updateHotKey(settings.hotKey)

        permissions.startMonitoring()

        // Safety net in case a global monitor does not deliver the press
        // (for example when the button is already held while the app launches).
        let pollTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollButtonState()
            }
        }
        RunLoop.main.add(pollTimer, forMode: .common)
        self.pollTimer = pollTimer

        Log.app.info("controller started mode=\(self.settings.triggerMode.label, privacy: .public)")
    }

    func shutdown() {
        turnOff(reason: "shutdown")
        monitor.stop()
        hotKey.unregister()
        engine.stop()
    }

    // MARK: - Global shortcut

    private func updateHotKey(_ shortcut: KeyShortcut) {
        hotKeyError = nil
        hotKey.unregister()
        guard shortcut.isSet else {
            Log.input.info("hot key cleared")
            return
        }
        let registered = hotKey.register(keyCode: UInt32(shortcut.keyCode),
                                         modifiers: shortcut.carbonModifiers) { [weak self] in
            Task { @MainActor in
                self?.toggleFromHotKey()
            }
        }
        if !registered {
            hotKeyError = "\(shortcut.display) を登録できませんでした。他のアプリが同じキーを使っている可能性があります。"
        }
    }

    /// The shortcut always toggles, independent of the mouse button mode.
    private func toggleFromHotKey() {
        Log.input.info("hot key pressed")
        if isActive {
            turnOff(reason: "hot key")
        } else {
            activate()
        }
    }

    // MARK: - Button handling

    private func handleButtonPress() {
        switch settings.triggerMode {
        case .toggle:
            if isActive {
                turnOff(reason: "toggle off")
            } else {
                activate()
            }
        case .hold:
            activate(followMouseButton: true)
        }
    }

    private func handleButtonRelease() {
        guard followsMouseButton else { return }
        turnOff(reason: "button release")
    }

    private func pollButtonState() {
        guard !isForced, settings.triggerMode == .hold else { return }
        let pressed = monitor.isButtonPressed
        if pressed && !isActive {
            Log.input.info("""
                press detected by polling (pressedMouseButtons=\(NSEvent.pressedMouseButtons, privacy: .public), \
                button=\(self.monitor.button.shortLabel, privacy: .public))
                """)
            activate(followMouseButton: true)
        } else if !pressed && isActive && followsMouseButton {
            turnOff(reason: "poll")
        }
    }

    // MARK: - Activation

    /// Test / CLI entry point: shows the magnifier for a while without a button press.
    /// With `capture: false` only the lens frame is drawn (no screen recording permission needed).
    func activateForTesting(duration: TimeInterval, capture: Bool = true) {
        isForced = true
        skipCapture = !capture
        activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            Task { @MainActor in
                self?.turnOff(reason: "test finished")
            }
        }
    }

    /// Test hook: behaves exactly like a physical button press.
    func simulateButtonPress() {
        Log.input.info("simulated button press (mode=\(self.settings.triggerMode.shortLabel, privacy: .public))")
        handleButtonPress()
    }

    private func activate(followMouseButton: Bool = false) {
        guard !isActive else { return }
        guard isForced || settings.isEnabled else {
            Log.overlay.info("activation skipped: disabled")
            return
        }
        guard let display = DisplayGeometry.containing(NSEvent.mouseLocation) else {
            Log.overlay.error("activation failed: no display at cursor")
            return
        }

        if !skipCapture {
            permissions.refresh()
            guard permissions.isScreenRecordingGranted else {
                Log.app.error("activation blocked: screen recording not granted")
                showPermissionAlertIfNeeded()
                return
            }
        }

        followsMouseButton = followMouseButton && !isForced
        isActive = true
        activeDisplay = display
        Log.overlay.info("""
            activated display=\(display.displayID, privacy: .public) \
            frame=\(String(describing: display.frame), privacy: .public) \
            pixels=\(Int(display.pixelSize.width), privacy: .public)x\(Int(display.pixelSize.height), privacy: .public) \
            scale=\(display.scaleFactor, privacy: .public) capture=\(!self.skipCapture, privacy: .public)
            """)
        setupWindow(for: display)
        startDisplayLink()
        if followsMouseButton {
            startReleaseWatchdog()
        }
        updateLens()
        if !skipCapture {
            startCapture(for: display)
        }
    }

    /// Hides the magnifier. `reason` is only used for logging.
    func turnOff(reason: String) {
        guard isActive else { return }
        Log.overlay.info("deactivating (\(reason, privacy: .public))")
        isActive = false
        followsMouseButton = false
        captureRequestID = nil
        isForced = false
        skipCapture = false
        stopReleaseWatchdog()
        stopDisplayLink()
        renderer?.hide()
        window?.orderOut(nil)
        activeDisplay = nil
        engine.stop()
    }

    private func restartCaptureIfActive() {
        guard isActive, let display = activeDisplay else { return }
        startCapture(for: display)
    }

    // MARK: - Window / layers

    private func setupWindow(for display: DisplayGeometry) {
        if window == nil {
            let window = OverlayWindow()
            let host = OverlayHostView(frame: CGRect(origin: .zero, size: display.frame.size))
            host.wantsLayer = true
            if host.layer == nil {
                host.layer = CALayer()
            }
            host.layer?.masksToBounds = false
            host.autoresizingMask = [.width, .height]
            window.contentView = host
            self.window = window
            self.hostView = host
            self.renderer = LensRenderer(host: host.layer ?? CALayer())
        }

        guard let window, let host = hostView else { return }
        window.setFrame(display.frame, display: false)
        host.frame = CGRect(origin: .zero, size: display.frame.size)
        window.orderFrontRegardless()
    }

    // MARK: - Capture

    private func startCapture(for display: DisplayGeometry) {
        guard isActive, !skipCapture else { return }
        let requestID = UUID()
        captureRequestID = requestID
        engine.update(configuration: CaptureConfiguration(frameRate: settings.frameRate,
                                                          showsCursor: settings.showsCursor))
        let displayID = display.displayID
        let pixelSize = display.pixelSize
        Task { [weak self] in
            guard let self, self.captureRequestID == requestID else { return }
            do {
                try await self.engine.start(displayID: displayID, pixelSize: pixelSize, requestID: requestID)
            } catch {
                self.handleCaptureFailure(error, requestID: requestID)
            }
        }
    }

    private func handleCaptureFailure(_ error: Error, requestID: UUID) {
        guard captureRequestID == requestID else { return }
        turnOff(reason: "capture start failed")
        Log.capture.error("capture start failed: \(error.localizedDescription, privacy: .public)")
        permissions.refresh()
        if !permissions.isScreenRecordingGranted {
            showPermissionAlertIfNeeded()
        }
    }

    private func handle(frame: ScreenCaptureEngine.FrameUpdate) {
        guard isActive, frame.requestID == captureRequestID, let display = activeDisplay, frame.displayID == display.displayID else { return }
        renderer?.setContents(frame.surface)
        updateLens()
    }

    // MARK: - Geometry

    private func cursorInView() -> CGPoint? {
        guard let window, let host = hostView else { return nil }
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        return host.convert(windowPoint, from: nil)
    }

    private func updateLens() {
        guard isActive, let window, let host = hostView, let renderer, let cursor = cursorInView() else { return }
        let viewSize = host.bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        renderer.update(lensState(cursor: cursor, viewSize: viewSize, scale: window.backingScaleFactor))
    }

    private func lensState(cursor: CGPoint, viewSize: CGSize, scale: CGFloat) -> LensState {
        let settings = self.settings
        let lensSize = settings.lensSize

        // Cursor position in normalized display coordinates (origin: top-left).
        let normalizedX = cursor.x / viewSize.width
        let normalizedY = 1 - cursor.y / viewSize.height

        let cropWidth = min(1, max(20, settings.regionWidth) / viewSize.width)
        let cropHeight = min(1, max(20, settings.regionHeight) / viewSize.height)
        var cropX = normalizedX - cropWidth / 2
        var cropY = normalizedY - cropHeight / 2
        if settings.clampToScreen {
            cropX = min(max(cropX, 0), max(0, 1 - cropWidth))
            cropY = min(max(cropY, 0), max(0, 1 - cropHeight))
        }
        let crop = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

        var center = CGPoint(x: cursor.x + settings.offsetX, y: cursor.y + settings.offsetY)
        if settings.clampToScreen {
            let margin: CGFloat = 2
            if lensSize.width + margin * 2 <= viewSize.width {
                center.x = min(max(center.x, lensSize.width / 2 + margin), viewSize.width - lensSize.width / 2 - margin)
            } else {
                center.x = viewSize.width / 2
            }
            if lensSize.height + margin * 2 <= viewSize.height {
                center.y = min(max(center.y, lensSize.height / 2 + margin), viewSize.height - lensSize.height / 2 - margin)
            } else {
                center.y = viewSize.height / 2
            }
        }

        return LensState(center: center,
                         lensSize: lensSize,
                         cropRect: crop,
                         shape: settings.shape,
                         smoothScaling: settings.smoothScaling,
                         showBorder: settings.showBorder,
                         cornerRadius: 18,
                         scale: scale)
    }

    // MARK: - Timers

    private func startDisplayLink() {
        stopDisplayLink()
        guard let host = hostView else { return }
        let link = host.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// A plain timer that keeps checking the button state. Unlike a `CADisplayLink`
    /// it also runs when the window is not visible or the display sleeps, so a
    /// missed mouse up event cannot leave the magnifier on screen.
    private func startReleaseWatchdog() {
        stopReleaseWatchdog()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive, self.followsMouseButton else { return }
                if !self.monitor.isButtonPressed {
                    Log.input.info("""
                        release detected by watchdog \
                        (pressedMouseButtons=\(NSEvent.pressedMouseButtons, privacy: .public))
                        """)
                    self.turnOff(reason: "watchdog")
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        releaseWatchdog = timer
    }

    private func stopReleaseWatchdog() {
        releaseWatchdog?.invalidate()
        releaseWatchdog = nil
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        guard isActive else { return }
        if followsMouseButton, !monitor.isButtonPressed {
            turnOff(reason: "display link")
            return
        }
        updateLens()
        switchDisplayIfNeeded()
    }

    private func switchDisplayIfNeeded() {
        guard let current = activeDisplay else { return }
        let cursor = NSEvent.mouseLocation
        guard !current.frame.contains(cursor) else { return }
        guard let next = DisplayGeometry.containing(cursor), next.displayID != current.displayID else { return }

        Log.overlay.info("moving lens to display \(next.displayID, privacy: .public)")
        activeDisplay = next
        renderer?.setContents(nil)
        setupWindow(for: next)
        startCapture(for: next)
    }

    private func screenParametersDidChange() {
        guard isActive else { return }
        guard let display = DisplayGeometry.containing(NSEvent.mouseLocation) else {
            turnOff(reason: "display removed")
            return
        }
        activeDisplay = display
        setupWindow(for: display)
        startCapture(for: display)
    }

    // MARK: - Permission

    private func showPermissionAlertIfNeeded() {
        guard !hasShownPermissionAlert else { return }
        hasShownPermissionAlert = true

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "画面収録の許可が必要です"
        alert.informativeText = """
            拡大鏡を使うには「画面収録」の許可が必要です。
            システム設定 → プライバシーとセキュリティ → 画面収録 で「拡大鏡」を有効にし、アプリを再起動してください。
            """
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "あとで")
        if alert.runModal() == .alertFirstButtonReturn {
            permissions.openScreenRecordingSettings()
        }
    }
}
