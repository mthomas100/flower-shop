import RealityKit

/// Per-flower state. A flower's root entity sits at the center of its bloom (that's where people grab it),
/// with the model as a child offset downward.
struct FlowerComponent: Component {
    enum Phase: Equatable {
        /// On display in front of the shop panel.
        case shelf
        /// In someone's hand.
        case held
        /// Flying itself into the vase after a quick pinch or an "add" tap.
        case placing
        /// Let go in mid-air; it just stays put.
        case floating
        /// Dropped into the vase; gravity and collisions are on until it comes to rest.
        case settling
        /// Came to rest in the vase; locked in place and carried along with the vase.
        case arranged
    }

    var kind: FlowerKind
    var phase: Phase
    var geometry: FlowerGeometry
    var slot: Int?

    /// Pose relative to the vase while arranged.
    var vaseOffset: simd_float4x4?

    var settleTime: Float = 0
    var calmTime: Float = 0
    var grabStartTime: Double = 0
    var grabStartPosition: SIMD3<Float> = .zero
    var grabbedFromShelf = false

    /// Stem bottom relative to the root (bloom center), at full size.
    var stemBottomLocal: SIMD3<Float> { geometry.stemBottom - geometry.bloomCenter }
    var stemTopLocal: SIMD3<Float> { geometry.stemTop - geometry.bloomCenter }
}

struct VaseComponent: Component {
    var geometry: VaseGeometry
}

/// Slow idle turn for flowers on display.
struct ShelfSpinComponent: Component {
    var speed: Float
}
