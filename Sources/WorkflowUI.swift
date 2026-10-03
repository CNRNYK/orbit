import SwiftUI
import AppKit

struct OperationResult: Identifiable {
    let id: String, name: String, status: String
}
extension Store {
    var progressSummary: String { "\(min(completed, total))/\(total) processed · \(max(total - completed, 0)) remaining" }
    var operationResults: [OperationResult] {
        statuses.map { key, value in OperationResult(id: key, name: packages.first { $0.id == key }?.name ?? key, status: value) }.sorted {
            if ($0.status == "Failed") != ($1.status == "Failed") { return $0.status == "Failed" }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    var operationIssues: [String] {
        var seen = Set<String>()
        return output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter {
            let text = $0.lowercased()
            return (text.contains("error:") || text.contains("failed:") || text.contains("permission denied") || (text.hasPrefix("exit status:") && text != "exit status: 0")) && seen.insert($0).inserted
        }.suffix(8).map { $0 }
    }
}
extension MaintenanceState {
    func selectCleanable(group: String? = nil) {
        guard !working else { return }
        selected.formUnion(items.filter { $0.removable && (group == nil || $0.group == group) }.map(\.id))
    }
    func clearGroup(_ group: String) {
        guard !working else { return }; selected.subtract(items.filter { $0.group == group }.map(\.id))
    }
}
struct OperationDetailsView: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Operation details").font(.title2.bold()); Spacer(); Button("Done") { store.showLog = false }.keyboardShortcut(.cancelAction) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.busy && !store.maintenanceState.working { Text(store.progressSummary).font(.headline); Text(store.headline).foregroundStyle(.secondary) }
                    if store.operationResults.isEmpty { Text("No package operation results yet.").foregroundStyle(.secondary) }
                    ForEach(store.operationResults) { result in HStack { Text(result.name); Spacer(); Text(result.status).foregroundStyle(result.status == "Failed" ? .red : .secondary) }.padding(.vertical, 3) }
                    if store.maintenanceState.scanned { Divider(); Text("Cleanup").font(.headline); Text(store.maintenanceState.status) }
                    if !store.operationIssues.isEmpty { Divider(); Text("Errors and diagnostics").font(.headline); ForEach(store.operationIssues, id: \.self) { Text($0).font(.callout).foregroundStyle(.red).textSelection(.enabled) } }
                    DisclosureGroup("Technical log", isExpanded: $store.showTechnicalLog) {
                        VStack(alignment: .leading, spacing: 10) {
                            Button("Copy technical log") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.output, forType: .string) }.disabled(store.output.isEmpty)
                            Text(store.output.isEmpty ? "No technical output recorded." : store.output).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.top, 8)
                    }.padding(.top, 8)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(24).onAppear { store.showTechnicalLog = false }.frame(width: 780, height: 520)
    }
}
