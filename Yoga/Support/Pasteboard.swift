import UIKit

enum Pasteboard {
    /// A url from the clipboard, either as a url item or as plain text.
    static func url() -> URL? {
        let pasteboard = UIPasteboard.general

        if let url = pasteboard.url {
            return url
        }

        guard let text = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text),
              url.scheme?.hasPrefix("http") == true
        else {
            return nil
        }

        return url
    }
}
