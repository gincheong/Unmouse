import AppKit
import Combine

final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case failed
    }

    // brew upgrade만으로는 tap을 새로 받지 않는 경우가 있어서 brew update를 먼저 실행한다.
    static let command = "brew update && brew upgrade --cask unmouse"
    static let changelogURL = URL(string: "https://gincheong.github.io/Unmouse/changelog.html")!
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/gincheong/Unmouse/releases/latest")!

    @Published private(set) var state: State = .idle
    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var availableVersion: String? {
        if case .available(let version) = state { return version }
        return nil
    }

    func startAutomaticChecks() {
        if Settings.checkForUpdates { check() }
        let timer = Timer(timeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            if Settings.checkForUpdates { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func check() {
        guard state != .checking else { return }
        state = .checking
        var request = URLRequest(url: Self.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let tag = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                .flatMap { $0["tag_name"] as? String }
            DispatchQueue.main.async {
                guard let self else { return }
                guard let tag else {
                    self.state = .failed
                    return
                }
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let newer = latest.compare(self.currentVersion, options: .numeric) == .orderedDescending
                self.state = newer ? .available(latest) : .upToDate
            }
        }.resume()
    }

    static func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
