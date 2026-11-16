import Foundation

/// Aracın sahip olduğu tek bölge: iki işaret satırı ve arası.
/// Bütün işlemler bayt düzeyinde yapılır; işaretlerin dışındaki baytlar aynen kopyalanır.
public enum MarkerBlock {
    public static let start = "<!-- bk-journal:start -->"
    public static let end = "<!-- bk-journal:end -->"

    private static let startData = Data(start.utf8)
    private static let endData = Data(end.utf8)

    /// Gövdeyi işaretlerle sarar.
    public static func wrap(_ body: String) -> String {
        start + "\n" + body.trimmingCharacters(in: .newlines) + "\n" + end
    }

    /// Bloğun (işaretler dahil) bayt aralığı. Blok yoksa nil.
    /// Başlangıç işareti var, ardından bitiş işareti yoksa `nil` yerine hata fırlatılır.
    public static func range(in data: Data, path: String = "") throws -> Range<Int>? {
        let bytes = Data(data) // dizinler 0'dan başlasın
        guard let s = bytes.range(of: startData) else { return nil }
        guard let e = bytes.range(of: endData, in: s.upperBound..<bytes.count) else {
            throw JournalError.markerCorrupt(path)
        }
        return s.lowerBound..<e.upperBound
    }

    /// Nottaki mevcut blok (işaretler dahil).
    public static func existingBlock(in data: Data) -> String? {
        guard let range = try? range(in: data) else { return nil }
        return String(decoding: Data(data)[range], as: UTF8.self)
    }

    /// Blok varsa yalnızca onu değiştirir; yoksa sona ekler. Bloğun dışındaki baytlar değişmez.
    public static func apply(block: String, to existing: Data, path: String = "") throws -> Data {
        let bytes = Data(existing)
        let blockData = Data(block.utf8)
        if let range = try range(in: bytes, path: path) {
            var result = Data()
            result.append(bytes[0..<range.lowerBound])
            result.append(blockData)
            result.append(bytes[range.upperBound..<bytes.count])
            return result
        }
        var result = bytes
        let newline = UInt8(ascii: "\n")
        if !bytes.isEmpty {
            // Mevcut metinle blok arasında bir boş satır bırakılır; var olan baytlara dokunulmaz.
            if bytes.last != newline { result.append(newline) }
            let endsWithBlankLine = bytes.count >= 2 && bytes[bytes.count - 1] == newline && bytes[bytes.count - 2] == newline
            if !endsWithBlankLine { result.append(newline) }
        }
        result.append(blockData)
        result.append(newline)
        return result
    }
}
