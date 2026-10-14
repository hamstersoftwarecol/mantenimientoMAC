import Foundation

enum BrewKind: String { case formula, cask }
struct BrewIdentity: Equatable {
    var token: String
    var kind: BrewKind
}

struct InstalledProgram: Identifiable {
    var id: String
    var name: String
    var version: String
    var origin: String
    var path: String
    var bundleID: String?
    var artifacts: [String] = []
    var brew: BrewIdentity? = nil
    var executableName: String? = nil
}
enum BrewParser {
    static func parse(_ data: Data) throws -> [InstalledProgram] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formulas = json["formulae"] as? [[String: Any]],
              let casks = json["casks"] as? [[String: Any]] else {
            throw InventoryError.invalidJSON
        }
        var programs: [InstalledProgram] = []
        for f in formulas {
            guard let name = f["name"] as? String,
                  let installed = f["installed"] as? [[String: Any]], !installed.isEmpty else { continue }
            let token = f["full_name"] as? String ?? name
            programs.append(InstalledProgram(id: "formula:\(token)", name: name,
                version: installed.compactMap { $0["version"] as? String }.joined(separator: ", "),
                origin: "Homebrew · fórmula", path: "Fórmula: \(token)", brew: BrewIdentity(token: token, kind: .formula)))
        }
        for c in casks {
            guard let token = c["token"] as? String else { continue }
            let artifacts = (c["artifacts"] as? [[String: Any]] ?? []).flatMap { artifact -> [String] in
                guard let app = artifact["app"] as? [Any] else { return [] }
                if let target = artifact["target"] as? String { return [target] }
                if let target = app.compactMap({ ($0 as? [String: Any])?["target"] as? String }).first { return [target] }
                return app.compactMap { $0 as? String }
            }
            let version = c["installed"] as? String ?? c["version"] as? String ?? "—"
            let fullToken = c["full_token"] as? String ?? token
            programs.append(InstalledProgram(id: "cask:\(fullToken)", name: (c["name"] as? [String])?.first ?? token,
                version: version, origin: "Homebrew · cask", path: "Cask: \(fullToken)", artifacts: artifacts,
                brew: BrewIdentity(token: fullToken, kind: .cask)))
        }
        return programs
    }
}
enum ApplicationReader {
    static func read(_ url: URL) throws -> InstalledProgram {
        let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw InventoryError.invalidPlist
        }
        return InstalledProgram(id: url.path,
            name: plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent,
            version: plist["CFBundleShortVersionString"] as? String ?? plist["CFBundleVersion"] as? String ?? "—",
            origin: url.path.hasPrefix("/System/") ? "macOS" : "Aplicación local", path: url.path,
            bundleID: plist["CFBundleIdentifier"] as? String, executableName: plist["CFBundleExecutable"] as? String)
    }
}

enum InventoryError: LocalizedError {
    case invalidJSON, invalidPlist, process(String), timeout
    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "Homebrew devolvió un inventario no válido."
        case .invalidPlist: return "No se pudieron leer los metadatos de la aplicación."
        case .process(let detail): return detail
        case .timeout: return "Homebrew superó el tiempo límite. Comprueba su estado antes de volver a intentarlo."
        }
    }
}

enum ProcessRunner {
    static func run(_ executable: URL, _ arguments: [String], cancelled: () -> Bool, timeout: TimeInterval = 30) throws -> Data {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("mantenimiento-process-\(UUID())")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let out = folder.appendingPathComponent("out")
        let err = folder.appendingPathComponent("err")
        guard fm.createFile(atPath: out.path, contents: nil), fm.createFile(atPath: err.path, contents: nil) else {
            throw InventoryError.process("No se pudo crear una salida temporal para Homebrew.")
        }
        let outputHandle = try FileHandle(forWritingTo: out)
        let errorHandle = try FileHandle(forWritingTo: err)
        defer { try? outputHandle.close(); try? errorHandle.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_AUTOREMOVE"] = "1"
        environment.removeValue(forKey: "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK")
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if cancelled() || Date() >= deadline {
                process.terminate()
                let stopDeadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < stopDeadline { Thread.sleep(forTimeInterval: 0.02) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                if cancelled() { throw MaintenanceError.cancelled }
                throw InventoryError.timeout
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if cancelled() { throw MaintenanceError.cancelled }
        guard process.terminationStatus == 0 else {
            let detail = String(data: (try? Data(contentsOf: err)) ?? Data(), encoding: .utf8) ?? "Error de Homebrew."
            throw InventoryError.process(String(detail.prefix(1200)))
        }
        return try Data(contentsOf: out)
    }
}

struct InventoryResult {
    var programs: [InstalledProgram]
    var brewCache: URL?
    var issues: [String]
    var brewStatus: String
}

enum Inventory {
    static func associate(applications: [InstalledProgram], packages: [InstalledProgram]) -> [InstalledProgram] {
        var programs = applications
        for package in packages {
            let matching = programs.indices.filter { index in
                package.artifacts.contains { $0.hasPrefix("/") && programs[index].path == $0 }
            }
            if matching.isEmpty { programs.append(package) }
            else {
                for index in matching {
                    programs[index].origin = "Homebrew · cask"
                    programs[index].brew = package.brew
                    programs[index].artifacts = package.artifacts
                }
            }
        }
        return programs
    }
    static func scan(cancelled: () -> Bool) throws -> InventoryResult {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let appRoots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"), URL(fileURLWithPath: "/System/Applications")]
        var programs: [InstalledProgram] = []
        var issues: [String] = []
        var seen = Set<String>()
        for root in appRoots where fm.fileExists(atPath: root.path) {
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { path, error in
                issues.append("\(path.path): \(error.localizedDescription)"); return true
            }) else { issues.append("No se pudo leer \(root.path)."); continue }
            while let url = walker.nextObject() as? URL {
                if cancelled() { throw MaintenanceError.cancelled }
                if url.pathExtension.lowercased() == "app" {
                    walker.skipDescendants()
                    guard seen.insert(url.resolvingSymlinksInPath().path).inserted else { continue }
                    do { programs.append(try ApplicationReader.read(url)) }
                    catch { issues.append("\(url.path): \(error.localizedDescription)") }
                } else if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    walker.skipDescendants()
                }
            }
        }
        var cache: URL?
        var brewStatus = "Homebrew no encontrado"
        if let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: { fm.isExecutableFile(atPath: $0) }) {
            brewStatus = "Homebrew: \(brew)"
            do {
                let data = try ProcessRunner.run(URL(fileURLWithPath: brew), ["info", "--json=v2", "--installed"], cancelled: cancelled)
                let packages = try BrewParser.parse(data)
                for package in packages {
                    for artifact in package.artifacts where artifact.hasPrefix("/") && artifact.hasSuffix(".app") && fm.fileExists(atPath: artifact) {
                        if !programs.contains(where: { $0.path == artifact }) {
                            do { programs.append(try ApplicationReader.read(URL(fileURLWithPath: artifact))) }
                            catch { issues.append("\(artifact): \(error.localizedDescription)") }
                        }
                    }
                }
                programs = associate(applications: programs, packages: packages)
                brewStatus += " · \(packages.count) paquetes"
            } catch MaintenanceError.cancelled { throw MaintenanceError.cancelled }
            catch { issues.append("Inventario Homebrew: \(error.localizedDescription)") }
            do {
                let data = try ProcessRunner.run(URL(fileURLWithPath: brew), ["--cache"], cancelled: cancelled)
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let proposed = URL(fileURLWithPath: path)
                if path.hasPrefix(home.path + "/") && proposed.lastPathComponent == "Homebrew" {
                    cache = proposed
                } else { issues.append("La caché de Homebrew está fuera del alcance permitido: \(path).") }
            } catch MaintenanceError.cancelled { throw MaintenanceError.cancelled }
            catch { issues.append("Caché Homebrew: \(error.localizedDescription)") }
        }
        return InventoryResult(programs: programs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                               brewCache: cache, issues: issues, brewStatus: brewStatus)
    }
}
