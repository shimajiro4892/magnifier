import AppKit
import Combine
import CoreGraphics
import QuartzCore

/// Wires the mouse button, the screen capture and the overlay window together.
///
/// While the configured mouse button is held down the display under the cursor is
/// captured and a lens centered on the cursor shows the area around it magnified.
@MainActor
final class MagnifierController {
    static let shared = MagnifierController()

    private let settings = SettingsStore.shared
    private let permissions = PermissionMonitor.shared
    private let monitor = MouseButtonMonitor()
    private let engine = ScreenCaptureEngine()

    private var window: OverlayWindow?
    private var hostView: OverlayHostView?
    private var renderer: LensRenderer?
    private var displayLink: CADisplayLink?

    private var isActive = false
    private var isForced = false
    private var skipCapture = false
    private var activeDisplay: DisplayGeometry?
    private var hasShownPermissionAlert = false
    private var pollTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private init() {}

    func start() {
        engine.onFrame = { [weak self] frame in
            Task { @MainActor [weak self] in
                self?.handle(frame: frame)
            }
        }
        engine.onStreamStopped = { [weak self] error in
            Task { @MainActor [weak self] in
                Log.capture.error("capture stopped unexpectedly: \(error.localizedDescription, privacy: .public)")
                self?.deactivate()
            }
        }

        monitor.onPress = { [weak self] in self?.activate() }
        monitor.onRelease = { [weak self] in
            guard let self, !self.isForced else { return }
            self.deactivate()
        }
        monitor.start(button: settings.mouseButton)

        settings.$mouseButton
            .dropFirst()
            .sink { [weak self] button in
                Task { @MainActor in
                    guard let self else { return }
                    self.deactivate()
                    self.monitor.start(button: button)
                }
            }
            .store(in: &cancellables)

        settings.$isEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                Task { @MainActor in
                    guard let self, !enabled else { return }
                    self.deactivate()
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

        Log.app.info("controller started")
    }

    private func pollButtonState() {
        guard !isForced else { return }
        let pressed = monitor.isButtonPressed
        if pressed && !isActive {
            Log.input.info("""
                press detected by polling (pressedMouseButtons=\(NSEvent.pressedMouseButtons, privacy: .public), \
                button=\(self.monitor.button.shortLabel, privacy: .public))
                """)
            activate()
        } else if !pressed && isActive {
            deactivate()
        }
    }

    func shutdown() {
        deactivate()
        monitor.stop()
        Task { await engine.stop() }
    }

    // MARK: - Activation

    /// Test / CLI entry point: shows the magnifier for a while without a button press.
    /// With `capture: false` only the lens frame is drawn (no screen recording permission needed).
    func activateForTesting(duration: TimeInterval, capture: Bool = true) {
        isForced = true
        skipCapture = !capture
        activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            self.isForced = false
            self.deactivate()
        }
    }

    private func activate() {
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
        updateLens()
        if !skipCapture {
            startCapture(for: display)
        }
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        isForced = false
        skipCapture = false
        stopDisplayLink()
        renderer?.hide()
        window?.orderOut(nil)
        activeDisplay = nil
        Task { await engine.stop() }
        Log.overlay.info("deactivated")
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
        engine.update(configuration: CaptureConfiguration(frameRate: settings.frameRate,
                                                          showsCursor: settings.showsCursor))
        let displayID = display.displayID
        let pixelSize = display.pixelSize
        Task { [weak self] in
            do {
                try await self?.engine.start(displayID: displayID, pixelSize: pixelSize)
            } catch {
                guard let self else { return }
                Log.capture.error("capture start failed: \(error.localizedDescription, privacy: .public)")
                self.permissions.refresh()
                if !self.permissions.isScreenRecordingGranted {
                    self.deactivate()
                    self.showPermissionAlertIfNeeded()
                }
            }
        }
    }

    private func handle(frame: ScreenCaptureEngine.FrameUpdate) {
        guard isActive, let display = activeDisplay, frame.displayID == display.displayID else { return }
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

        // Cursor position in normalized image coordinates (origin: top-left of the captured display).
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

    // MARK: - Display link

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

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        guard isActive else { return }
        if !isForced && !monitor.isButtonPressed {
            // Safety net in case a mouse up event was missed.
            deactivate()
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
            deactivate()
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
