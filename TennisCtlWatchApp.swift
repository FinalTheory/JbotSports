import SwiftUI

@main
struct TennisCtlWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var ble: BLEManager
    @StateObject private var vm: ControlViewModel

    init() {
        let b = BLEManager()
        _ble = StateObject(wrappedValue: b)
        _vm = StateObject(wrappedValue: ControlViewModel(ble: b))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                MainPagerView(vm: vm)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink {
                                PairingView(ble: ble)
                            } label: {
                                Text("Pair")
                                    .font(.system(size: 16, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
            }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .background:
                    ble.prepareForBackground()
                case .active:
                    ble.resumeConnectionAfterForeground(timeout: 3.0)
                default:
                    break
                }
            }
        }
    }
}
