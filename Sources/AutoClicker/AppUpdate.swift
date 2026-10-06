import Foundation

struct AvailableUpdate: Equatable {
    var version: String
    var downloadURL: URL
}

enum AppVersion {
    static func current(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let trimmed = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "0.0.0" : trimmed
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = components(candidate)
        let right = components(current)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let newer = index < left.count ? left[index] : 0
            let installed = index < right.count ? right[index] : 0
            if newer != installed { return newer > installed }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        var text = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("v") {
            text.removeFirst()
        }
        return text.split(separator: ".").map { part in
            Int(part) ?? 0
        }
    }
}

enum ReleaseFeed {
    static let assetName = "AutoClicker-macos.zip"

    static func availableUpdate(from data: Data, currentVersion: String) -> AvailableUpdate? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = json["tag_name"] as? String
        else { return nil }

        let version = tag.lowercased().hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard AppVersion.isNewer(version, than: currentVersion) else { return nil }
        guard
            let assets = json["assets"] as? [[String: Any]],
            let asset = assets.first(where: { $0["name"] as? String == assetName }),
            let urlString = asset["browser_download_url"] as? String,
            let url = URL(string: urlString)
        else { return nil }

        return AvailableUpdate(version: version, downloadURL: url)
    }
}

struct GitHubUpdateClient: Sendable {
    var session: URLSession = .shared
    var latestReleaseURL = URL(string: "https://api.github.com/repos/bear-seal-os/auto-clicker/releases/latest")!

    func availableUpdate(currentVersion: String) async -> AvailableUpdate? {
        var request = URLRequest(url: latestReleaseURL)
        request.timeoutInterval = 20
        request.setValue("AutoClicker", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard
            let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse,
            http.statusCode == 200
        else { return nil }
        return ReleaseFeed.availableUpdate(from: data, currentVersion: currentVersion)
    }
}

enum UpdateError: Error {
    case downloadFailed
    case unzipFailed
    case invalidArchive
    case installFailed
}

enum AppBundleUpdater {
    static func install(update: AvailableUpdate, replacing appURL: URL, session: URLSession = .shared) async throws {
        let zip = try await download(update.downloadURL, session: session)
        let newApp = try unarchiveApp(from: zip)
        try swapAfterExit(newApp: newApp, destination: appURL)
    }

    private static func download(_ url: URL, session: URLSession) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue("AutoClicker", forHTTPHeaderField: "User-Agent")
        let (temp, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.downloadFailed
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoClicker-\(UUID().uuidString).zip")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }

    private static func unarchiveApp(from zipURL: URL) throws -> URL {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoClicker-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, work.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.unzipFailed }
        let app = work.appendingPathComponent("AutoClicker.app")
        guard FileManager.default.fileExists(atPath: app.path) else { throw UpdateError.invalidArchive }
        return app
    }

    /// Replaces the running bundle after this process exits. `nohup` keeps the
    /// swap alive across quit.
    private static func swapAfterExit(newApp: URL, destination: URL) throws {
        let command = swapScript(
            pid: ProcessInfo.processInfo.processIdentifier,
            newApp: newApp,
            destination: destination
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "nohup /bin/bash -c \(shellQuote(command)) >/dev/null 2>&1 &"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.installFailed }
    }

    private static func swapScript(pid: Int32, newApp: URL, destination: URL) -> String {
        let dest = shellQuote(destination.path)
        let stage = shellQuote(destination.path + ".new")
        let backup = shellQuote(destination.path + ".bak")
        let source = shellQuote(newApp.path)
        let work = shellQuote(newApp.deletingLastPathComponent().path)
        return """
        i=0
        while [ "$i" -lt 150 ]; do
          kill -0 \(pid) 2>/dev/null || break
          sleep 0.2
          i=$((i + 1))
        done
        if kill -0 \(pid) 2>/dev/null; then
          exit 1
        fi
        sleep 0.4
        /bin/rm -rf \(backup) \(stage)
        /usr/bin/ditto \(source) \(stage)
        if ! /bin/mv \(dest) \(backup); then
          /bin/rm -rf \(stage)
          exit 1
        fi
        if ! /bin/mv \(stage) \(dest); then
          /bin/mv \(backup) \(dest) || true
          exit 1
        fi
        /usr/bin/xattr -dr com.apple.quarantine \(dest) || true
        /usr/bin/open \(dest)
        /bin/rm -rf \(backup) \(work)
        """
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
