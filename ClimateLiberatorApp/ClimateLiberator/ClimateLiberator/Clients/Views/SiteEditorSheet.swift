import SwiftUI

/// Add or edit one site. Coordinates can be typed or pasted as "lat, lon".
struct SiteEditorSheet: View {
    @State var site: Site
    let accent: Color
    let onSave: (Site) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var coordinateText = ""

    init(site: Site, accent: Color, onSave: @escaping (Site) -> Void) {
        _site = State(initialValue: site)
        self.accent = accent
        self.onSave = onSave
        if let latitude = site.latitude, let longitude = site.longitude {
            _coordinateText = State(initialValue: CoordinateText.format(latitude: latitude, longitude: longitude))
        }
    }

    private var parsed: (latitude: Double, longitude: Double)? { CoordinateText.parse(coordinateText) }
    private var coordinateIsInvalid: Bool {
        !coordinateText.trimmingCharacters(in: .whitespaces).isEmpty && parsed == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(site.name.isEmpty ? "New Site" : site.name).font(.title2.weight(.semibold))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                DSFormRow("Name", width: 110) {
                    TextField("e.g. Ambattur injection moulding shop", text: $site.name).textFieldStyle(.roundedBorder)
                }
                DSFormRow("Type", width: 110) {
                    Picker("Type", selection: $site.kind) {
                        ForEach(SiteKind.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                DSFormRow("Address", width: 110) {
                    TextField("Street and locality", text: $site.address, axis: .vertical)
                        .lineLimit(1...3).textFieldStyle(.roundedBorder)
                }
                DSFormRow("District", width: 110) {
                    HStack {
                        TextField("District", text: $site.district).textFieldStyle(.roundedBorder)
                        TextField("State", text: $site.state).textFieldStyle(.roundedBorder)
                        TextField("PIN", text: $site.pinCode).textFieldStyle(.roundedBorder).frame(width: 90)
                    }
                }
                DSFormRow("Coordinates", width: 110) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Latitude, longitude, e.g. 11.10850, 77.34110", text: $coordinateText)
                            .textFieldStyle(.roundedBorder)
                        Text(coordinateIsInvalid ? "Enter latitude and longitude in decimal degrees, separated by a comma."
                                                 : "Copy them from a map app: right-click the site in Apple Maps or Google Maps.")
                            .font(.caption)
                            .foregroundStyle(coordinateIsInvalid ? DSStyle.bad : DSStyle.faint)
                    }
                }
                DSFormRow("Notes", width: 110) {
                    TextField("Processes, floor area, anything relevant", text: $site.notes, axis: .vertical)
                        .lineLimit(1...4).textFieldStyle(.roundedBorder)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    var saved = site
                    saved.latitude = parsed?.latitude
                    saved.longitude = parsed?.longitude
                    onSave(saved)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
                .disabled(coordinateIsInvalid)
            }
        }
        .padding(22)
        .frame(width: 620)
    }
}
