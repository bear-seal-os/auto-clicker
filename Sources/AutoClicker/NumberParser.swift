import Foundation

enum NumberParseResult<Value: Equatable>: Equatable {
    case valid(Value)
    case incomplete
    case invalid
}

enum NumberParser {
    static func integer(_ text: String) -> NumberParseResult<Int> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "-" || trimmed == "+" {
            return .incomplete
        }
        guard trimmed.range(of: #"^[+-]?\d+$"#, options: .regularExpression) != nil,
              let value = Int(trimmed) else {
            return .invalid
        }
        return .valid(value)
    }

    static func decimal(_ text: String) -> NumberParseResult<Double> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isIncompleteDecimal(trimmed) {
            return .incomplete
        }
        guard trimmed.range(of: #"^[+-]?\d+([.,]\d+)?$"#, options: .regularExpression) != nil else {
            return .invalid
        }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else {
            return .invalid
        }
        return .valid(value)
    }

    static func display(_ value: Int) -> String {
        String(value)
    }

    static func display(_ value: Double) -> String {
        if let whole = Int(exactly: value) {
            return String(whole)
        }
        return String(value)
    }

    private static func isIncompleteDecimal(_ trimmed: String) -> Bool {
        if trimmed.isEmpty || trimmed == "-" || trimmed == "+" {
            return true
        }
        return trimmed.range(of: #"^[+-]?\d*[.,]$"#, options: .regularExpression) != nil
    }
}
