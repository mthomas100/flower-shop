import SwiftUI
import RealityKit

@main
struct FlowerShopApp: App {
    @State private var appModel = AppModel()

    init() {
        FlowerComponent.registerComponent()
        VaseComponent.registerComponent()
        ShelfSpinComponent.registerComponent()
        TweenComponent.registerComponent()
        BouquetSystem.registerSystem()
        TweenSystem.registerSystem()
    }

    var body: some SwiftUI.Scene {
        WindowGroup(id: AppModel.launchWindowID) {
            LaunchView()
                .environment(appModel)
        }
        .defaultSize(width: 720, height: 600)
        .windowResizability(.contentSize)

        ImmersiveSpace(id: AppModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear { appModel.immersiveSpaceState = .open }
                .onDisappear { appModel.immersiveSpaceState = .closed }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
