import Foundation

struct RunCue: Equatable {
    var currentLabel: String
    var nextLabel: String
    var waitMilliseconds: Int
    var startedAt: Date

    static func waiting(
        current: String,
        next: String,
        waitMilliseconds: Int,
        startedAt: Date = Date()
    ) -> RunCue {
        RunCue(
            currentLabel: current,
            nextLabel: next,
            waitMilliseconds: max(0, waitMilliseconds),
            startedAt: startedAt
        )
    }

    static func finished(current: String, startedAt: Date = Date()) -> RunCue {
        RunCue(
            currentLabel: current,
            nextLabel: "Done",
            waitMilliseconds: 0,
            startedAt: startedAt
        )
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
