import SwiftUI

@main
struct TennisCtlWatchApp: App {
    @StateObject private var ble = BLEManager()
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
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 11, weight: .regular))
                            }
                        }
                    }
            }
        }
    }
}
