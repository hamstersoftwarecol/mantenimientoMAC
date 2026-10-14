import SwiftUI
import AppKit

@MainActor
final class MaintenanceModel: ObservableObject {
    @Published var result: ScanResult?
    @Published var busy = false
    @Published var cleaning = false
    @Published var status = "Listo para analizar tu Mac"
    @Published var selected = Set<String>()
    @Published var search = ""
    @Published var outcomes: [CleanOutcome] = []
    @Published var running = Set<String>()
    @Published var lastScan: Date?
    @Published var uninstallBatch: BatchUninstallPlan?
    @Published var batchOutcomes: [BatchProgramOutcome] = []
    @Published var batchRunning = false
    @Published var stopRequested = false
    private var token: CancellationToken?

    var programs: [InstalledProgram] {
        (result?.inventory.programs ?? []).filter { search.isEmpty ||
            "\($0.name) \($0.origin) \($0.path)".localizedCaseInsensitiveContains(search) }
    }
    var caches: [CacheEntry] {
        (result?.entries ?? []).filter { search.isEmpty ||
            "\($0.owner) \($0.url.path)".localizedCaseInsensitiveContains(search) }
    }
    var chosen: [CacheEntry] { (result?.entries ?? []).filter { selected.contains($0.id) } }
    var chosenBytes: Int64 { chosen.reduce(0) { $0 + $1.bytes } }
    var totalBytes: Int64 { (result?.entries ?? []).reduce(0) { $0 + $1.bytes } }

    func blockReason(_ entry: CacheEntry) -> String? {
        if let reason = entry.blockedReason { return reason }
        if let bundle = entry.bundleID, running.contains(bundle) { return "Aplicación abierta: ciérrala y vuelve a analizar." }
        return nil
    }

    func refreshRunning() {
        running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func analyze(keepOutcomes: Bool = false) {
        guard !busy else { return }
        busy = true
        result = nil
        selected.removeAll()
        if !keepOutcomes { outcomes = []; batchOutcomes = [] }
        refreshRunning()
        status = "Leyendo aplicaciones y Homebrew…"
        let cancellation = CancellationToken()
        token = cancellation
        Task { [self] in
            do {
                let scan = try await Task.detached(priority: .userInitiated) { [weak self] in
                    let inventory = try Inventory.scan(cancelled: { cancellation.isCancelled })
                    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
                    return try Analysis.scan(inventory: inventory, userCacheRoot: root,
                        cancelled: { cancellation.isCancelled }, progress: { message in
                            Task { @MainActor [weak self] in self?.status = message }
                        })
                }.value
                if cancellation.isCancelled { throw MaintenanceError.cancelled }
                result = scan
                lastScan = Date()
                refreshRunning()
                status = "Análisis terminado · \(scan.inventory.programs.count) programas · \(scan.entries.count) entradas de caché"
            } catch {
                status = error.localizedDescription
            }
            busy = false
            token = nil
        }
    }

    func cancel() {
        token?.cancel()
        stopRequested = batchRunning
        status = batchRunning ? "El lote se detendrá después del programa actual…" : "Deteniendo análisis…"
    }

    static func currentRunning() -> RunningPrograms {
        let applications = NSWorkspace.shared.runningApplications
        return RunningPrograms(bundleIDs: Set(applications.compactMap(\.bundleIdentifier)),
                               paths: Set(applications.compactMap { $0.bundleURL?.path }))
    }

    static func uninstallEnvironment(_ programs: [InstalledProgram]) -> UninstallEnvironment {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return UninstallEnvironment(home: home, applicationRoots: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")], inventory: programs)
    }

    func analyzeUninstall(_ programs: [InstalledProgram]) {
        guard !busy, let inventory = result?.inventory.programs else { return }
        guard !programs.isEmpty else { return }
        busy = true
        outcomes = []
        batchOutcomes = []
        status = "Analizando \(programs.count) programas y sus residuos…"
        let cancellation = CancellationToken()
        token = cancellation
        let environment = Self.uninstallEnvironment(inventory)
        let runningNow = Self.currentRunning()
        Task { [self] in
            do {
                let batch = try await Task.detached(priority: .userInitiated) { [weak self] in
                    try BatchUninstaller.analyze(programs: programs, environment: environment, running: runningNow,
                        brew: BrewService.live(cancelled: { cancellation.isCancelled }), cancelled: { cancellation.isCancelled }, progress: { message in
                            Task { @MainActor [weak self] in
                                guard let self = self, self.token === cancellation else { return }
                                self.status = "Análisis \(message.completed + 1)/\(message.total): \(message.message)"
                            }
                        })
                }.value
                if cancellation.isCancelled { throw MaintenanceError.cancelled }
                uninstallBatch = batch
                status = "Revisión del lote: \(batch.ready.count) listos · \(batch.blocked.count) bloqueados"
            } catch { status = error.localizedDescription }
            busy = false
            token = nil
        }
    }

    func uninstall(_ batch: BatchUninstallPlan, selectedResidues: Set<String>) {
        guard !busy else { return }
        uninstallBatch = nil
        busy = true
        cleaning = true
        batchRunning = true
        stopRequested = false
        let cancellation = CancellationToken()
        token = cancellation
        status = "Comprobando el lote de \(batch.ready.count) programas…"
        Task { [self] in
            batchOutcomes = await Task.detached(priority: .userInitiated) { [weak self] in
                BatchUninstaller.execute(batch: batch, selectedResidues: selectedResidues, environment: {
                    let inventory = try Inventory.scan(cancelled: { false })
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    return UninstallEnvironment(home: home,
                        applicationRoots: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")], inventory: inventory.programs)
                }, running: {
                    DispatchQueue.main.sync { MaintenanceModel.currentRunning() }
                }, brew: BrewService.live(), cancelled: { cancellation.isCancelled }, progress: { progress in
                    Task { @MainActor [weak self] in
                        guard let self = self, self.batchRunning, self.token === cancellation else { return }
                        if !self.stopRequested { self.status = progress.message }
                    }
                })
            }.value
            batchRunning = false
            busy = false
            cleaning = false
            token = nil
            stopRequested = false
            analyze(keepOutcomes: true)
        }
    }

    func clean(_ entries: [CacheEntry]) {
        guard !busy, let roots = result?.roots, !entries.isEmpty else { return }
        busy = true
        cleaning = true
        selected.removeAll()
        status = "Enviando elementos seleccionados a la Papelera…"
        Task {
            outcomes = await Task.detached(priority: .userInitiated) {
                Cleaner.clean(entries: entries, roots: roots, runningBundles: {
                    DispatchQueue.main.sync {
                        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
                    }
                })
            }.value
            busy = false
            cleaning = false
            analyze(keepOutcomes: true)
        }
    }
}

struct ContentView: View {
    @StateObject private var model = MaintenanceModel()
    @State private var tab = 0
    @State private var showConfirmation = false
    @State private var confirmationEntries: [CacheEntry] = []
    @State private var showIssues = false
    @State private var programSelection = Set<String>()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            HStack(spacing: 16) {
                metric("Programas", value: model.result.map { "\($0.inventory.programs.count)" } ?? "—", icon: "square.grid.2x2")
                metric("Cachés estimadas", value: model.result == nil ? "—" : formatBytes(model.totalBytes), icon: "externaldrive")
                metric("Selección", value: "\(model.chosen.count) · \(formatBytes(model.chosenBytes))", icon: "checkmark.circle")
            }
            HStack {
                Picker("Vista", selection: $tab) {
                    Text("Programas instalados").tag(0)
                    Text("Cachés").tag(1)
                }.pickerStyle(.segmented).frame(width: 330)
                Spacer()
                TextField("Buscar nombre, origen o ubicación", text: $model.search)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 330)
                    .accessibilityLabel("Buscar programas y cachés")
            }
            if model.result == nil {
                emptyState
            } else if tab == 0 {
                programList
            } else {
                cacheList
            }
            if !model.outcomes.isEmpty { outcomesPanel }
            if !model.batchOutcomes.isEmpty { batchOutcomesPanel }
            footer
        }
        .padding(24)
        .frame(minWidth: 920, minHeight: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showConfirmation) { confirmation }
        .sheet(isPresented: $showIssues) { issues }
        .sheet(item: $model.uninstallBatch) { batch in
            UninstallReviewView(batch: batch, onCancel: { model.uninstallBatch = nil }, onConfirm: { selected in
                model.uninstall(batch, selectedResidues: selected)
            })
        }
        .onChange(of: model.lastScan) { _ in programSelection.removeAll() }
        .onChange(of: scenePhase) { phase in if phase == .active { model.refreshRunning() } }
        .onAppear {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 32)).foregroundStyle(Color.accentColor)
                .frame(width: 64, height: 64)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Mantenimiento Mac").font(.largeTitle.weight(.semibold))
                Text("Conoce tus programas. Revisa cachés y residuos. Elige qué quitar.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.busy {
                ProgressView().controlSize(.small)
                if model.batchRunning {
                    Button(model.stopRequested ? "Deteniendo lote…" : "Detener lote", action: model.cancel).disabled(model.stopRequested)
                } else if !model.cleaning { Button("Detener", action: model.cancel) }
            } else {
                Button(action: { model.analyze() }) {
                    Label(model.result == nil ? "Analizar mi Mac" : "Volver a analizar", systemImage: "arrow.clockwise")
                }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: model.busy ? "magnifyingglass" : "desktopcomputer")
                .font(.system(size: 44)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(model.busy ? "Analizando tu computadora" : "Primero, una vista de tu Mac")
                .font(.title2.weight(.semibold))
            Text(model.busy ? "Puedes detener el análisis. Esta etapa solo lee información." :
                "Pulsa Analizar mi Mac para ver las aplicaciones, los paquetes de Homebrew y el tamaño de tus cachés.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 540)
            Text("Ninguna caché se limpia durante el análisis.").font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var programList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.result?.inventory.brewStatus ?? "").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Table(model.programs, selection: $programSelection) {
                TableColumn("Elegir") { program in
                    Toggle("Seleccionar \(program.name)", isOn: Binding(
                        get: { programSelection.contains(program.id) },
                        set: { if $0 { programSelection.insert(program.id) } else { programSelection.remove(program.id) } }
                    )).toggleStyle(.checkbox).labelsHidden().accessibilityLabel("Seleccionar programa \(program.name)").disabled(model.busy)
                }.width(50)
                TableColumn("Programa", value: \.name).width(min: 150, ideal: 210)
                TableColumn("Versión", value: \.version).width(min: 80, ideal: 100, max: 150)
                TableColumn("Origen", value: \.origin).width(min: 130, ideal: 160, max: 200)
                TableColumn("Ubicación / paquete") { p in
                    Text(p.path).font(.callout).textSelection(.enabled).help(p.path)
                }.width(min: 230, ideal: 340)
            }
            Text("«Aplicación local» indica que no se verificó una asociación con Homebrew. Las fórmulas pueden ser herramientas sin ventana.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Text("\(selectedPrograms.count) programas seleccionados").font(.callout)
                Button("Seleccionar resultados") { programSelection.formUnion(model.programs.map(\.id)) }.disabled(model.busy || model.programs.isEmpty)
                Button("Quitar selección") { programSelection.removeAll() }.disabled(model.busy || programSelection.isEmpty)
                Spacer()
                Button(selectedPrograms.count > 1 ? "Desinstalar \(selectedPrograms.count) programas…" : "Desinstalar…") {
                    model.analyzeUninstall(selectedPrograms)
                }.disabled(model.busy || selectedPrograms.isEmpty)
            }
            Text("Marca las casillas o usa ⌘ clic para elegir varios. La selección se conserva al buscar; el resumen incluye todos los seleccionados.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var selectedPrograms: [InstalledProgram] {
        (model.result?.inventory.programs ?? []).filter { programSelection.contains($0.id) }
    }

    private var cacheList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ordenadas de mayor a menor tamaño").foregroundStyle(.secondary)
                Spacer()
                Button("Seleccionar resultados") {
                    for entry in model.caches where model.blockReason(entry) == nil { model.selected.insert(entry.id) }
                }.disabled(model.busy || model.caches.isEmpty)
                Button("Quitar selección") { model.selected.removeAll() }.disabled(model.busy || model.selected.isEmpty)
            }.font(.callout)
            List(model.caches) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Toggle("Seleccionar \(entry.url.lastPathComponent)", isOn: Binding(
                        get: { model.selected.contains(entry.id) },
                        set: { if $0 { model.selected.insert(entry.id) } else { model.selected.remove(entry.id) } }
                    )).toggleStyle(.checkbox).labelsHidden()
                        .accessibilityLabel("Seleccionar \(entry.url.lastPathComponent), \(entry.owner)")
                        .disabled(model.busy || model.blockReason(entry) != nil)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.owner).font(.headline)
                            if entry.owner == "Sin identificar" {
                                Text("Revisar antes de limpiar").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(entry.url.path).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2).help(entry.url.path)
                        if let reason = model.blockReason(entry) {
                            Label(reason, systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
                        } else if entry.incomplete {
                            Label("Medición incompleta: el tamaño puede ser mayor.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(entry.blockedReason != nil ? "Sin medir" : "\(entry.incomplete ? "≥ " : "")\(formatBytes(entry.bytes))")
                        .font(.body.weight(.medium)).monospacedDigit().padding(.top, 2)
                }.padding(.vertical, 8)
            }.listStyle(.inset)
            HStack(spacing: 16) {
                Text("Solo cachés del usuario y Homebrew. Las carpetas sin identificar requieren revisión.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Limpiar seleccionadas…") {
                    confirmationEntries = model.chosen
                    showConfirmation = true
                }.buttonStyle(.borderedProminent).disabled(model.busy || model.chosen.isEmpty)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Text(model.status).font(.callout).lineLimit(1).help(model.status)
                Spacer()
                if let count = model.result?.issues.count, count > 0 {
                    Button("Ver \(count) incidencias") { showIssues = true }
                }
            }
            Text("La limpieza envía los elementos a la Papelera. El espacio se libera cuando la vacías desde Finder.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var outcomesPanel: some View {
        DisclosureGroup("Resultado: \(model.outcomes.filter(\.success).count) operaciones completadas · \(model.outcomes.filter { !$0.success }.count) sin completar") {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.outcomes) { outcome in
                        Label("\(outcome.path)\n\(outcome.detail)", systemImage: outcome.success ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(maxHeight: 100)
        }.font(.callout)
    }

    private var batchOutcomesPanel: some View {
        DisclosureGroup("Resultado del lote: \(model.batchOutcomes.filter { $0.state == .completed || $0.state == .partial }.count) desinstalados de \(model.batchOutcomes.count) programas") {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.batchOutcomes) { result in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(result.program.name) · \(result.state.rawValue)").font(.headline)
                            ForEach(result.items) { item in
                                Label("\(item.path)\n\(item.detail)", systemImage: item.success ? "checkmark.circle" : "exclamationmark.triangle")
                                    .font(.caption).textSelection(.enabled)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(maxHeight: 160)
        }.font(.callout)
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Revisar limpieza", systemImage: "trash").font(.title2.weight(.semibold))
            Text("\(confirmationEntries.count) elementos · \(formatBytes(confirmationEntries.reduce(0) { $0 + $1.bytes })) estimados")
                .font(.headline)
            Text("Cierra las aplicaciones que usen estas cachés. Pueden volver a crearlas al abrirse. Los elementos se enviarán a la Papelera; el programa no la vacía.")
            if confirmationEntries.contains(where: { $0.owner == "Sin identificar" }) {
                Label("Incluiste carpetas sin propietario identificado. Revisa sus rutas antes de continuar.", systemImage: "exclamationmark.triangle")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(confirmationEntries) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(entry.owner) · \(formatBytes(entry.bytes))\(entry.incomplete ? " (incompleto)" : "")").font(.headline)
                            Text(entry.url.path).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(12)
            }.frame(height: 220).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Cancelar") { showConfirmation = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Enviar a la Papelera") {
                    showConfirmation = false
                    model.clean(confirmationEntries)
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 620)
    }

    private var issues: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Incidencias del análisis").font(.title2.weight(.semibold))
            Text("Las carpetas inaccesibles no cuentan como cero bytes. El resto del análisis sigue disponible.")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array((model.result?.issues ?? []).enumerated()), id: \.offset) { _, issue in
                        Text(issue).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                }
            }.frame(height: 300)
            HStack { Spacer(); Button("Cerrar") { showIssues = false }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 660)
    }
}

@main
struct MaintenanceApp: App {
    var body: some Scene {
        WindowGroup("Mantenimiento Mac") { ContentView() }
            .defaultSize(width: 1060, height: 780)
    }
}
