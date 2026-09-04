import Foundation
import os

enum WaxlinePerf {
    nonisolated static let log = Logger(subsystem: "com.api.Waxline", category: "perf")

    nonisolated static func event(_ name: String, _ detail: String = "") {
        if detail.isEmpty {
            log.debug("WAXPERF \(name, privacy: .public)")
        } else {
            log.debug("WAXPERF \(name, privacy: .public) \(detail, privacy: .public)")
        }
    }

    @discardableResult
    nonisolated static func measure<T>(_ name: String, _ body: () -> T) -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let value = body()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        log.debug("WAXPERF \(name, privacy: .public) \(ms, format: .fixed(precision: 1))ms")
        return value
    }
}
