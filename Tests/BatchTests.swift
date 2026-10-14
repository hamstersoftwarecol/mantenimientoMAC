import Foundation

func secondProgram(_ s: Scenario) throws -> InstalledProgram {
    let url = s.environment.applicationRoots[0].appendingPathComponent("Second.app")
    try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    let info: [String: Any] = ["CFBundleName": "Second", "CFBundleIdentifier": "com.example.second", "CFBundleShortVersionString": "1.0"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
    return try ApplicationReader.read(url)
}

func runBatchTests(_ base: URL) {
    let fm = FileManager.default
    check("lote analiza dos aplicaciones y conserva residuos sin seleccionar") {
        var s = try scenario(base)
        let second = try secondProgram(s)
        s.environment.inventory.append(second)
        let batch = try BatchUninstaller.analyze(programs: [s.program, second], environment: s.environment)
        let results = BatchUninstaller.execute(batch: batch, selectedResidues: [], environment: { s.environment }, running: { RunningPrograms() }, trash: { source in
            try fm.moveItem(at: source, to: s.fakeTrash.appendingPathComponent(source.lastPathComponent))
        })
        return batch.plans.count == 2 && results.count == 2 && results.allSatisfy { $0.state == .completed } &&
            !fm.fileExists(atPath: s.program.path) && !fm.fileExists(atPath: second.path) && fm.fileExists(atPath: s.data.path)
    }
    check("lote deduplica un mismo programa seleccionado dos veces") {
        let s = try scenario(base)
        let b = try BatchUninstaller.analyze(programs: [s.program, s.program], environment: s.environment)
        return b.plans.count == 1 && b.ready.count == 1
    }
    check("fallo en primer programa no impide completar el siguiente") {
        var s = try scenario(base)
        let second = try secondProgram(s)
        s.environment.inventory.append(second)
        let b = try BatchUninstaller.analyze(programs: [s.program, second], environment: s.environment)
        let r = BatchUninstaller.execute(batch: b, selectedResidues: [s.cache.path], environment: { s.environment }, running: { RunningPrograms() }, trash: { source in
            if source.path == s.program.path { throw InventoryError.process("Sin permiso") }
            try fm.moveItem(at: source, to: s.fakeTrash.appendingPathComponent(source.lastPathComponent))
        })
        return r.count == 2 && r[0].state == .failed && r[1].state == .completed && fm.fileExists(atPath: s.cache.path) && !fm.fileExists(atPath: second.path)
    }
    check("selección externa invalida todo el lote antes de mover programas") {
        var s = try scenario(base)
        let second = try secondProgram(s)
        s.environment.inventory.append(second)
        let b = try BatchUninstaller.analyze(programs: [s.program, second], environment: s.environment)
        var moves = 0
        let r = BatchUninstaller.execute(batch: b, selectedResidues: [s.document.path], environment: { s.environment }, running: { RunningPrograms() }, trash: { _ in moves += 1 })
        return r.count == 2 && r.allSatisfy { $0.state == .failed } && moves == 0 && fm.fileExists(atPath: s.document.path)
    }
    check("detener lote termina el actual y conserva el siguiente") {
        var s = try scenario(base)
        let second = try secondProgram(s)
        s.environment.inventory.append(second)
        let b = try BatchUninstaller.analyze(programs: [s.program, second], environment: s.environment)
        var stopped = false
        let r = BatchUninstaller.execute(batch: b, selectedResidues: [], environment: { s.environment }, running: { RunningPrograms() }, cancelled: { stopped }, trash: { source in
            try fm.moveItem(at: source, to: s.fakeTrash.appendingPathComponent(source.lastPathComponent)); stopped = true
        })
        return r.count == 2 && r[0].state == .completed && r[1].state == .cancelled && fm.fileExists(atPath: second.path)
    }
    check("aplicación abierta queda bloqueada sin impedir otra desinstalación") {
        var s = try scenario(base)
        let second = try secondProgram(s)
        s.environment.inventory.append(second)
        let active = RunningPrograms(bundleIDs: ["com.example.app"])
        let b = try BatchUninstaller.analyze(programs: [s.program, second], environment: s.environment, running: active)
        let r = BatchUninstaller.execute(batch: b, selectedResidues: [], environment: { s.environment }, running: { active }, trash: { source in
            try fm.moveItem(at: source, to: s.fakeTrash.appendingPathComponent(source.lastPathComponent))
        })
        return b.blocked.count == 1 && r.count == 2 && r[0].state == .blocked && r[1].state == .completed && fm.fileExists(atPath: s.program.path)
    }
    check("lote respeta selección de un residuo y conserva los demás") {
        let s = try scenario(base)
        let b = try BatchUninstaller.analyze(programs: [s.program], environment: s.environment)
        let r = BatchUninstaller.execute(batch: b, selectedResidues: [s.cache.path], environment: { s.environment }, running: { RunningPrograms() }, trash: { source in
            try fm.moveItem(at: source, to: s.fakeTrash.appendingPathComponent(source.lastPathComponent))
        })
        return r.first?.state == .completed && r.first?.items.count == 2 && !fm.fileExists(atPath: s.cache.path) && fm.fileExists(atPath: s.data.path)
    }
    check("análisis de lote cancelado no devuelve un plan ejecutable parcial") {
        let s = try scenario(base)
        return rejected { _ = try BatchUninstaller.analyze(programs: [s.program], environment: s.environment, cancelled: { true }) }
    }
    check("lote Homebrew ordena dependiente seleccionado antes de su dependencia") {
        var s = try scenario(base)
        let packages = ["core", "tool"].map { token in
            InstalledProgram(id: "formula:\(token)", name: token, version: "1.0", origin: "Homebrew · fórmula", path: "Fórmula: \(token)", brew: BrewIdentity(token: token, kind: .formula))
        }
        s.environment.inventory = packages
        var installed = Set(["core", "tool"])
        var removed: [String] = []
        let brew = BrewService { args, _ in
            if args.first == "info" {
                return try JSONSerialization.data(withJSONObject: ["formulae": installed.sorted().map { ["name": $0, "installed": [["version": "1.0"]]] as [String: Any] }, "casks": []])
            }
            if args.first == "uses" { return Data((args.last == "core" && installed.contains("tool") ? "tool\n" : "").utf8) }
            if args.first == "uninstall", let token = args.last { removed.append(token); installed.remove(token); return Data() }
            throw InventoryError.process("Comando inesperado")
        }
        let batch = try BatchUninstaller.analyze(programs: packages, environment: s.environment, brew: brew)
        let results = BatchUninstaller.execute(batch: batch, selectedResidues: [], environment: { s.environment }, running: { RunningPrograms() }, brew: brew)
        return batch.blocked.isEmpty && removed == ["tool", "core"] && results.allSatisfy { $0.state == .completed } && results.count == 2
    }
    check("dependiente no seleccionado mantiene bloqueo de Homebrew") {
        var s = try scenario(base)
        let core = InstalledProgram(id: "formula:core", name: "core", version: "1.0", origin: "Homebrew · fórmula", path: "Fórmula: core", brew: BrewIdentity(token: "core", kind: .formula))
        let external = InstalledProgram(id: "formula:external", name: "external", version: "1.0", origin: "Homebrew · fórmula", path: "Fórmula: external", brew: BrewIdentity(token: "external", kind: .formula))
        s.environment.inventory = [core, external]
        let data = Data(#"{"formulae":[{"name":"core","installed":[{"version":"1.0"}]},{"name":"external","installed":[{"version":"1.0"}]}],"casks":[]}"#.utf8)
        var removed = false
        let brew = BrewService { args, _ in
            if args.first == "info" { return data }
            if args.first == "uses" { return Data("external\n".utf8) }
            removed = true; return Data()
        }
        let batch = try BatchUninstaller.analyze(programs: [core], environment: s.environment, brew: brew)
        let result = BatchUninstaller.execute(batch: batch, selectedResidues: [], environment: { s.environment }, running: { RunningPrograms() }, brew: brew)
        return batch.blocked.count == 1 && result.first?.state == .blocked && !removed
    }
    check("dependiente seleccionado pero protegido no habilita quitar su dependencia") {
        var s = try scenario(base)
        let core = InstalledProgram(id: "formula:core", name: "core", version: "1.0", origin: "Homebrew · fórmula", path: "Fórmula: core", brew: BrewIdentity(token: "core", kind: .formula))
        let protected = InstalledProgram(id: "formula:tool", name: "tool", version: "1.0", origin: "Homebrew · fórmula", path: "Fórmula: tool", bundleID: "com.apple.tool", brew: BrewIdentity(token: "tool", kind: .formula))
        s.environment.inventory = [core, protected]
        let json = Data(#"{"formulae":[{"name":"core","installed":[{"version":"1.0"}]},{"name":"tool","installed":[{"version":"1.0"}]}],"casks":[]}"#.utf8)
        let brew = BrewService { args, _ in args.first == "info" ? json : Data("tool\n".utf8) }
        let batch = try BatchUninstaller.analyze(programs: [core, protected], environment: s.environment, brew: brew)
        return batch.ready.isEmpty && batch.blocked.count == 2
    }
}
