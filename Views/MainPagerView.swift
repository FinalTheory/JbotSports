import SwiftUI

struct MainPagerView: View {
    @ObservedObject var vm: ControlViewModel

    var body: some View {
        TabView {
            Page1View(vm: vm)
            Page2View(vm: vm)
            Page3View(vm: vm)
        }
        .tabViewStyle(.verticalPage)
    }
}
