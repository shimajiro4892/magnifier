import CoreMedia
import CoreVideo
import Foundation
import IOSurface
import ScreenCaptureKit

struct CaptureConfiguration {
    var frameRate: Int = 60
    var showsCursor: Bool = true
}

enum MagnifierError: LocalizedError {
    case displayNotFound(CGDirectDisplayID)
    case screenCaptureUnavailable

    var errorDescription: String? {
        switch self {
        case .displayNotFound(let id):
            return "ディスプレイ \(id) が見つかりませんでした。"
        case .screenCaptureUnavailable:
            return "画面収録の許可が必要です。"
        }
    }
}

/// Captures one display with ScreenCaptureKit and hands the newest IOSurface to the caller.
///
/// The frames are delivered as IOSurfaces that are handed straight to Core Animation,
/// so the zooming itself is done by the GPU (`contentsRect` on a `CALayer`).
final class ScreenCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    struct FrameUpdate {
        let displayID: CGDirectDisplayID
        let surface: IOSurface
        let pixelSize: CGSize
    }

    /// Called on the capture queue for every delivered frame.
    var onFrame: ((FrameUpdate) -> Void)?
    /// Called on the main queue when the stream stops on its own (e.g. permission revoked).
    var onStreamStopped: ((Error) -> Void)?

    private let queue = DispatchQueue(label: "dev.local.Magnifier.capture", qos: .userInteractive)
    private var stream: SCStream?
    private var configuration = CaptureConfiguration()
    private var generation = 0

    private(set) var runningDisplayID: CGDirectDisplayID?

    func update(configuration: CaptureConfiguration) {
        self.configuration = configuration
    }

    func start(displayID: CGDirectDisplayID, pixelSize: CGSize) async throws {
        generation += 1
        let myGeneration = generation
        await stopStream()

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            Log.capture.error("shareable content failed: \(error.localizedDescription, privacy: .public)")
            throw MagnifierError.screenCaptureUnavailable
        }

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw MagnifierError.displayNotFound(displayID)
        }

        // Never capture our own overlay (it would mirror itself inside the lens).
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }

        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }

        let config = SCStreamConfiguration()
        let width = Int(max(1, pixelSize.width.rounded()))
        let height = Int(max(1, pixelSize.height.rounded()))
        config.width = width
        config.height = height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = configuration.showsCursor
        config.capturesAudio = false
        config.scalesToFit = false
        config.queueDepth = 6
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, configuration.frameRate)))
        config.shouldBeOpaque = true

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()

        guard generation == myGeneration else {
            // A newer request came in while we were starting up.
            try? await stream.stopCapture()
            return
        }

        self.stream = stream
        runningDisplayID = displayID
        Log.capture.info("""
            started display=\(displayID, privacy: .public) size=\(width, privacy: .public)x\(height, privacy: .public) \
            contentRect=\(String(describing: filter.contentRect), privacy: .public) \
            excludedWindows=\(ownWindows.count, privacy: .public)
            """)
    }

    func stop() async {
        generation += 1
        await stopStream()
    }

    private func stopStream() async {
        runningDisplayID = nil
        guard let stream else { return }
        self.stream = nil
        do {
            try await stream.stopCapture()
            Log.capture.info("stopped")
        } catch {
            Log.capture.error("stop failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let displayID = runningDisplayID else { return }
        guard sampleBuffer.isValid else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusValue) else {
            return
        }
        switch status {
        case .complete, .started, .idle:
            break
        case .blank, .suspended, .stopped:
            return
        @unknown default:
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
            return
        }
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        onFrame?(FrameUpdate(displayID: displayID, surface: surface, pixelSize: size))
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.capture.error("stream stopped: \(error.localizedDescription, privacy: .public)")
        if self.stream === stream {
            self.stream = nil
            runningDisplayID = nil
        }
        DispatchQueue.main.async { [weak self] in
            self?.onStreamStopped?(error)
        }
    }
}
