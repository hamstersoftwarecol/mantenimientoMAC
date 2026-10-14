import Foundation

struct CacheEntry: Identifiable {
    var id: String { url.path }
    var url: URL
    var owner: String
    var bundleID: String?
    var bytes: Int64
    var incomplete: Bool
    var blockedReason: String?
}
struct ScanResult {
    var inventory: InventoryResult
    var entries: [CacheEntry]
    var roots: [URL]
    var issues: [String]
}
enum Analysis {
    static func scan(inventory: InventoryResult, userCacheRoot: URL, cancelled: () -> Bool, progress: (String) -> Void) throws -> ScanResult {
        let fm = FileManager.default
        var roots = [userCacheRoot]
        if let brew = inventory.brewCache,
           brew.path != userCacheRoot.path, !brew.path.hasPrefix(userCacheRoot.path + "/") {
            if userCacheRoot.path.hasPrefix(brew.path + "/") { roots = [brew] }
            else { roots.append(brew) }
        }
        var entries: [CacheEntry] = []
        var issues = inventory.issues
        let policy = CachePolicy(roots: roots)
        for root in roots {
            if cancelled() { throw MaintenanceError.cancelled }
            do {
                let attributes = try fm.attributesOfItem(atPath: root.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                    throw MaintenanceError.unsafePath
                }
                let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                for url in children {
                    if cancelled() { throw MaintenanceError.cancelled }
                    progress("Midiendo \(url.lastPathComponent)…")
                    let app = inventory.programs.first { $0.bundleID != nil && $0.bundleID == url.lastPathComponent }
                    let isBrew = inventory.brewCache.map { $0.path == url.path || root.path == $0.path } ?? false
                    var entry = CacheEntry(url: url, owner: isBrew ? "Homebrew" : app?.name ?? "Sin identificar",
                                           bundleID: app?.bundleID, bytes: 0, incomplete: false, blockedReason: nil)
                    do {
                        try policy.validate(url)
                        let size = try CacheScanner.measure(url, cancelled: cancelled)
                        entry.bytes = size.bytes
                        entry.incomplete = size.incomplete
                        if size.incomplete { issues.append("Medición incompleta: \(url.path)") }
                    } catch MaintenanceError.cancelled { throw MaintenanceError.cancelled }
                    catch {
                        entry.incomplete = true
                        entry.blockedReason = error.localizedDescription
                        issues.append("\(url.path): \(error.localizedDescription)")
                    }
                    entries.append(entry)
                }
            } catch MaintenanceError.cancelled { throw MaintenanceError.cancelled }
            catch { issues.append("\(root.path): \(error.localizedDescription)") }
        }
        return ScanResult(inventory: inventory, entries: entries.sorted {
            $0.bytes == $1.bytes ? $0.url.path < $1.url.path : $0.bytes > $1.bytes
        }, roots: roots, issues: issues)
    }
}
