import Foundation

struct RunningPrograms {
    var bundleIDs: Set<String> = []
    var paths: Set<String> = []
}
struct UninstallEnvironment {
    var home: URL
    var applicationRoots: [URL]
    var inventory: [InstalledProgram]
    var ownBundleID = "local.mantenimientomac.app"
}
struct FileIdentity: Equatable {
    var device: UInt64
    var inode: UInt64
    static func read(_ url: URL) throws -> FileIdentity {
        try PathSafety.rejectSymbolicAncestors(url)
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let device = a[.systemNumber] as? NSNumber, let inode = a[.systemFileNumber] as? NSNumber else {
            throw InventoryError.process("No se pudo comprobar la identidad del archivo: \(url.path)")
        }
        return FileIdentity(device: device.uint64Value, inode: inode.uint64Value)
    }
}
enum ResidueKind: String {
    case cache = "Caché", preferences = "Preferencias", logs = "Registros", data = "Datos de la aplicación", savedState = "Estado guardado"
}
struct ResidueEntry: Identifiable {
    var id: String { url.path }
    var url: URL
    var kind: ResidueKind
    var evidence: String
    var bytes: Int64
    var incomplete: Bool
    var identity: FileIdentity?
    var blockedReason: String?
}
struct UninstallPlan: Identifiable {
    let id = UUID()
    var program: InstalledProgram
    var residues: [ResidueEntry] = []
    var applicationIdentity: FileIdentity?
    var applicationBytes: Int64 = 0
    var applicationIncomplete = false
    var issues: [String] = []
    var blockedReason: String?
    var dependents: [String] = []
}
struct BrewService {
    var run: ([String], TimeInterval) throws -> Data
    func installed() throws -> [InstalledProgram] { try BrewParser.parse(run(["info", "--json=v2", "--installed"], 30)) }
    func dependents(_ identity: BrewIdentity) throws -> [String] {
        try validate(identity)
        guard identity.kind == .formula else { return [] }
        let data = try run(["uses", "--installed", "--recursive", identity.token], 30)
        guard let output = String(data: data, encoding: .utf8) else { throw InventoryError.invalidJSON }
        return output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    func uninstall(_ identity: BrewIdentity) throws {
        try validate(identity)
        _ = try run(["uninstall", identity.kind == .formula ? "--formula" : "--cask", identity.token], 300)
    }
    func validate(_ identity: BrewIdentity) throws {
        let pattern = "^[A-Za-z0-9][A-Za-z0-9+_.@-]*(/[A-Za-z0-9][A-Za-z0-9+_.@-]*){0,2}$"
        guard identity.token.range(of: pattern, options: .regularExpression) != nil else {
            throw InventoryError.process("El identificador del paquete Homebrew no es válido.")
        }
    }
    static func live(cancelled: @escaping () -> Bool = { false }) -> BrewService? {
        guard let path = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        return BrewService { arguments, timeout in
            try ProcessRunner.run(URL(fileURLWithPath: path), arguments, cancelled: cancelled, timeout: timeout)
        }
    }
}
enum Uninstaller {
    static func protection(_ program: InstalledProgram, environment: UninstallEnvironment, running: RunningPrograms) -> String? {
        if program.path.hasPrefix("/System/") || program.origin == "macOS" || program.bundleID?.hasPrefix("com.apple.") == true {
            return "Los componentes de macOS están protegidos."
        }
        if program.bundleID == environment.ownBundleID { return "Esta herramienta no puede desinstalarse a sí misma." }
        if let id = program.bundleID, running.bundleIDs.contains(id) { return "La aplicación está abierta. Ciérrala antes de desinstalar." }
        if program.path.hasPrefix("/") {
            let resolved = URL(fileURLWithPath: program.path).resolvingSymlinksInPath().path
            if running.paths.contains(where: { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == resolved }) {
                return "La aplicación está abierta. Ciérrala antes de desinstalar."
            }
        }
        return nil
    }

    static func validateApplication(_ program: InstalledProgram, environment: UninstallEnvironment) throws -> FileIdentity? {
        guard program.path.hasPrefix("/") else {
            guard program.brew != nil else { throw MaintenanceError.unsafePath }
            return nil
        }
        let url = URL(fileURLWithPath: program.path)
        guard url.pathExtension == "app" else { throw MaintenanceError.unsafePath }
        if program.brew == nil {
            guard environment.applicationRoots.contains(where: { url.path.hasPrefix($0.path + "/") }) else { throw MaintenanceError.unsafePath }
        }
        var parent = (url.path as NSString).deletingLastPathComponent
        while parent != "/" {
            guard !(parent as NSString).pathExtension.lowercased().elementsEqual("app") else { throw MaintenanceError.unsafePath }
            parent = (parent as NSString).deletingLastPathComponent
        }
        let identity = try FileIdentity.read(url)
        let current = try ApplicationReader.read(url)
        guard current.bundleID == program.bundleID, current.version == program.version, current.name == program.name else {
            throw InventoryError.process("La identidad o versión de la aplicación cambió. Vuelve a analizar.")
        }
        return identity
    }

    static func candidates(_ program: InstalledProgram, environment: UninstallEnvironment) -> [(URL, ResidueKind, String)] {
        guard let id = program.bundleID, id.range(of: "^[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)+$", options: .regularExpression) != nil,
              !environment.inventory.contains(where: { $0.bundleID == id && $0.path != program.path }) else { return [] }
        let library = environment.home.appendingPathComponent("Library")
        var slots: [(String, String, ResidueKind, String)] = [
            ("Caches", id, .cache, "Identificador exacto"),
            ("Preferences", id + ".plist", .preferences, "Identificador exacto"),
            ("Logs", id, .logs, "Identificador exacto"),
            ("Application Support", id, .data, "Identificador exacto"),
            ("Containers", id, .data, "Identificador exacto"),
            ("Saved Application State", id + ".savedState", .savedState, "Identificador exacto")
        ]
        let names = Set([program.name, program.executableName].compactMap { $0 })
        for name in names where !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains(":") {
            let collision = environment.inventory.contains { $0.path != program.path && ($0.name == name || $0.executableName == name || $0.bundleID == name) }
            if collision { continue }
            slots.append(("Application Support", name, .data, "Coincidencia por nombre; puede compartirse"))
            slots.append(("Logs", name, .logs, "Coincidencia por nombre; puede compartirse"))
        }
        var seen = Set<String>()
        return slots.compactMap { folder, name, kind, evidence in
            let url = library.appendingPathComponent(folder).appendingPathComponent(name)
            return seen.insert(url.path).inserted ? (url, kind, evidence) : nil
        }
    }

    static func checkPackage(_ program: InstalledProgram, brew: BrewService?) throws -> [String] {
        guard let identity = program.brew else {
            if let brew = brew, program.path.hasPrefix("/") {
                let installed = try brew.installed()
                let appName = URL(fileURLWithPath: program.path).lastPathComponent
                let possibleCask = installed.contains { package in
                    package.brew?.kind == .cask && package.artifacts.contains { artifact in
                        artifact.hasPrefix("/") ? artifact == program.path : URL(fileURLWithPath: artifact).lastPathComponent == appName
                    }
                }
                if possibleCask {
                    throw InventoryError.process("Homebrew registra esta aplicación o una con el mismo nombre. Su origen debe verificarse antes de desinstalarla; vuelve a analizar o usa Homebrew directamente.")
                }
            }
            return []
        }
        guard let brew = brew else { throw InventoryError.process("No se encuentra Homebrew para desinstalar este paquete.") }
        try brew.validate(identity)
        let installed = try brew.installed()
        guard let package = installed.first(where: { $0.brew == identity }), package.version == program.version || program.path.hasSuffix(".app") else {
            throw InventoryError.process("El paquete ya no está instalado o su versión cambió. Vuelve a analizar.")
        }
        if program.path.hasPrefix("/") {
            guard package.artifacts.contains(program.path) else { throw InventoryError.process("Homebrew ya no asocia este paquete con la aplicación seleccionada.") }
        }
        let appTargets = package.artifacts.filter { $0.lowercased().hasSuffix(".app") }
        guard appTargets.count <= 1 else { throw InventoryError.process("Este cask incluye varias aplicaciones. Desinstálalo directamente con Homebrew para revisar el alcance completo.") }
        guard !appTargets.contains(where: { !$0.hasPrefix("/") }) else {
            throw InventoryError.process("El destino de la aplicación de este cask no pudo verificarse. Utiliza Homebrew directamente para desinstalarlo.")
        }
        if !appTargets.isEmpty && !program.path.hasPrefix("/") {
            throw InventoryError.process("La aplicación de este cask no pudo identificarse. Vuelve a analizar o utiliza Homebrew directamente.")
        }
        return try brew.dependents(identity)
    }

    static func analyze(program: InstalledProgram, environment: UninstallEnvironment, running: RunningPrograms = RunningPrograms(), brew: BrewService? = nil,
                        cancelled: () -> Bool = { false }, progress: (String) -> Void = { _ in }) throws -> UninstallPlan {
        if cancelled() { throw MaintenanceError.cancelled }
        var plan = UninstallPlan(program: program)
        if let reason = protection(program, environment: environment, running: running) { plan.blockedReason = reason; return plan }
        do {
            plan.applicationIdentity = try validateApplication(program, environment: environment)
            progress("Comprobando paquete y dependencias…")
            plan.dependents = try checkPackage(program, brew: brew)
            if !plan.dependents.isEmpty {
                plan.blockedReason = "Otros paquetes instalados dependen de este: " + plan.dependents.joined(separator: ", ")
                return plan
            }
        } catch MaintenanceError.cancelled { throw MaintenanceError.cancelled }
        catch { plan.blockedReason = error.localizedDescription; return plan }
        if program.path.hasPrefix("/") {
            progress("Midiendo aplicación…")
            do {
                let size = try CacheScanner.measure(URL(fileURLWithPath: program.path), cancelled: cancelled)
                plan.applicationBytes = size.bytes; plan.applicationIncomplete = size.incomplete
            } catch MaintenanceError.cancelled { throw MaintenanceError.cancelled }
            catch { plan.applicationIncomplete = true; plan.issues.append(error.localizedDescription) }
        }
        if let id = program.bundleID, environment.inventory.contains(where: { $0.bundleID == id && $0.path != program.path }) {
            plan.issues.append("Hay otra instalación con el mismo identificador. Se conservan los residuos que pueden compartir.")
        }
        if program.bundleID == nil { plan.issues.append("No hay identificador de aplicación: no se infieren residuos para este paquete.") }
        for (url, kind, evidence) in candidates(program, environment: environment) {
            if cancelled() { throw MaintenanceError.cancelled }
            progress("Revisando \(url.lastPathComponent)…")
            do {
                _ = try FileManager.default.attributesOfItem(atPath: url.path)
            } catch {
                let ns = error as NSError
                if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileNoSuchFileError || ns.code == NSFileReadNoSuchFileError) { continue }
                plan.issues.append("\(url.path): \(error.localizedDescription)"); continue
            }
            var entry = ResidueEntry(url: url, kind: kind, evidence: evidence, bytes: 0, incomplete: false, identity: nil, blockedReason: nil)
            do {
                try CachePolicy(roots: [url.deletingLastPathComponent()]).validate(url)
                entry.identity = try FileIdentity.read(url)
                let size = try CacheScanner.measure(url, cancelled: cancelled)
                entry.bytes = size.bytes; entry.incomplete = size.incomplete
                if size.incomplete { plan.issues.append("Medición incompleta: \(url.path)") }
            } catch MaintenanceError.cancelled { throw MaintenanceError.cancelled }
            catch { entry.blockedReason = error.localizedDescription; entry.incomplete = true }
            plan.residues.append(entry)
        }
        plan.residues.sort { $0.url.path < $1.url.path }
        return plan
    }
    static func execute(plan: UninstallPlan, selected: Set<String>, environment: UninstallEnvironment,
                        running: () -> RunningPrograms, brew: BrewService? = nil,
                        trash: (URL) throws -> Void = { _ = try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> [CleanOutcome] {
        let program = plan.program
        var results: [CleanOutcome] = []
        let residues = plan.residues.filter { selected.contains($0.id) }
        do {
            if let blocked = plan.blockedReason { throw InventoryError.process(blocked) }
            if let blocked = protection(program, environment: environment, running: running()) { throw InventoryError.process(blocked) }
            guard try validateApplication(program, environment: environment) == plan.applicationIdentity else {
                throw InventoryError.process("La aplicación fue sustituida desde el análisis. Vuelve a analizar.")
            }
            guard selected.isSubset(of: Set(plan.residues.map(\.id))) else { throw MaintenanceError.unsafePath }
            let allowed = Set(candidates(program, environment: environment).map { $0.0.path })
            for residue in residues {
                guard allowed.contains(residue.id), residue.blockedReason == nil,
                      try FileIdentity.read(residue.url) == residue.identity else { throw MaintenanceError.unsafePath }
            }
            let dependents = try checkPackage(program, brew: brew)
            guard dependents.isEmpty else { throw InventoryError.process("Otros paquetes dependen de este: " + dependents.joined(separator: ", ")) }
            if let blocked = protection(program, environment: environment, running: running()) { throw InventoryError.process(blocked) }
            if let identity = program.brew {
                guard let brew = brew else { throw InventoryError.process("Homebrew no disponible.") }
                try brew.uninstall(identity)
                guard !(try brew.installed()).contains(where: { $0.brew == identity }) else {
                    throw InventoryError.process("Homebrew todavía informa el paquete como instalado. Se conservan sus residuos.")
                }
                results.append(CleanOutcome(path: program.path, success: true, detail: "Paquete desinstalado mediante Homebrew."))
            } else {
                guard try validateApplication(program, environment: environment) == plan.applicationIdentity else { throw MaintenanceError.unsafePath }
                try trash(URL(fileURLWithPath: program.path))
                results.append(CleanOutcome(path: program.path, success: true, detail: "Aplicación enviada a la Papelera."))
            }
        } catch {
            return [CleanOutcome(path: program.path, success: false, detail: "\(error.localizedDescription) Los residuos se conservaron. Si Homebrew llegó a ejecutarse, revisa el inventario actualizado.")]
        }
        for residue in residues {
            do {
                if let id = program.bundleID, running().bundleIDs.contains(id) { throw InventoryError.process("La aplicación volvió a abrirse; se conserva el residuo.") }
                guard try FileIdentity.read(residue.url) == residue.identity else { throw MaintenanceError.unsafePath }
                try trash(residue.url)
                results.append(CleanOutcome(path: residue.url.path, success: true, detail: "Residuo enviado a la Papelera."))
            } catch { results.append(CleanOutcome(path: residue.url.path, success: false, detail: error.localizedDescription)) }
        }
        return results
    }
}
