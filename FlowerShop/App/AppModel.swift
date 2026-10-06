import SwiftUI

/// App-wide state shared by the launch window and the immersive shop.
@MainActor
@Observable
final class AppModel {
    static let launchWindowID = "launch"
    static let immersiveSpaceID = "shop"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
}
