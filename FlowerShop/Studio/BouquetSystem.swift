import RealityKit

/// Per-frame bouquet behavior: spins shelf flowers, watches dropped flowers until they come to rest,
/// and keeps arranged flowers locked to the vase while it moves.
struct BouquetSystem: System {
    private static let flowers = EntityQuery(where: .has(FlowerComponent.self))
    private static let vases = EntityQuery(where: .has(VaseComponent.self))
    private static let spinners = EntityQuery(where: .has(ShelfSpinComponent.self))

    /// Speeds below these count as "at rest".
    private static let restLinearSpeed: Float = 0.035
    private static let restAngularSpeed: Float = 0.7
    private static let restDuration: Float = 0.35
    private static let maxSettleDuration: Float = 4.5

    @MainActor static weak var studio: BouquetStudio?

    init(scene: RealityKit.Scene) {}

    mutating func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)

        for entity in context.entities(matching: Self.spinners, updatingSystemWhen: .rendering) {
            guard let spin = entity.components[ShelfSpinComponent.self] else { continue }
            entity.orientation = simd_quatf(angle: spin.speed * dt, axis: [0, 1, 0]) * entity.orientation
        }

        var vaseTransform: simd_float4x4?
        for vase in context.entities(matching: Self.vases, updatingSystemWhen: .rendering) {
            vaseTransform = vase.transformMatrix(relativeTo: nil)
            break
        }

        for entity in context.entities(matching: Self.flowers, updatingSystemWhen: .rendering) {
            guard var flower = entity.components[FlowerComponent.self] else { continue }
            switch flower.phase {
            case .arranged:
                if let offset = flower.vaseOffset, let vaseTransform {
                    entity.setTransformMatrix(vaseTransform * offset, relativeTo: nil)
                }

            case .settling:
                flower.settleTime += dt
                let motion = entity.components[PhysicsMotionComponent.self]
                let linear = simd_length(motion?.linearVelocity ?? .zero)
                let angular = simd_length(motion?.angularVelocity ?? .zero)
                flower.calmTime = (linear < Self.restLinearSpeed && angular < Self.restAngularSpeed) ? flower.calmTime + dt : 0
                entity.components.set(flower)

                if flower.calmTime > Self.restDuration || flower.settleTime > Self.maxSettleDuration {
                    Self.studio?.flowerCameToRest(entity)
                } else if entity.position(relativeTo: nil).y < -0.5 {
                    Self.studio?.discard(entity)
                }

            default:
                break
            }
        }
    }
}
