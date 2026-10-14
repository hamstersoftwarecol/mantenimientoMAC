import Foundation

struct BatchUninstallPlan: Identifiable {
    let id = UUID()
    var plans: [UninstallPlan]
    var executionOrder: [String]
    var ready: [UninstallPlan] { executionOrder.compactMap { id in plans.first { $0.program.id == id && $0.blockedReason == nil } } }
    var blocked: [UninstallPlan] { plans.filter { $0.blockedReason != nil } }
}
enum BatchProgramState: String {
    case completed = "Completado", partial = "Residuos pendientes", failed = "No completado", blocked = "Bloqueado", cancelled = "Omitido al detener"
}
struct BatchProgramOutcome: Identifiable {
    var id: String { program.id }
    var program: InstalledProgram
    var state: BatchProgramState
    var items: [CleanOutcome]
}
struct BatchProgress {
    var completed: Int
    var total: Int
    var message: String
}
enum BatchUninstaller {
    static func dependencyOrder(plans: inout [UninstallPlan], inventory: [InstalledProgram]) -> [String] {
        func resolve(_ name: String) -> String? {
            var identities: [BrewIdentity] = []
            for program in inventory {
                guard let identity = program.brew else { continue }
                let matches = identity.token == name || (!name.contains("/") && identity.token.split(separator: "/").last.map(String.init) == name)
                if matches && !identities.contains(identity) { identities.append(identity) }
            }
            guard identities.count == 1 else { return nil }
            let selected = plans.filter { $0.program.brew == identities[0] }
            return selected.count == 1 ? selected[0].program.id : nil
        }
        var needed: [String: Set<String>] = [:]
        for index in plans.indices where !plans[index].dependents.isEmpty {
            let ids = plans[index].dependents.compactMap(resolve)
            if ids.count == plans[index].dependents.count {
                needed[plans[index].program.id] = Set(ids)
                plans[index].blockedReason = nil
            }
        }
        var changed = true
        while changed {
            changed = false
            for index in plans.indices where plans[index].blockedReason == nil {
                if (needed[plans[index].program.id] ?? []).contains(where: { id in plans.first { $0.program.id == id }?.blockedReason != nil }) {
                    plans[index].blockedReason = "Un dependiente seleccionado está bloqueado. Este paquete se conserva mientras ese dependiente siga instalado."
                    changed = true
                }
            }
        }
        let active = plans.filter { $0.blockedReason == nil }.map { $0.program.id }
        var incoming: [String: Int] = Dictionary(uniqueKeysWithValues: active.map { ($0, 0) })
        var next: [String: [String]] = [:]
        for prerequisite in active {
            for dependent in needed[prerequisite] ?? [] {
                incoming[prerequisite, default: 0] += 1
                next[dependent, default: []].append(prerequisite)
            }
        }
        var ordered: [String] = []
        var visited = Set<String>()
        while let id = active.first(where: { !visited.contains($0) && incoming[$0] == 0 }) {
            ordered.append(id); visited.insert(id)
            for following in next[id] ?? [] { incoming[following, default: 0] -= 1 }
        }
        for index in plans.indices where plans[index].blockedReason == nil && !visited.contains(plans[index].program.id) {
            plans[index].blockedReason = "No se pudo determinar un orden seguro para estas dependencias. Se conserva el paquete."
        }
        return ordered
    }
    static func analyze(programs: [InstalledProgram], environment: UninstallEnvironment, running: RunningPrograms = RunningPrograms(), brew: BrewService? = nil,
                        cancelled: () -> Bool = { false }, progress: (BatchProgress) -> Void = { _ in }) throws -> BatchUninstallPlan {
        var unique = Set<String>()
        let programs = programs.filter { program in
            let key = program.brew.map { "\($0.kind.rawValue):\($0.token)" } ?? "app:\(URL(fileURLWithPath: program.path).resolvingSymlinksInPath().path)"
            return unique.insert(key).inserted
        }
        var plans: [UninstallPlan] = []
        for (index, program) in programs.enumerated() {
            if cancelled() { throw MaintenanceError.cancelled }
            let plan = try Uninstaller.analyze(program: program, environment: environment, running: running, brew: brew, cancelled: cancelled, progress: { message in
                progress(BatchProgress(completed: index, total: programs.count, message: "\(program.name): \(message)"))
            })
            plans.append(plan)
        }
        if cancelled() { throw MaintenanceError.cancelled }
        let order = dependencyOrder(plans: &plans, inventory: environment.inventory)
        var occurrences: [String: Int] = [:]
        for plan in plans where plan.blockedReason == nil {
            for residue in plan.residues { occurrences[residue.id, default: 0] += 1 }
        }
        for index in plans.indices {
            let shared = plans[index].residues.filter { occurrences[$0.id, default: 0] > 1 }
            if !shared.isEmpty {
                plans[index].issues.append("Se conservan residuos que coinciden entre varios programas: " + shared.map(\.id).joined(separator: ", "))
                plans[index].residues.removeAll { occurrences[$0.id, default: 0] > 1 }
            }
        }
        return BatchUninstallPlan(plans: plans, executionOrder: order)
    }
    static func execute(batch: BatchUninstallPlan, selectedResidues: Set<String>, environment: () throws -> UninstallEnvironment,
                        running: () -> RunningPrograms, brew: BrewService? = nil, cancelled: () -> Bool = { false },
                        progress: (BatchProgress) -> Void = { _ in },
                        trash: (URL) throws -> Void = { _ = try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> [BatchProgramOutcome] {
        let allowed = Set(batch.ready.flatMap { $0.residues.filter { $0.blockedReason == nil }.map(\.id) })
        guard selectedResidues.isSubset(of: allowed) else {
            return batch.plans.map { plan in
                BatchProgramOutcome(program: plan.program, state: .failed, items: [CleanOutcome(path: plan.program.path, success: false, detail: "Selección de residuos no válida. Vuelve a analizar el lote.")])
            }
        }
        var results: [String: BatchProgramOutcome] = [:]
        for plan in batch.blocked {
            results[plan.program.id] = BatchProgramOutcome(program: plan.program, state: .blocked,
                items: [CleanOutcome(path: plan.program.path, success: false, detail: plan.blockedReason ?? "Programa bloqueado.")])
        }
        let ready = batch.ready
        for (index, plan) in ready.enumerated() {
            if cancelled() {
                results[plan.program.id] = BatchProgramOutcome(program: plan.program, state: .cancelled,
                    items: [CleanOutcome(path: plan.program.path, success: false, detail: "Omitido al detener el lote. Se conservaron el programa y sus residuos.")])
                continue
            }
            progress(BatchProgress(completed: index, total: ready.count, message: "Desinstalando \(index + 1)/\(ready.count): \(plan.program.name)…"))
            do {
                let current = try environment()
                let selected = selectedResidues.intersection(Set(plan.residues.map(\.id)))
                let items = Uninstaller.execute(plan: plan, selected: selected, environment: current, running: running, brew: brew, trash: trash)
                let state: BatchProgramState = items.first?.success == true ? (items.allSatisfy(\.success) ? .completed : .partial) : .failed
                results[plan.program.id] = BatchProgramOutcome(program: plan.program, state: state, items: items)
                progress(BatchProgress(completed: index + 1, total: ready.count, message: "\(plan.program.name): \(state.rawValue)"))
            } catch {
                results[plan.program.id] = BatchProgramOutcome(program: plan.program, state: .failed,
                    items: [CleanOutcome(path: plan.program.path, success: false, detail: "\(error.localizedDescription) Se conservaron sus residuos.")])
            }
        }
        return batch.plans.compactMap { results[$0.program.id] }
    }
}
