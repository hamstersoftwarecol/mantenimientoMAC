import Foundation

struct Scenario {
    var program: InstalledProgram
    var environment: UninstallEnvironment
    var cache: URL
    var data: URL
    var document: URL
    var fakeTrash: URL
}

func scenario(_ base: URL) throws -> Scenario {
    let fm = FileManager.default
    let home = base.appendingPathComponent("uninstall-\(UUID())")
    let apps = home.appendingPathComponent("Applications")
    let app = apps.appendingPathComponent("Example.app")
    try fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleName": "Example", "CFBundleIdentifier": "com.example.app", "CFBundleShortVersionString": "1.0", "CFBundleExecutable": "Example"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
    let cache = home.appendingPathComponent("Library/Caches/com.example.app")
    let data = home.appendingPathComponent("Library/Application Support/com.example.app")
    for folder in [cache, data, home.appendingPathComponent("Library/Preferences"), home.appendingPathComponent("Library/Group Containers/shared")] {
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    try Data([1, 2, 3, 4]).write(to: cache.appendingPathComponent("cache"))
    try Data([5, 6, 7]).write(to: data.appendingPathComponent("profile"))
    try Data([8]).write(to: home.appendingPathComponent("Library/Preferences/com.example.app.plist"))
    let document = home.appendingPathComponent("personal-document")
    try Data([9]).write(to: document)
    let fakeTrash = home.appendingPathComponent("FakeTrash")
    try fm.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
    let p = try ApplicationReader.read(app)
    return Scenario(program: p, environment: UninstallEnvironment(home: home, applicationRoots: [apps], inventory: [p]),
                    cache: cache, data: data, document: document, fakeTrash: fakeTrash)
}

func runUninstallTests(_ base: URL) {
    let fm = FileManager.default
    check("residuos exactos con tipo y tamaño; no incluye documentos ni carpetas compartidas") {
        let s = try scenario(base)
        let p = try Uninstaller.analyze(program: s.program, environment: s.environment)
        return p.blockedReason == nil && p.residues.count == 3 &&
            p.residues.contains { $0.url.path == s.cache.path && $0.bytes == 4 && $0.kind == .cache } &&
            p.residues.contains { $0.url.path == s.data.path && $0.bytes == 3 && $0.kind == .data }
    }
    check("desinstalación local conserva residuos y datos sin seleccionar") {
        let s = try scenario(base)
        let plan = try Uninstaller.analyze(program: s.program, environment: s.environment)
        let results = Uninstaller.execute(plan: plan, selected: [], environment: s.environment, running: { RunningPrograms() }, trash: { url in
            try fm.moveItem(at: url, to: s.fakeTrash.appendingPathComponent(url.lastPathComponent))
        })
        return results.first?.success == true && !fm.fileExists(atPath: s.program.path) && fm.fileExists(atPath: s.cache.path) && fm.fileExists(atPath: s.data.path)
    }
    check("desinstalación traslada solo residuos seleccionados") {
        let s = try scenario(base)
        let plan = try Uninstaller.analyze(program: s.program, environment: s.environment)
        let results = Uninstaller.execute(plan: plan, selected: [s.cache.path], environment: s.environment, running: { RunningPrograms() }, trash: { url in
            try fm.moveItem(at: url, to: s.fakeTrash.appendingPathComponent(url.lastPathComponent))
        })
        return results.count == 2 && results.allSatisfy(\.success) && !fm.fileExists(atPath: s.cache.path) && fm.fileExists(atPath: s.data.path) && fm.fileExists(atPath: s.document.path)
    }
    check("aplicación abierta por ruta se bloquea aunque falte su identificador en procesos") {
        let s = try scenario(base)
        let p = try Uninstaller.analyze(program: s.program, environment: s.environment)
        let r = Uninstaller.execute(plan: p, selected: [s.cache.path], environment: s.environment, running: { RunningPrograms(paths: [s.program.path]) }, trash: { _ in throw InventoryError.process("No debe llegar aquí") })
        return r.first?.success == false && r.first?.detail.contains("abierta") == true && fm.fileExists(atPath: s.cache.path)
    }
    check("selección externa rechazada antes de desinstalar") {
        let s = try scenario(base)
        let p = try Uninstaller.analyze(program: s.program, environment: s.environment)
        let r = Uninstaller.execute(plan: p, selected: [s.document.path], environment: s.environment, running: { RunningPrograms() }, trash: { url in
            try fm.moveItem(at: url, to: s.fakeTrash.appendingPathComponent(url.lastPathComponent))
        })
        return r.first?.success == false && fm.fileExists(atPath: s.program.path) && fm.fileExists(atPath: s.document.path)
    }
    check("fallo desinstalando aplicación no traslada sus residuos") {
        let s = try scenario(base)
        let p = try Uninstaller.analyze(program: s.program, environment: s.environment)
        let r = Uninstaller.execute(plan: p, selected: [s.cache.path], environment: s.environment, running: { RunningPrograms() }, trash: { _ in throw InventoryError.process("Sin permiso") })
        return r.first?.success == false && r.first?.detail.contains("Sin permiso") == true && fm.fileExists(atPath: s.cache.path)
    }
    check("identidad de aplicación cambiada impide desinstalación") {
        let s = try scenario(base)
        let p = try Uninstaller.analyze(program: s.program, environment: s.environment)
        let info = URL(fileURLWithPath: s.program.path).appendingPathComponent("Contents/Info.plist")
        let other: [String: Any] = ["CFBundleIdentifier": "com.other.app", "CFBundleName": "Other"]
        try PropertyListSerialization.data(fromPropertyList: other, format: .xml, options: 0).write(to: info)
        let r = Uninstaller.execute(plan: p, selected: [], environment: s.environment, running: { RunningPrograms() }, trash: { url in
            try fm.moveItem(at: url, to: s.fakeTrash.appendingPathComponent(url.lastPathComponent))
        })
        return r.first?.success == false && fm.fileExists(atPath: s.program.path)
    }
    check("residuo sustituido por enlace no toca aplicación ni destino externo") {
        let s = try scenario(base)
        let p = try Uninstaller.analyze(program: s.program, environment: s.environment)
        try fm.moveItem(at: s.cache, to: s.fakeTrash.appendingPathComponent("preserved"))
        try fm.createSymbolicLink(at: s.cache, withDestinationURL: s.document)
        let r = Uninstaller.execute(plan: p, selected: [s.cache.path], environment: s.environment, running: { RunningPrograms() }, trash: { url in
            try fm.moveItem(at: url, to: s.fakeTrash.appendingPathComponent(url.lastPathComponent))
        })
        return r.first?.success == false && fm.fileExists(atPath: s.program.path) && fm.fileExists(atPath: s.document.path)
    }
    check("bloquea componentes macOS y esta herramienta") {
        let s = try scenario(base)
        var apple = s.program; apple.bundleID = "com.apple.example"
        var own = s.program; own.bundleID = "local.mantenimientomac.app"
        return try Uninstaller.analyze(program: apple, environment: s.environment).blockedReason != nil &&
            Uninstaller.analyze(program: own, environment: s.environment).blockedReason != nil
    }
    check("bundle compartido por otra instalación no permite quitar residuos") {
        var s = try scenario(base)
        var other = s.program; other.id = "other"; other.path = "/Applications/Other.app"
        s.environment.inventory.append(other)
        let p = try Uninstaller.analyze(program: s.program, environment: s.environment)
        return p.residues.isEmpty && !p.issues.isEmpty
    }
    check("Homebrew usa tipo y token sin zap ni force ni ignore-dependencies") {
        var calls: [[String]] = []
        let b = BrewService { args, _ in calls.append(args); return Data() }
        try b.uninstall(BrewIdentity(token: "wget", kind: .formula))
        try b.uninstall(BrewIdentity(token: "sample", kind: .cask))
        return calls == [["uninstall", "--formula", "wget"], ["uninstall", "--cask", "sample"]]
    }
    check("Homebrew bloquea tokens que podrían ser opciones") {
        let b = BrewService { _, _ in throw InventoryError.process("No debe ejecutarse") }
        return rejected { try b.uninstall(BrewIdentity(token: "--zap", kind: .cask)) }
    }
    check("Homebrew comprueba dependientes instalados") {
        var captured: [String] = []
        let b = BrewService { args, _ in captured = args; return Data("tool-one\ntool-two\n".utf8) }
        let d = try b.dependents(BrewIdentity(token: "wget", kind: .formula))
        return d == ["tool-one", "tool-two"] && captured == ["uses", "--installed", "--recursive", "wget"]
    }
    check("Homebrew revalida dependientes al ejecutar y no desinstala un paquete requerido") {
        let s = try scenario(base)
        let program = InstalledProgram(id: "formula:wget", name: "wget", version: "1.25.0", origin: "Homebrew · fórmula", path: "Fórmula: wget", brew: BrewIdentity(token: "wget", kind: .formula))
        let json = Data(#"{"formulae":[{"name":"wget","installed":[{"version":"1.25.0"}]}],"casks":[]}"#.utf8)
        var depended = false
        var removed = false
        let brew = BrewService { args, _ in
            if args.first == "info" { return json }
            if args.first == "uses" { return Data((depended ? "other-tool\n" : "").utf8) }
            removed = true; return Data()
        }
        let plan = try Uninstaller.analyze(program: program, environment: s.environment, brew: brew)
        depended = true
        let r = Uninstaller.execute(plan: plan, selected: [], environment: s.environment, running: { RunningPrograms() }, brew: brew)
        return !removed && r.first?.success == false && r.first?.detail.contains("other-tool") == true
    }
    check("Homebrew verifica eliminación y no traslada datos no seleccionados") {
        let s = try scenario(base)
        let program = InstalledProgram(id: "formula:wget", name: "wget", version: "1.25.0", origin: "Homebrew · fórmula", path: "Fórmula: wget", brew: BrewIdentity(token: "wget", kind: .formula))
        let installed = Data(#"{"formulae":[{"name":"wget","installed":[{"version":"1.25.0"}]}],"casks":[]}"#.utf8)
        let empty = Data(#"{"formulae":[],"casks":[]}"#.utf8)
        var removed = false
        let brew = BrewService { args, _ in
            if args.first == "info" { return removed ? empty : installed }
            if args.first == "uses" { return Data() }
            if args == ["uninstall", "--formula", "wget"] { removed = true; return Data() }
            throw InventoryError.process("Argumentos inesperados")
        }
        let plan = try Uninstaller.analyze(program: program, environment: s.environment, brew: brew)
        let r = Uninstaller.execute(plan: plan, selected: [], environment: s.environment, running: { RunningPrograms() }, brew: brew)
        return r.first?.success == true && removed && fm.fileExists(atPath: s.data.path)
    }
    check("fallo de Homebrew conserva los residuos seleccionados del cask") {
        var s = try scenario(base)
        s.program.brew = BrewIdentity(token: "example", kind: .cask)
        s.program.artifacts = [s.program.path]
        let package: [String: Any] = ["token": "example", "name": ["Example"], "version": "1.0", "installed": "1.0", "artifacts": [["app": ["Example.app"], "target": s.program.path]]]
        let json = try JSONSerialization.data(withJSONObject: ["formulae": [], "casks": [package]])
        let brew = BrewService { args, _ in
            if args.first == "info" { return json }
            throw InventoryError.process("Homebrew rechazó la desinstalación")
        }
        let plan = try Uninstaller.analyze(program: s.program, environment: s.environment, brew: brew)
        let r = Uninstaller.execute(plan: plan, selected: [s.cache.path], environment: s.environment, running: { RunningPrograms() }, brew: brew)
        return r.first?.success == false && r.first?.detail.contains("rechazó") == true && fm.fileExists(atPath: s.cache.path)
    }
    check("cancelación de análisis de residuos interrumpe sin cambios") {
        let s = try scenario(base)
        return rejected { _ = try Uninstaller.analyze(program: s.program, environment: s.environment, cancelled: { true }) } && fm.fileExists(atPath: s.program.path)
    }
    check("cask con aplicación relativa sin destino verificado se bloquea") {
        let s = try scenario(base)
        let program = InstalledProgram(id: "cask:example", name: "Example", version: "1.0", origin: "Homebrew · cask", path: "Cask: example", artifacts: ["Example.app"], brew: BrewIdentity(token: "example", kind: .cask))
        let json = Data(#"{"formulae":[],"casks":[{"token":"example","name":["Example"],"installed":"1.0","artifacts":[{"app":["Example.app"]}]}]}"#.utf8)
        let brew = BrewService { _, _ in json }
        let p = try Uninstaller.analyze(program: program, environment: s.environment, running: RunningPrograms(bundleIDs: ["com.example.app"]), brew: brew)
        return p.blockedReason != nil
    }
    check("cask con varias aplicaciones relativas no evade revisión de alcance") {
        let s = try scenario(base)
        let program = InstalledProgram(id: "cask:example", name: "Example", version: "1.0", origin: "Homebrew · cask", path: "Cask: example", artifacts: ["First.app", "Second.app"], brew: BrewIdentity(token: "example", kind: .cask))
        let json = Data(#"{"formulae":[],"casks":[{"token":"example","name":["Example"],"installed":"1.0","artifacts":[{"app":["First.app"]},{"app":["Second.app"]}]}]}"#.utf8)
        let p = try Uninstaller.analyze(program: program, environment: s.environment, brew: BrewService { _, _ in json })
        return p.blockedReason?.contains("varias aplicaciones") == true
    }
    check("app aparentemente local con cask de destino ambiguo no se manda a Papelera") {
        let s = try scenario(base)
        let plan = try Uninstaller.analyze(program: s.program, environment: s.environment)
        let json = Data(#"{"formulae":[],"casks":[{"token":"example","name":["Example"],"installed":"1.0","artifacts":[{"app":["Example.app"]}]}]}"#.utf8)
        var moved = false
        let r = Uninstaller.execute(plan: plan, selected: [], environment: s.environment, running: { RunningPrograms() }, brew: BrewService { _, _ in json }, trash: { _ in moved = true })
        return !moved && r.first?.success == false && fm.fileExists(atPath: s.program.path)
    }
}
