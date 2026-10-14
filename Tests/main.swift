import Foundation

var failures = 0
var checks = 0
func check(_ name: String, _ body: () throws -> Bool) {
    checks += 1
    do {
        if try body() { print("PASS: \(name)") }
        else { failures += 1; print("FAIL: \(name)") }
    } catch { failures += 1; print("FAIL: \(name): \(error)") }
}
func rejected(_ body: () throws -> Void) -> Bool {
    do { try body(); return false } catch { return true }
}
let fm = FileManager.default
let base = URL(fileURLWithPath: "/private/tmp/mantenimiento-test-\(UUID())")
try fm.createDirectory(at: base, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: base) }
let root = base.appendingPathComponent("Caches")
let item = root.appendingPathComponent("com.example.app")
try fm.createDirectory(at: item, withIntermediateDirectories: true)
try Data(repeating: 1, count: 11).write(to: item.appendingPathComponent("data"))
let outside = base.appendingPathComponent("private-data")
try Data(repeating: 2, count: 100).write(to: outside)
try fm.createSymbolicLink(at: item.appendingPathComponent("external"), withDestinationURL: outside)
let policy = CachePolicy(roots: [root])
check("permite hijo inmediato") { try policy.validate(item); return true }
check("rechaza raíz") { rejected { try policy.validate(root) } }
check("rechaza hijo anidado") { rejected { try policy.validate(item.appendingPathComponent("data")) } }
check("rechaza fuera de cachés") { rejected { try policy.validate(outside) } }
let link = root.appendingPathComponent("alias")
try fm.createSymbolicLink(at: link, withDestinationURL: outside)
check("rechaza enlace seleccionado") { rejected { try policy.validate(link) } }
let aliasRoot = base.appendingPathComponent("AliasCaches")
try fm.createSymbolicLink(at: aliasRoot, withDestinationURL: root)
check("rechaza ancestro simbólico") {
    rejected { try CachePolicy(roots: [aliasRoot]).validate(aliasRoot.appendingPathComponent("com.example.app")) }
}
check("mide bytes sin seguir enlaces") {
    let m = try CacheScanner.measure(item, cancelled: { false })
    return m.bytes == 11 && !m.incomplete
}
check("archivo regular medido") {
    try CacheScanner.measure(outside, cancelled: { false }).bytes == 100
}
check("cancelación interrumpe análisis") {
    rejected { _ = try CacheScanner.measure(item, cancelled: { true }) }
}
check("inaccesible o inexistente no se informa como cero exacto") {
    rejected { _ = try CacheScanner.measure(base.appendingPathComponent("missing"), cancelled: { false }) }
}
let fixture = Data(#"{"formulae":[{"name":"wget","full_name":"wget","installed":[{"version":"1.25.0"}]}],"casks":[{"token":"sample","name":["Sample"],"version":"2.0","installed":"2.0","artifacts":[{"app":["Sample.app"]}]}]}"#.utf8)
check("parser conserva fórmulas instaladas y versión") {
    let p = try BrewParser.parse(fixture)
    return p.contains { $0.name == "wget" && $0.version == "1.25.0" && $0.origin == "Homebrew · fórmula" }
}
check("parser conserva casks y artefactos") {
    let p = try BrewParser.parse(fixture)
    return p.contains { $0.name == "Sample" && $0.artifacts == ["Sample.app"] && $0.origin == "Homebrew · cask" }
}
check("JSON inválido produce incidencia y no inventario vacío") {
    rejected { _ = try BrewParser.parse(Data("broken".utf8)) }
}
let appURL = base.appendingPathComponent("Example.app")
try fm.createDirectory(at: appURL.appendingPathComponent("Contents"), withIntermediateDirectories: true)
let plist: [String: Any] = ["CFBundleName": "Example", "CFBundleIdentifier": "com.example.app", "CFBundleShortVersionString": "3.2"]
let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
try plistData.write(to: appURL.appendingPathComponent("Contents/Info.plist"))
check("lee nombre versión e identificador de .app") {
    let p = try ApplicationReader.read(appURL)
    return p.name == "Example" && p.version == "3.2" && p.bundleID == "com.example.app" && p.path == appURL.path
}
check("análisis asocia identificador exacto y ordena por tamaño") {
    let inventory = InventoryResult(programs: [try ApplicationReader.read(appURL)], brewCache: nil, issues: [], brewStatus: "")
    let result = try Analysis.scan(inventory: inventory, userCacheRoot: root, cancelled: { false }, progress: { _ in })
    return result.entries.first?.url.path == item.path && result.entries.first?.owner == "Example" && result.entries.first?.bytes == 11
}
let destination = base.appendingPathComponent("FakeTrash")
try fm.createDirectory(at: destination, withIntermediateDirectories: true)
check("limpieza rechaza externo y conserva datos") {
    let entry = CacheEntry(url: outside, owner: "", bundleID: nil, bytes: 100, incomplete: false, blockedReason: nil)
    let results = Cleaner.clean(entries: [entry], roots: [root], runningBundles: { [] }, operation: { source in
        try fm.moveItem(at: source, to: destination.appendingPathComponent(source.lastPathComponent))
    })
    return results.first?.success == false && fm.fileExists(atPath: outside.path)
}
check("limpieza excluye aplicación abierta al confirmar") {
    let entry = CacheEntry(url: item, owner: "Example", bundleID: "com.example.app", bytes: 11, incomplete: false, blockedReason: nil)
    let result = Cleaner.clean(entries: [entry], roots: [root], runningBundles: { ["com.example.app"] }, operation: { source in
        try fm.moveItem(at: source, to: destination.appendingPathComponent(source.lastPathComponent))
    })
    return result.first?.success == false && fm.fileExists(atPath: item.path)
}
check("limpieza válida traslada solamente selección a destino de prueba") {
    let disposable = root.appendingPathComponent("disposable")
    try Data([1, 2, 3]).write(to: disposable)
    let entry = CacheEntry(url: disposable, owner: "", bundleID: nil, bytes: 3, incomplete: false, blockedReason: nil)
    let result = Cleaner.clean(entries: [entry], roots: [root], runningBundles: { [] }, operation: { source in
        try fm.moveItem(at: source, to: destination.appendingPathComponent(source.lastPathComponent))
    })
    guard result.first?.success == true, !fm.fileExists(atPath: disposable.path) else { return false }
    let moved = try Data(contentsOf: destination.appendingPathComponent("disposable"))
    return moved == Data([1, 2, 3]) && fm.fileExists(atPath: outside.path)
}
let targeted = Data(#"{"formulae":[],"casks":[{"token":"sample","name":["Sample"],"version":"2.0","installed":"2.0","artifacts":[{"app":["Sample.app"],"target":"/Custom/Apps/Renamed.app"}]}]}"#.utf8)
check("cask conserva destino explícito personalizado") {
    try BrewParser.parse(targeted).first?.artifacts == ["/Custom/Apps/Renamed.app"]
}
check("tamaño cero evita palabras en inglés") { formatBytes(0) == "0 B" }
check("límite de tiempo detiene proceso") {
    rejected { _ = try ProcessRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["5"], cancelled: { false }, timeout: 0.1) }
}
check("inventario conserva identidad Homebrew para desinstalación") {
    let p = try BrewParser.parse(fixture)
    return p.first?.brew == BrewIdentity(token: "wget", kind: .formula) &&
        p.last?.brew == BrewIdentity(token: "sample", kind: .cask)
}
check("fusión conserva token del cask en aplicación local") {
    var app = try ApplicationReader.read(appURL)
    app.path = "/Custom/Apps/Renamed.app"
    let merged = Inventory.associate(applications: [app], packages: try BrewParser.parse(targeted))
    return merged.count == 1 && merged[0].brew == BrewIdentity(token: "sample", kind: .cask) && merged[0].bundleID == "com.example.app"
}
runUninstallTests(base)
runBatchTests(base)
print("\(checks - failures)/\(checks) comprobaciones aprobadas")
exit(failures == 0 ? 0 : 1)
