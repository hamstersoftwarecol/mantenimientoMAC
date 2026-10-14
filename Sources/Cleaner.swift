import Foundation
import AppKit

struct CleanOutcome: Identifiable {
    var id: String { path }
    var path: String
    var success: Bool
    var detail: String
}
enum Cleaner {
    static func clean(entries: [CacheEntry], roots: [URL], runningBundles: () -> Set<String>, operation: (URL) throws -> Void = { url in
        _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }) -> [CleanOutcome] {
        let policy = CachePolicy(roots: roots)
        var seen = Set<String>()
        return entries.filter { seen.insert($0.id).inserted }.map { entry in
            do {
                guard entry.blockedReason == nil else { throw InventoryError.process(entry.blockedReason!) }
                if let bundleID = entry.bundleID, runningBundles().contains(bundleID) {
                    throw InventoryError.process("La aplicación está abierta. Ciérrala y vuelve a analizar.")
                }
                try policy.validate(entry.url)
                try operation(entry.url)
                return CleanOutcome(path: entry.url.path, success: true, detail: "Enviado a la Papelera.")
            } catch {
                return CleanOutcome(path: entry.url.path, success: false, detail: error.localizedDescription)
            }
        }
    }
}
