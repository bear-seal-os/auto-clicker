import SwiftUI

private struct NumericFieldNamespaceKey: EnvironmentKey {
    static let defaultValue = "panel"
}

extension EnvironmentValues {
    var numericFieldNamespace: String {
        get { self[NumericFieldNamespaceKey.self] }
        set { self[NumericFieldNamespaceKey.self] = newValue }
    }
}

struct TypedNumberField<Value: Equatable>: View {
    @Environment(\.numericFieldNamespace) private var fieldNamespace
    @EnvironmentObject private var model: AppModel
    @Binding private var value: Value
    private let fieldID: String
    private let parse: (String) -> NumberParseResult<Value>
    private let display: (Value) -> String
    private let invalidMessage: String
    private let width: CGFloat?
    private let enabled: Bool

    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    init(
        integer value: Binding<Int>,
        id: String,
        width: CGFloat? = 72,
        enabled: Bool = true
    ) where Value == Int {
        _value = value
        fieldID = id
        parse = NumberParser.integer
        display = NumberParser.display
        invalidMessage = "Whole number"
        self.width = width
        self.enabled = enabled
    }

    init(
        decimal value: Binding<Double>,
        id: String,
        width: CGFloat? = nil,
        enabled: Bool = true
    ) where Value == Double {
        _value = value
        fieldID = id
        parse = NumberParser.decimal
        display = NumberParser.display
        invalidMessage = "Number"
        self.width = width
        self.enabled = enabled
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .focused($focused)
            .disabled(!enabled)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(invalid ? Color.red : Color.clear, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .help(invalid ? invalidMessage : "")
            .onAppear {
                text = display(value)
            }
            .onChange(of: text) { _, newText in
                apply(newText)
            }
            .onChange(of: value) { _, newValue in
                guard !focused else { return }
                text = display(newValue)
                setInvalid(false)
            }
            .onChange(of: focused) { _, isFocused in
                guard !isFocused else { return }
                switch parse(text) {
                case .valid(let newValue):
                    setInvalid(false)
                    if value != newValue {
                        value = newValue
                    }
                    text = display(newValue)
                case .incomplete, .invalid:
                    setInvalid(true)
                }
            }
            .onDisappear {
                model.setNumericFieldInvalid(storageID, invalid: false)
            }
    }

    private func apply(_ newText: String) {
        switch parse(newText) {
        case .valid(let newValue):
            setInvalid(false)
            if value != newValue {
                value = newValue
            }
        case .incomplete:
            setInvalid(false)
        case .invalid:
            setInvalid(true)
        }
    }

    private var storageID: String { "\(fieldNamespace).\(fieldID)" }

    private func setInvalid(_ newValue: Bool) {
        guard invalid != newValue else { return }
        invalid = newValue
        model.setNumericFieldInvalid(storageID, invalid: newValue)
    }
}
