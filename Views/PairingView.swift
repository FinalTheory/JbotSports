import SwiftUI
import CoreBluetooth

struct PairingView: View {
    @ObservedObject var ble: BLEManager

    var body: some View {
        List {
            Section(NSLocalizedString("section_devices", comment: "Devices section")) {
                ForEach(ble.discovered, id: \.identifier) { p in
                    Button {
                        ble.connect(p)
                    } label: {
                        HStack {
                            Text(p.name ?? NSLocalizedString("label_unknown", comment: "Unknown device"))
                            Spacer()
                            if ble.connected?.identifier == p.identifier && ble.isReady {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if ble.connectingID == p.identifier {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }
                    }
                }
            }

            Section {
                Button(ble.isScanning ? NSLocalizedString("label_scanning", comment: "Scanning") : NSLocalizedString("action_rescan", comment: "Rescan")) { ble.startScan() }
            }
        }
        .navigationTitle(NSLocalizedString("label_pair", comment: "Pair"))
    }
}
