import SwiftUI
import WebKit

struct ShellRootView: View {
    @StateObject private var model = ShellModel()

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: ShellTheme.background).ignoresSafeArea()
            WebShellView(model: model)
            if model.progress < 0.98 {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .tint(Color(uiColor: ShellTheme.accent))
                    .frame(height: 2)
            }
        }
    }
}

struct WebShellView: UIViewRepresentable {
    let model: ShellModel

    func makeUIView(context: Context) -> WKWebView {
        model.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

enum ShellTheme {
    static var background: UIColor {
        color(for: "YLBackgroundColor", fallback: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1))
    }

    static var accent: UIColor {
        color(for: "YLAccentColor", fallback: UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1))
    }

    private static func color(for key: String, fallback: UIColor) -> UIColor {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return fallback }
        let hex = raw.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return fallback }
        return UIColor(
            red: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}
