import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DataLibraryView: View {
    @State private var selectingDatabase = false
    @State private var importing = false
    @State private var message = ""

    var body: some View {
        Form {
            Section("India Data") {
                Text("The included India sample is synthetic. Import an approved building database or use Portfolio Intelligence to import your OED exposure files.")
                Text(AppDataLocations.indiaDatabaseURL.path)
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Button(importing ? "Importing database..." : "Import India Database...") { selectingDatabase = true }
                    .disabled(importing)
                if !message.isEmpty { Text(message).font(.callout).accessibilityIdentifier("data-import-status") }
            }
            Section("Storage and Portability") {
                Text("Datasets, run outputs and exports are stored under your own Application Support folder. The app never needs the original developer's Desktop or Build folders.")
                Button("Open Data Folder") { NSWorkspace.shared.open(AppDataLocations.applicationSupportDirectory) }
                Button("Open India OED Sample") {
                    NSWorkspace.shared.open(AppDataLocations.current.starterDirectory.appendingPathComponent("India/OED"))
                }
                Text("Forecasts and map tiles require network access. Optional Earth Engine and GDAL workflows require your own configuration. Back up this folder and Documents/ClimateLiberator to retain your user data when moving Macs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 470)
        .fileImporter(isPresented: $selectingDatabase, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            importing = true
            message = "Validating and copying database..."
            Task {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        try AppDataBootstrap.installIndiaDatabase(from: url)
                    }.value
                    message = "India database installed. The previous database, if present, was retained as a backup."
                    NotificationCenter.default.post(name: .climateLiberatorIndiaDataChanged, object: nil)
                } catch { message = error.localizedDescription }
                importing = false
            }
        }
    }
}
