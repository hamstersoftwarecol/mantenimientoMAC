import Foundation

struct Measurement { var bytes: Int64; var incomplete: Bool }
enum MaintenanceError: LocalizedError {
    case unsafePath, cancelled
    var errorDescription: String? {
        switch self {
        case .unsafePath: return "Ruta no autorizada o enlace simbólico."
        case .cancelled: return "Análisis cancelado."
        }
    }
}
struct CachePolicy {
    let roots: [URL]
    func validate(_ url: URL) throws {
        let candidate = url
        guard url.isFileURL, !url.pathComponents.contains(".."), !url.pathComponents.contains("."),
              roots.contains(where: { $0.path == (candidate.path as NSString).deletingLastPathComponent })
        else { throw MaintenanceError.unsafePath }
        try PathSafety.rejectSymbolicAncestors(candidate)
    }
}
enum PathSafety {
    static func rejectSymbolicAncestors(_ url: URL) throws {
        guard url.isFileURL, !url.pathComponents.contains(".."), !url.pathComponents.contains(".") else { throw MaintenanceError.unsafePath }
        var current = url.path
        while current != "/" {
            let attributes = try FileManager.default.attributesOfItem(atPath: current)
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                throw MaintenanceError.unsafePath
            }
            current = (current as NSString).deletingLastPathComponent
        }
    }
}
enum CacheScanner {
    static func measure(_ url: URL, cancelled: () -> Bool) throws -> Measurement {
        if cancelled() { throw MaintenanceError.cancelled }
        let fm = FileManager.default
        let attributes = try fm.attributesOfItem(atPath: url.path)
        let type = attributes[.type] as? FileAttributeType
        if type == .typeSymbolicLink { return Measurement(bytes: 0, incomplete: false) }
        if type == .typeRegular {
            return Measurement(bytes: (attributes[.size] as? NSNumber)?.int64Value ?? 0, incomplete: false)
        }
        guard type == .typeDirectory else { return Measurement(bytes: 0, incomplete: true) }
        var incomplete = false
        var bytes: Int64 = 0
        guard let walker = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in
            incomplete = true
            return true
        }) else { throw MaintenanceError.unsafePath }
        while let child = walker.nextObject() as? URL {
            if cancelled() { throw MaintenanceError.cancelled }
            do {
                let values = try fm.attributesOfItem(atPath: child.path)
                let childType = values[.type] as? FileAttributeType
                if childType == .typeSymbolicLink { walker.skipDescendants(); continue }
                if childType == .typeRegular { bytes += (values[.size] as? NSNumber)?.int64Value ?? 0 }
            } catch { incomplete = true; walker.skipDescendants() }
        }
        return Measurement(bytes: bytes, incomplete: incomplete)
    }
}

final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
}

func formatBytes(_ value: Int64) -> String {
    if value == 0 { return "0 B" }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: value)
}
