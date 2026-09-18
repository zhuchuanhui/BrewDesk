import SwiftUI
import Foundation

@main
struct BrewDeskApp: App {
    var body: some Scene {
        WindowGroup("BrewDesk") { ContentView() }
            .windowResizability(.contentSize)
    }
}

@MainActor
final class BrewModel: ObservableObject {
    @Published var output = "準備完了"
    @Published var isRunning = false
    @Published var outdated = ""
    @Published var lastAction = ""
    @Published var packages: [BrewPackage] = []
    @Published var mirrors: [BrewMirror] = BrewMirror.defaults
    @Published var selectedMirror = "公式"
    @Published var mirrorMessage = ""
    @Published var newMirrorName = ""
    @Published var newMirrorURL = ""

    init() { loadMirrors() }

    func loadMirrors() {
        if let data = UserDefaults.standard.data(forKey: "mirrors"), let saved = try? JSONDecoder().decode([BrewMirror].self, from: data) { mirrors = saved }
        selectedMirror = UserDefaults.standard.string(forKey: "selectedMirror") ?? "公式"
    }

    func saveMirrors() { if let data = try? JSONEncoder().encode(mirrors) { UserDefaults.standard.set(data, forKey: "mirrors") }; UserDefaults.standard.set(selectedMirror, forKey: "selectedMirror") }

    func applyMirror(_ mirror: BrewMirror) {
        selectedMirror = mirror.name; saveMirrors()
        let profile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zprofile")
        var text = (try? String(contentsOf: profile, encoding: .utf8)) ?? ""
        let begin = "# BrewDesk mirror settings"
        if let start = text.range(of: begin), let end = text.range(of: "# End BrewDesk mirror settings", range: start.upperBound..<text.endIndex) { text.removeSubrange(start.lowerBound..<end.upperBound) }
        let block = "\n\(begin)\n\(mirror.exports)\n# End BrewDesk mirror settings\n"
        text.append(block); try? text.write(to: profile, atomically: true, encoding: .utf8)
        mirrorMessage = "「\(mirror.name)」を保存しました。新しいターミナルから反映されます。"
    }

    func addMirror() {
        let url = newMirrorURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !newMirrorName.isEmpty, let valid = URL(string: "https://\(url)") else { mirrorMessage = "名前とURLを入力してください。"; return }
        mirrors.append(BrewMirror(name: newMirrorName, baseURL: valid.absoluteString)); saveMirrors(); newMirrorName = ""; newMirrorURL = ""; mirrorMessage = "ミラーを追加しました。接続テストを実行してください。"
    }

    func testMirror(_ mirror: BrewMirror) {
        mirrorMessage = "接続テスト中…"
        Task { do { var request = URLRequest(url: URL(string: mirror.baseURL)!) ; request.httpMethod = "HEAD"; request.timeoutInterval = 8; _ = try await URLSession.shared.data(for: request); mirrorMessage = "\(mirror.name): 接続できました" } catch { mirrorMessage = "\(mirror.name): 接続できませんでした" } }
    }

    func run(_ args: [String], label: String) {
        guard !isRunning else { return }
        isRunning = true; lastAction = label; output = "実行中…"
        let activeMirror = mirrors.first(where: { $0.name == selectedMirror }) ?? BrewMirror.defaults[0]
        Task.detached { [args, activeMirror] in
            let result: String
            do {
                let p = Process(); let pipe = Pipe()
                p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
                if !FileManager.default.fileExists(atPath: p.executableURL!.path) { p.executableURL = URL(fileURLWithPath: "/usr/local/bin/brew") }
                p.arguments = args; p.standardOutput = pipe; p.standardError = pipe
                var environment = ProcessInfo.processInfo.environment
                environment.removeValue(forKey: "HOMEBREW_API_DOMAIN")
                environment.removeValue(forKey: "HOMEBREW_BOTTLE_DOMAIN")
                environment.removeValue(forKey: "HOMEBREW_PIP_INDEX_URL")
                if activeMirror.name != "公式" {
                    environment["HOMEBREW_API_DOMAIN"] = "\(activeMirror.baseURL)/homebrew-bottles/api"
                    environment["HOMEBREW_BOTTLE_DOMAIN"] = "\(activeMirror.baseURL)/homebrew/homebrew-bottles"
                }
                p.environment = environment
                try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
                result = String(data: data, encoding: .utf8) ?? "出力を読み取れませんでした"
            } catch { result = "実行できませんでした: \(error.localizedDescription)" }
            await MainActor.run { self.output = result; self.packages = BrewPackage.parse(result); self.isRunning = false }
        }
    }

    func check() { run(["outdated", "--verbose"], label: "更新を確認") }
    func update() { run(["update"], label: "Homebrewを更新") }
    func upgrade() { run(["upgrade"], label: "パッケージを更新") }
    func doctor() { run(["doctor"], label: "診断を実行") }
    func upgrade(_ package: BrewPackage) { run(["upgrade", package.name], label: "\(package.name)を更新") }
}

struct BrewPackage: Identifiable, Equatable {
    let id = UUID(); let name: String; let current: String; let latest: String; let kind: String
    static func parse(_ text: String) -> [BrewPackage] {
        text.split(separator: "\n").compactMap { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            if let range = s.range(of: " < ") { let a = String(s[..<range.lowerBound]); let b = String(s[range.upperBound...]); let parts = a.split(separator: " ", maxSplits: 1); if parts.count == 2 { return BrewPackage(name: String(parts[0]), current: String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "()")), latest: b, kind: "formula") } }
            if let range = s.range(of: " != ") { let a = String(s[..<range.lowerBound]); let b = String(s[range.upperBound...]); let parts = a.split(separator: " ", maxSplits: 1); if parts.count == 2 { return BrewPackage(name: String(parts[0]), current: String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "()")), latest: b, kind: "cask") } }
            return nil
        }
    }
}

struct BrewMirror: Codable, Identifiable, Equatable {
    var id: String { name }; let name: String; let baseURL: String
    var exports: String { name == "公式" ? "unset HOMEBREW_API_DOMAIN\nunset HOMEBREW_BOTTLE_DOMAIN\nunset HOMEBREW_PIP_INDEX_URL" : "export HOMEBREW_API_DOMAIN=\(baseURL)/homebrew-bottles/api\nexport HOMEBREW_BOTTLE_DOMAIN=\(baseURL)/homebrew/homebrew-bottles\nunset HOMEBREW_PIP_INDEX_URL" }
    static let defaults = [BrewMirror(name: "公式", baseURL: "https://github.com"), BrewMirror(name: "清華大学", baseURL: "https://mirrors.tuna.tsinghua.edu.cn"), BrewMirror(name: "阿里云", baseURL: "https://mirrors.aliyun.com")]
}

struct ContentView: View {
    @StateObject private var model = BrewModel()
    @State private var showUpgradeAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "shippingbox.fill").font(.system(size: 28)).foregroundStyle(.orange)
                VStack(alignment: .leading) { Text("BrewDesk").font(.title2.bold()); Text("Homebrew 管理").foregroundStyle(.secondary) }
                Spacer(); if model.isRunning { ProgressView().controlSize(.small) }
            }
            Divider()
            HStack(spacing: 10) {
                Button("更新を確認") { model.check() }.keyboardShortcut("r")
                Button("Homebrewを更新") { model.update() }
                Button("パッケージを更新") { showUpgradeAlert = true }.tint(.orange)
                Menu("その他") { Button("診断を実行") { model.doctor() } }
            }
            MirrorView(model: model)
            if !model.lastAction.isEmpty { Text(model.lastAction).font(.caption).foregroundStyle(.secondary) }
            if !model.packages.isEmpty {
                Text("更新可能なパッケージ（\(model.packages.count)件）").font(.headline)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.packages) { package in
                            HStack { Image(systemName: package.kind == "cask" ? "macwindow" : "shippingbox").foregroundStyle(.orange).frame(width: 22); Text(package.name).frame(width: 150, alignment: .leading); Text(package.kind == "cask" ? "アプリ" : "formula").font(.caption).foregroundStyle(.secondary).frame(width: 60); Text(package.current).foregroundStyle(.secondary); Image(systemName: "arrow.right").font(.caption); Text(package.latest); Spacer(); Button("更新") { model.upgrade(package) }.controlSize(.small) }.padding(.vertical, 5)
                            Divider()
                        }
                    }
                }.frame(maxHeight: 170).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
            ScrollView { Text(model.output).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                .frame(minWidth: 680, minHeight: 360).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            Text("sudoを使う処理は実行しません。必要な権限がある場合はターミナルで確認してください。").font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(width: 760, height: 650)
        .alert("パッケージを更新しますか？", isPresented: $showUpgradeAlert) {
            Button("更新する") { model.upgrade() }; Button("キャンセル", role: .cancel) {}
        } message: { Text("インストール済みのformulaとcaskをHomebrewで更新します。") }
    }
}

struct MirrorView: View {
    @ObservedObject var model: BrewModel
    var body: some View {
        GroupBox("ミラー管理") {
            HStack { Picker("使用するミラー", selection: $model.selectedMirror) { ForEach(model.mirrors) { Text($0.name).tag($0.name) } }.onChange(of: model.selectedMirror) { _, name in if let m = model.mirrors.first(where: {$0.name == name}) { model.applyMirror(m) } }; Button("接続テスト") { if let m = model.mirrors.first(where: {$0.name == model.selectedMirror}) { model.testMirror(m) } } }
            HStack { TextField("ミラー名", text: $model.newMirrorName); TextField("https://example.com", text: $model.newMirrorURL); Button("追加") { model.addMirror() } }
            if !model.mirrorMessage.isEmpty { Text(model.mirrorMessage).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
