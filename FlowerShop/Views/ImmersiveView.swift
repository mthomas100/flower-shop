import RealityKit
import SwiftUI

private enum PanelAttachment {
    static let id = "shop-panel"
}

/// The flower shop around you: shop panel, vase, and stems.
struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @State private var studio = BouquetStudio()

    var body: some View {
        RealityView { content, attachments in
            // Models load inside the make closure, the way RealityKit expects, before the shop is assembled.
            await studio.loadAssets()
            studio.install(in: content, panelView: attachments.entity(for: PanelAttachment.id))
        } attachments: {
            // The panel uses the attachments closure rather than `ViewAttachmentComponent(rootView:)`: on the
            // visionOS 27 simulator, component-based attachments stopped rendering once any entity had been
            // loaded from a file, while closure-based attachments keep working.
            Attachment(id: PanelAttachment.id) {
                ShopPanelView(studio: studio)
            }
        }
        .task {
            studio.onLeave = {
                Task { @MainActor in
                    appModel.immersiveSpaceState = .inTransition
                    await dismissImmersiveSpace()
                }
            }
            await studio.start()
        }
        .onDisappear {
            studio.stop()
            openWindow(id: AppModel.launchWindowID)
        }
    }
}
