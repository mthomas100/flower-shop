import SwiftUI

/// The shop's front door.
struct LaunchView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            VStack(alignment: .leading, spacing: 22) {
                step("hand.pinch", "Look at a flower and pinch, then pull it out of the shop.")
                step("rotate.3d", "Hold the pinch to carry it. Turn your hand to turn the flower.")
                step("arrow.down.to.line", "Let go over the vase and it slides in. Seven stems make a bouquet.")

                Button {
                    Task { await enterShop() }
                } label: {
                    Label("Open the Shop", systemImage: "door.left.hand.open")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .controlSize(.extraLarge)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.86, green: 0.42, blue: 0.55))
                .disabled(appModel.immersiveSpaceState != .closed)
                .padding(.top, 6)
            }
            .padding(36)
        }
        .frame(width: 720)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            // Simulator/testing convenience: `-autoOpenShop` walks straight in.
            if ProcessInfo.processInfo.arguments.contains("-autoOpenShop"), appModel.immersiveSpaceState == .closed {
                await enterShop()
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = ShopArt.background {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 720, height: 300)
                    .clipped()
            }
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text("The Flower Shop")
                    .font(.system(size: 48, weight: .semibold, design: .serif))
                Text("Pick your stems and arrange a bouquet, right in your room.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(32)
        }
        .frame(width: 720, height: 300)
    }

    private func step(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.pink.opacity(0.9))
            Text(text)
                .font(.title3)
        }
    }

    private func enterShop() async {
        appModel.immersiveSpaceState = .inTransition
        switch await openImmersiveSpace(id: AppModel.immersiveSpaceID) {
        case .opened:
            dismissWindow(id: AppModel.launchWindowID)
        case .userCancelled, .error:
            appModel.immersiveSpaceState = .closed
        @unknown default:
            appModel.immersiveSpaceState = .closed
        }
    }
}
