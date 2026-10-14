import SwiftUI

struct UninstallReviewView: View {
    let batch: BatchUninstallPlan
    let onCancel: () -> Void
    let onConfirm: (Set<String>) -> Void
    @State private var selected = Set<String>()
    @State private var confirming = false

    private var chosen: [ResidueEntry] { batch.ready.flatMap(\.residues).filter { selected.contains($0.id) } }
    private var chosenBytes: Int64 { chosen.reduce(0) { $0 + $1.bytes } }
    private var observations: [String] { batch.plans.flatMap { plan in plan.issues.map { "\(plan.program.name): \($0)" } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: confirming ? "trash" : "magnifyingglass").font(.title).foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(confirming ? "Confirmar desinstalación del lote" : "Revisar programas y residuos").font(.title2.weight(.semibold))
                    Text("\(batch.ready.count) listos · \(batch.blocked.count) bloqueados · \(batch.plans.count) seleccionados").font(.headline)
                }
                Spacer()
            }
            if confirming { summary } else { residueList }
            if !observations.isEmpty {
                DisclosureGroup("\(observations.count) observaciones del análisis") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(observations.enumerated()), id: \.offset) { _, observation in
                                Text(observation).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.frame(maxHeight: 80)
                }.font(.callout)
            }
            Divider()
            HStack {
                Button("Cancelar", action: onCancel).keyboardShortcut(.cancelAction)
                if confirming { Button("Volver a revisar") { confirming = false } }
                Spacer()
                if confirming {
                    Button("Desinstalar \(batch.ready.count) programas", role: .destructive) { onConfirm(selected) }
                        .buttonStyle(.borderedProminent).disabled(batch.ready.isEmpty)
                } else {
                    Button("Revisar resumen…") { confirming = true }.buttonStyle(.borderedProminent).disabled(batch.ready.isEmpty)
                }
            }
        }.padding(24).frame(width: 780)
    }

    private var residueList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Residuos elegidos: \(chosen.count) · \(formatBytes(chosenBytes))").monospacedDigit()
                Spacer()
                Button("Seleccionar cachés") {
                    selected.formUnion(batch.ready.flatMap(\.residues).filter { $0.kind == .cache && $0.blockedReason == nil }.map(\.id))
                }.disabled(batch.ready.isEmpty)
                Button("Quitar selección") { selected.removeAll() }.disabled(selected.isEmpty)
            }.font(.callout)
            Text("Se desinstalarán los programas listos después de una sola confirmación. Elige los residuos que quieras quitar; todos empiezan sin seleccionar. Los datos y preferencias pueden contener perfiles y configuraciones personales.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(batch.plans) { plan in
                    Section {
                        if let reason = plan.blockedReason {
                            Label(reason, systemImage: "lock.fill").font(.callout).foregroundStyle(.secondary)
                        } else if plan.residues.isEmpty {
                            Text("No se identificaron residuos en el alcance del análisis. Se desinstalará el programa.").font(.callout).foregroundStyle(.secondary)
                        } else {
                            ForEach(plan.residues) { entry in residueRow(entry) }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.program.name).font(.headline)
                            Text(plan.program.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            if plan.blockedReason == nil {
                                Text(plan.program.path.hasPrefix("/") ? "Aplicación: \(plan.applicationIncomplete ? "≥ " : "")\(formatBytes(plan.applicationBytes)) estimados" : "Paquete Homebrew · tamaño no medido")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }.frame(height: 330)
            Text("Los bloqueados se omitirán. No encontrar residuos no garantiza que no existan archivos en otras ubicaciones. Las coincidencias por nombre requieren revisión.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func residueRow(_ entry: ResidueEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("Seleccionar \(entry.url.path)", isOn: Binding(
                get: { selected.contains(entry.id) },
                set: { if $0 { selected.insert(entry.id) } else { selected.remove(entry.id) } }
            )).toggleStyle(.checkbox).labelsHidden().accessibilityLabel("Seleccionar \(entry.kind.rawValue): \(entry.url.path)")
                .disabled(entry.blockedReason != nil)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.kind.rawValue).font(.headline)
                Text(entry.url.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Text(entry.blockedReason ?? entry.evidence).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.blockedReason != nil ? "Sin medir" : "\(entry.incomplete ? "≥ " : "")\(formatBytes(entry.bytes))").monospacedDigit().font(.callout)
        }.padding(.vertical, 6)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            if batch.ready.contains(where: { $0.program.brew != nil }) {
                Label("Homebrew desinstalará sus paquetes y podrá ejecutar sus desinstaladores. Esos paquetes pueden eliminarse sin pasar por la Papelera.", systemImage: "exclamationmark.triangle").font(.callout)
            }
            Text("Las aplicaciones locales y los \(chosen.count) residuos seleccionados se enviarán a la Papelera. Residuos: \(formatBytes(chosenBytes)) estimados.")
            if chosen.contains(where: { $0.kind == .data || $0.kind == .preferences }) {
                Label("Seleccionaste datos o preferencias que pueden incluir perfiles y configuraciones personales.", systemImage: "person.crop.circle.badge.exclamationmark").font(.callout)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(batch.ready.enumerated()), id: \.element.id) { index, plan in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1). \(plan.program.name)").font(.headline)
                            Text(plan.program.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            let residues = plan.residues.filter { selected.contains($0.id) }
                            ForEach(residues) { entry in
                                Text("\(entry.kind.rawValue): \(entry.url.path) · \(formatBytes(entry.bytes))\(entry.incomplete ? " (incompleto)" : "")")
                                    .font(.caption).textSelection(.enabled)
                            }
                            if residues.isEmpty { Text("Se conservarán todos sus residuos identificados.").font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                    ForEach(batch.blocked) { plan in
                        Label("Se omite \(plan.program.name): \(plan.blockedReason ?? "Bloqueado")", systemImage: "lock.fill")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(12)
            }.frame(height: 280).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            Text("Se ejecutará en el orden mostrado. Un fallo no detiene los demás programas. Puedes detener el lote después del programa actual. Si un programa no se desinstala, conserva sus residuos.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
