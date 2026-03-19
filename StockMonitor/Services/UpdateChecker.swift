import Foundation
import AppKit
import Combine

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: String
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

@MainActor
final class UpdateChecker: ObservableObject {

    static let shared = UpdateChecker()
    private init() {}

    @Published var isBusy   = false
    @Published var status   = ""

    /// 入口：点击"检查更新"后调用
    func checkAndUpdate() {
        guard !isBusy else { return }
        isBusy  = true
        status  = "正在检查…"
        Task { await run() }
    }

    // MARK: - 主流程

    private func run() async {
        defer { if !isBusy { status = "" } }

        // 1. 获取最新 release
        guard let url = URL(string: "https://api.github.com/repos/VGEAREN/Stockbar/releases/latest") else { return finish("检查失败") }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            return finish("检查失败，请检查网络")
        }

        let latestTag = release.tagName
        let latest  = latestTag.hasPrefix("v") ? String(latestTag.dropFirst()) : latestTag
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        guard isNewer(latest, than: current) else {
            return finish("已是最新版本")
        }

        // 2. 找到 DMG 下载地址
        guard let dmgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }),
              let downloadURL = URL(string: dmgAsset.browserDownloadUrl) else {
            return finish("未找到安装包")
        }

        // 3. 下载 + 安装
        status = "正在下载 v\(latest)…"
        await downloadAndInstall(url: downloadURL, version: latest)
    }

    // MARK: - 下载安装

    private func downloadAndInstall(url: URL, version: String) async {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("StockbarUpdate-\(UUID().uuidString)")
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 下载 DMG
        let dmgPath = tempDir.appendingPathComponent("Stockbar.dmg")
        do {
            let (localURL, _) = try await URLSession.shared.download(from: url)
            try fm.moveItem(at: localURL, to: dmgPath)
        } catch {
            return finish("下载失败")
        }

        status = "正在安装…"

        // 挂载 DMG
        let mountPoint = tempDir.appendingPathComponent("vol").path
        try? fm.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)
        guard shell("/usr/bin/hdiutil", "attach", dmgPath.path, "-mountpoint", mountPoint, "-nobrowse", "-quiet") == 0 else {
            return finish("挂载失败")
        }

        // 找到 .app
        let sourceApp = "\(mountPoint)/Stockbar.app"
        guard fm.fileExists(atPath: sourceApp) else {
            shell("/usr/bin/hdiutil", "detach", mountPoint, "-quiet")
            return finish("安装包异常")
        }

        // 复制到临时目录
        let newApp = tempDir.appendingPathComponent("Stockbar.app").path
        do {
            try fm.copyItem(atPath: sourceApp, toPath: newApp)
        } catch {
            shell("/usr/bin/hdiutil", "detach", mountPoint, "-quiet")
            return finish("复制失败")
        }
        shell("/usr/bin/hdiutil", "detach", mountPoint, "-quiet")

        // 写替换脚本并执行
        let currentApp = Bundle.main.bundlePath
        let script = """
        #!/bin/bash
        sleep 1
        rm -rf "\(currentApp)"
        cp -R "\(newApp)" "\(currentApp)"
        open "\(currentApp)"
        rm -rf "\(tempDir.path)"
        """
        let scriptPath = tempDir.appendingPathComponent("update.sh").path
        try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        shell("/bin/chmod", "+x", scriptPath)

        status = "正在重启…"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptPath]
        try? proc.run()

        NSApplication.shared.terminate(nil)
    }

    // MARK: - 辅助

    private func finish(_ msg: String) {
        status = msg
        isBusy = false
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if status == msg { status = "" }
        }
    }

    @discardableResult
    private func shell(_ args: String...) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: args[0])
        proc.arguments = Array(args.dropFirst())
        try? proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus
    }

    /// 逐段比较语义版本
    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap  { Int($0) }
        let len = max(r.count, l.count)
        for i in 0..<len {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }
}
