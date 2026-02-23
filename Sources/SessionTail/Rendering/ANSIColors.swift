/// ANSI escape code helpers for terminal output.
enum ANSIColor: String, Sendable {
    case reset = "\u{1B}[0m"
    case bold = "\u{1B}[1m"
    case dim = "\u{1B}[2m"
    case underline = "\u{1B}[4m"

    // Foreground colors
    case red = "\u{1B}[31m"
    case green = "\u{1B}[32m"
    case yellow = "\u{1B}[33m"
    case blue = "\u{1B}[34m"
    case magenta = "\u{1B}[35m"
    case cyan = "\u{1B}[36m"
    case white = "\u{1B}[37m"
    case gray = "\u{1B}[90m"

    // Bright foreground colors
    case brightGreen = "\u{1B}[92m"
    case brightYellow = "\u{1B}[93m"
    case brightBlue = "\u{1B}[94m"
    case brightMagenta = "\u{1B}[95m"
    case brightCyan = "\u{1B}[96m"
}


/// Wrap a string in ANSI color codes.
func styled(_ text: String, _ colors: ANSIColor...) -> String {
    let prefix = colors.map(\.rawValue).joined()
    return "\(prefix)\(text)\(ANSIColor.reset.rawValue)"
}


/// A horizontal rule for visual separation.
func separator(width: Int = 60) -> String {
    styled(String(repeating: "─", count: width), .dim)
}
