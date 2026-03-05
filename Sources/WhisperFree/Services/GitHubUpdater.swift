import Foundation
import AppKit
import Combine

class GitHubUpdater: ObservableObject {
    static let shared = GitHubUpdater()
    private let repo = "iddictive/Whisper-Free"
    private let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
    
    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var downloadUrl: String?
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var error: String?
    
    private var downloadTask: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?

    func checkForUpdates(manual: Bool = false) {
        guard !isChecking else { return }
        
        // Check settings
        let defaults = UserDefaults.standard
        let autoCheck = defaults.bool(forKey: "automaticallyChecksForUpdates")
        if !manual && !autoCheck { return }
        
        isChecking = true
        error = nil
        
        print("🔍 Checking for updates at https://api.github.com/repos/\(repo)/releases/latest")
        
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("WhisperKillerUpdater", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false
                guard let data = data, error == nil else { 
                    self?.error = error?.localizedDescription ?? "Network error"
                    return 
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let tagName = json["tag_name"] as? String {
                        
                        let latest = tagName.replacingOccurrences(of: "v", with: "")
                        self?.latestVersion = latest
                        
                        let defaults = UserDefaults.standard
                        let automaticallyDownloadsUpdates = defaults.bool(forKey: "automaticallyDownloadsUpdates")
                        
                        if self?.compareVersions(current: self?.currentVersion ?? "", latest: latest) == true {
                            self?.updateAvailable = true
                            let assets = json["assets"] as? [[String: Any]]
                            let dmgAsset = assets?.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true })
                            self?.downloadUrl = dmgAsset?["browser_download_url"] as? String
                            
                            if manual {
                                self?.showUpdateAlert(version: latest, downloadUrl: self?.downloadUrl)
                            } else if automaticallyDownloadsUpdates {
                                self?.startDownload()
                            }
                        } else if manual {
                            let alert = NSAlert()
                            alert.messageText = "You're up to date!"
                            alert.informativeText = "WhisperKiller \(self?.currentVersion ?? "") is the latest version."
                            alert.runModal()
                        }
                    }
                } catch {
                    self?.error = "JSON error"
                }
            }
        }.resume()
    }

    private func compareVersions(current: String, latest: String) -> Bool {
        return latest.compare(current, options: .numeric) == .orderedDescending
    }

    private func showUpdateAlert(version: String, downloadUrl: String?) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "A new version (\(version)) of WhisperKiller is available. Would you like to download and install it now?"
        alert.addButton(withTitle: "Download & Install")
        alert.addButton(withTitle: "Later")
        
        if alert.runModal() == .alertFirstButtonReturn {
            startDownload()
        }
    }

    func startDownload() {
        guard let urlString = downloadUrl, let url = URL(string: urlString), !isDownloading else { return }
        
        isDownloading = true
        downloadProgress = 0
        error = nil
        
        downloadTask = URLSession.shared.downloadTask(with: url) { [weak self] localURL, _, error in
            DispatchQueue.main.async {
                self?.isDownloading = false
                self?.observation = nil
                
                if let localURL = localURL, error == nil {
                    let tempPath = NSTemporaryDirectory() + "WhisperKillerUpdate.dmg"
                    try? FileManager.default.removeItem(atPath: tempPath)
                    try? FileManager.default.copyItem(at: localURL, to: URL(fileURLWithPath: tempPath))
                    self?.performInstallation(dmgPath: tempPath)
                } else {
                    self?.error = error?.localizedDescription ?? "Download failed"
                }
            }
        }
        
        // Track progress
        observation = downloadTask?.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.downloadProgress = progress.fractionCompleted
            }
        }
        
        downloadTask?.resume()
    }

    private func performInstallation(dmgPath: String) {
        // Show install prompt if it was a background download
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Installation Ready"
            alert.informativeText = "The update has been downloaded. WhisperKiller will close to install the new version."
            alert.addButton(withTitle: "Install & Relaunch")
            alert.addButton(withTitle: "Later")
            
            if alert.runModal() == .alertFirstButtonReturn {
                self.runInstallScript(dmgPath: dmgPath)
            }
        }
    }

    private func runInstallScript(dmgPath: String) {
        let script = """
        mkdir -p /tmp/whisperfree_update
        hdiutil attach "\(dmgPath)" -mountpoint /tmp/whisperfree_update -nobrowse -quiet
        # Force copy even if folder exists
        rm -rf /Applications/WhisperKiller.app
        cp -R /tmp/whisperfree_update/WhisperKiller.app /Applications/
        hdiutil detach /tmp/whisperfree_update -quiet
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                relaunch()
            }
        } catch {
            print("❌ Installation error: \(error)")
        }
    }

    private func relaunch() {
        let appPath = "/Applications/WhisperKiller.app"
        let pid = ProcessInfo.processInfo.processIdentifier
        // Launch a detached script that waits for us to die, then opens the new app
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open \"\(appPath)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }
}
