import SwiftUI

struct MainPagerView: View {
    @ObservedObject var vm: ControlViewModel

    var body: some View {
        TabView {
            MainControllerView(vm: vm)
            DetailControllerView(vm: vm)
            RandomShuffleControllerView(vm: vm)
            PresetView(vm: vm)
        }
        .tabViewStyle(.verticalPage)
        .indexViewStyle(.page(backgroundDisplayMode: .never))
    }
}
