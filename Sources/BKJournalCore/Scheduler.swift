import Foundation

/// Günlük çalıştırma için kullanıcı LaunchAgent'ı.
public enum Scheduler {
    public static let label = "local.bkjournal"

    public static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var domain: String { "gui/\(getuid())" }

    static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// LaunchAgent dosyasının içeriği: her gün verilen saatte `bkjournal tamamla`.
    public static func plist(executable: String, hour: Int, minute: Int, logPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(xmlEscape(executable))</string>
                <string>tamamla</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Hour</key>
                <integer>\(hour)</integer>
                <key>Minute</key>
                <integer>\(minute)</integer>
            </dict>
            <key>ProcessType</key>
            <string>Background</string>
            <key>StandardOutPath</key>
            <string>\(xmlEscape(logPath))</string>
            <key>StandardErrorPath</key>
            <string>\(xmlEscape(logPath))</string>
        </dict>
        </plist>

        """
    }

    /// Zamanlayıcının çalıştıracağı dosya: kuruluysa `~/.local/bin/bkjournal`, değilse çalışan kopya.
    public static func executablePath() -> (path: String, installed: Bool) {
        let installed = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/bkjournal").path
        if FileManager.default.isExecutableFile(atPath: installed) { return (installed, true) }
        let current = Bundle.main.executablePath ?? CommandLine.arguments[0]
        return (URL(fileURLWithPath: current).resolvingSymlinksInPath().path, false)
    }

    /// LaunchAgent dosyasını yazar ve launchd'ye yükler.
    public static func install(config: Config) throws -> (executable: String, installed: Bool) {
        let (hour, minute) = try config.scheduleHourMinute()
        let executable = executablePath()
        let content = plist(executable: executable.path, hour: hour, minute: minute, logPath: Paths.logFile.path)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createDirectory(at: Paths.dataDirectory, withIntermediateDirectories: true)
            try Data(content.utf8).write(to: plistURL, options: .atomic)
        } catch {
            throw JournalError.writeFailed(plistURL.path, error.localizedDescription)
        }
        // Eski sürüm yüklüyse önce çıkarılır; yüklü değilse hata önemsenmez.
        Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"], timeout: 20)
        let out = Shell.run("/bin/launchctl", ["bootstrap", domain, plistURL.path], timeout: 20)
        guard out.succeeded else {
            throw JournalError.scheduler("Zamanlayıcı yüklenemedi (launchctl bootstrap): \(out.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return (executable.path, executable.installed)
    }

    /// Zamanlayıcıyı launchd'den çıkarır ve dosyasını siler. Dosya vardıysa true döner.
    @discardableResult
    public static func uninstall() throws -> Bool {
        Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"], timeout: 20)
        let fm = FileManager.default
        guard fm.fileExists(atPath: plistURL.path) else { return false }
        do { try fm.removeItem(at: plistURL) } catch {
            throw JournalError.writeFailed(plistURL.path, error.localizedDescription)
        }
        return true
    }

    public static var plistExists: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    /// launchd'de yüklü mü? (salt okunur sorgu)
    public static var isLoaded: Bool {
        Shell.run("/bin/launchctl", ["print", "\(domain)/\(label)"], timeout: 10).succeeded
    }
}
