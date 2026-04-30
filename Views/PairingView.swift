import SwiftUI
import CoreBluetooth

struct PairingView: View {
    @ObservedObject var ble: BLEManager

    var body: some View {
        List {
            Section("Devices") {
                ForEach(ble.discovered, id: \.identifier) { p in
                    Button {
                        ble.connect(p)
                    } label: {
                        HStack {
                            Text(p.name ?? "Unknown")
                            Spacer()
                            if ble.connected?.identifier == p.identifier {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Rescan") { ble.startScan() }
            }
        }
        .navigationTitle("Pair")
    }
}
