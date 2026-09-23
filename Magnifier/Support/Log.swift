import Foundation
import os

/// Loggers used across the app. Inspect with:
/// `log stream --predicate 'subsystem == "dev.local.Magnifier"' --level debug`
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "dev.local.Magnifier"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
}
