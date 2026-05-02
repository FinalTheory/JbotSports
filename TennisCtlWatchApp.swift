import SwiftUI

@main
struct TennisCtlWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var ble: BLEManager
    @StateObject private var vm: ControlViewModel
    @State private var txFlashText: String = ""
    @State private var txFlashVisible: Bool = false
    @State private var txFlashToken: UUID = UUID()
    @State private var presetFlashText: String = ""
    @State private var presetFlashVisible: Bool = false
    @State private var presetFlashToken: UUID = UUID()

    init() {
        let b = BLEManager()
        _ble = StateObject(wrappedValue: b)
        _vm = StateObject(wrappedValue: ControlViewModel(ble: b))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                MainPagerView(vm: vm)
                    .overlay(alignment: .top) {
                        if vm.debugEnabled && (presetFlashVisible || txFlashVisible) {
                            VStack(spacing: 1) {
                                if presetFlashVisible {
                                    Text(presetFlashText)
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .lineLimit(1)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                        .transition(.opacity)
                                }
                                if txFlashVisible {
                                    Text(txFlashText)
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .lineLimit(1)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                        .transition(.opacity)
                                }
                            }
                            .padding(.top, -24)
                        }
                    }
                    .onReceive(ble.$lastTxHex) { hex in
                        guard vm.debugEnabled else { return }
                        guard !hex.isEmpty else { return }
                        showTxFlash(txSummary(for: hex))
                    }
                    .onReceive(vm.$flashHint) { hint in
                        guard vm.debugEnabled else { return }
                        guard !hint.isEmpty else { return }
                        showPresetFlash(hint)
                    }
                    .onChange(of: vm.debugEnabled) { enabled in
                        if !enabled {
                            txFlashVisible = false
                            presetFlashVisible = false
                        }
                    }
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

    private func txSummary(for hex: String) -> String {
        let lower = hex.lowercased()
        guard lower.count >= 8 else { return "TX \(lower)" }
        let cmd = String(lower.dropFirst(4).prefix(4))
        switch cmd {
        case "0702", "0722":
            return "TX START"
        case "0601":
            return "TX STOP"
        case "0301":
            return "TX FREQ"
        case "0401":
            return "TX HEIGHT"
        case "0b01":
            return "TX TUNE"
        default:
            return "TX \(cmd)"
        }
    }

    private func showTxFlash(_ text: String) {
        txFlashText = text
        txFlashToken = UUID()
        let token = txFlashToken
        withAnimation(.easeInOut(duration: 0.12)) {
            txFlashVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard txFlashToken == token else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                txFlashVisible = false
            }
        }
    }

    private func showPresetFlash(_ text: String) {
        presetFlashText = text
        presetFlashToken = UUID()
        let token = presetFlashToken
        withAnimation(.easeInOut(duration: 0.12)) {
            presetFlashVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard presetFlashToken == token else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                presetFlashVisible = false
            }
        }
    }
}
