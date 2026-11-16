import Foundation

/// Kullanıcıya gösterilen hatalar. Mesajlar Türkçedir.
public enum JournalError: Error, LocalizedError, Equatable {
    case vaultMissing(String)
    case configUnreadable(String, String)
    case stateUnwritable(String, String)
    case noRepos([String])
    case invalidDate(String)
    case futureDate(String)
    case markerCorrupt(String)
    case outsideVault(String)
    case writeFailed(String, String)
    case invalidScheduleTime(String)
    case scheduler(String)
    case usage(String)

    public var errorDescription: String? {
        switch self {
        case .vaultMissing(let path):
            return "Obsidian kasası bulunamadı: \(path)\nconfig.json içindeki \"vault\" değerini düzeltin."
        case .configUnreadable(let path, let reason):
            return "Ayar dosyası okunamadı: \(path)\n\(reason)\nDosyayı düzeltin ya da silin; silinirse varsayılanlarla yeniden oluşturulur."
        case .stateUnwritable(let path, let reason):
            return "Durum dosyası yazılamadı: \(path)\n\(reason)"
        case .noRepos(let roots):
            return "Hiç git deposu bulunamadı. Aranan klasörler: \(roots.joined(separator: ", "))\nconfig.json içindeki \"roots\" listesini kontrol edin."
        case .invalidDate(let text):
            return "Geçersiz tarih: \(text). Biçim YYYY-MM-DD olmalı, örneğin 2026-11-16."
        case .futureDate(let text):
            return "Gelecekteki bir tarih için not yazılamaz: \(text)"
        case .markerCorrupt(let path):
            return "Notta başlangıç işareti var ama bitiş işareti yok, dosyaya dokunulmadı: \(path)\n\"\(MarkerBlock.start)\" satırından sonra \"\(MarkerBlock.end)\" satırını ekleyin ya da başlangıç işaretini silin."
        case .outsideVault(let path):
            return "Hedef dosya kasanın dışında kalıyor, yazılmadı: \(path)"
        case .writeFailed(let path, let reason):
            return "Dosya yazılamadı: \(path)\n\(reason)"
        case .invalidScheduleTime(let text):
            return "Geçersiz saat: \(text). config.json içindeki \"scheduleTime\" SS:dd biçiminde olmalı, örneğin 23:30."
        case .scheduler(let message):
            return message
        case .usage(let message):
            return message
        }
    }
}
