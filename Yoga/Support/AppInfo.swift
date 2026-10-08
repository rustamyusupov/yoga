import Foundation

enum AppInfo {
    static let version: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        return "v\(version)"
    }()
}
