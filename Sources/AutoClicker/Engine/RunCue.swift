import Foundation

struct RunCue: Equatable {
    var currentLabel: String
    var nextLabel: String
    var waitMilliseconds: Int
    var actionIndex: Int
    var startedAt: Date

    static func waiting(
        current: String,
        next: String,
        waitMilliseconds: Int,
        actionIndex: Int,
        startedAt: Date = Date()
    ) -> RunCue {
        RunCue(
            currentLabel: current,
            nextLabel: next,
            waitMilliseconds: max(0, waitMilliseconds),
            actionIndex: max(1, actionIndex),
            startedAt: startedAt
        )
    }

    static func finished(current: String, actionIndex: Int, startedAt: Date = Date()) -> RunCue {
        RunCue(
            currentLabel: current,
            nextLabel: "Done",
            waitMilliseconds: 0,
            actionIndex: max(1, actionIndex),
            startedAt: startedAt
        )
    }
}

enum OverlayReadout {
    static func currentLine(label: String, actionIndex: Int) -> String {
        "\(label)  ·  \(actionIndex)"
    }

    static func countdown(waitMilliseconds: Int, startedAt: Date, at date: Date) -> String {
        guard waitMilliseconds > 0 else { return "" }
        let elapsedMs = Int((date.timeIntervalSince(startedAt) * 1000).rounded())
        let remainingMs = max(0, waitMilliseconds - max(0, elapsedMs))
        if waitMilliseconds >= 1000 {
            if remainingMs <= 0 { return "0s" }
            return "\(max(1, Int((Double(remainingMs) / 1000).rounded(.up))))s"
        }
        return "\(remainingMs)ms"
    }

    static func fraction(waitMilliseconds: Int, startedAt: Date, at date: Date) -> Double {
        guard waitMilliseconds > 0 else { return 1 }
        let duration = Double(waitMilliseconds) / 1000
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        return min(1, elapsed / duration)
    }
}

enum RunLabels {
    static func intervalAction(_ settings: AppSettings) -> String {
        switch settings.mode {
        case .clickHere:
            return "\(settings.mouseButton.title) click"
        case .clickPoint:
            return String(
                format: "%@ click (%.0f, %.0f)",
                settings.mouseButton.title,
                settings.clickPoint.x,
                settings.clickPoint.y
            )
        case .key:
            return settings.keyChord.isEmpty ? "Key" : settings.keyChord.displayName
        case .macro:
            return "Macro"
        }
    }

    static func macroStep(_ step: MacroStep) -> String {
        switch step.kind {
        case .click:
            let button = step.mouseButton.title
            if let point = step.point {
                return String(format: "%@ click (%.0f, %.0f)", button, point.x, point.y)
            }
            return "\(button) click"
        case .key:
            return step.key?.displayName ?? "Key"
        case .wait:
            return "Wait"
        }
    }
}
