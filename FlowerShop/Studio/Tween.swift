import RealityKit

/// Frame-driven animation of an entity's local transform. Unlike `Entity.move(to:)` it composes with
/// other systems that write the same entity (rotation can be left alone for spinning shelf flowers),
/// and it can run a completion handler.
struct TweenComponent: Component {
    enum Easing {
        case linear, easeIn, easeOut, easeInOut, easeOutBack

        func callAsFunction(_ t: Float) -> Float {
            switch self {
            case .linear: return t
            case .easeIn: return t * t * t
            case .easeOut: return 1 - pow(1 - t, 3)
            case .easeInOut: return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            case .easeOutBack:
                let c1: Float = 1.70158
                let c3 = c1 + 1
                return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
            }
        }
    }

    var from: Transform
    var to: Transform
    var animatesRotation: Bool
    var duration: Float
    var delay: Float
    var easing: Easing
    var elapsed: Float = 0
    var onComplete: (@MainActor (Entity) -> Void)?
}

extension Entity {
    /// Animates this entity's local transform (relative to its parent) to `target`.
    @MainActor
    func tween(to target: Transform, duration: Float, delay: Float = 0, easing: TweenComponent.Easing = .easeInOut,
               animatesRotation: Bool = true, onComplete: (@MainActor (Entity) -> Void)? = nil) {
        components.set(TweenComponent(from: transform, to: target, animatesRotation: animatesRotation,
                                      duration: max(duration, 0.001), delay: delay, easing: easing, onComplete: onComplete))
    }

    @MainActor
    func cancelTween() {
        components.remove(TweenComponent.self)
    }
}

struct TweenSystem: System {
    private static let query = EntityQuery(where: .has(TweenComponent.self))

    init(scene: RealityKit.Scene) {}

    mutating func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        var finished: [(Entity, (@MainActor (Entity) -> Void)?)] = []

        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var tween = entity.components[TweenComponent.self] else { continue }
            if tween.delay > 0 {
                tween.delay -= dt
                if tween.delay <= 0 { tween.from = entity.transform } // Start from wherever it is by then.
                entity.components.set(tween)
                continue
            }
            tween.elapsed += dt
            let t = min(tween.elapsed / tween.duration, 1)
            let k = tween.easing(t)

            var transform = entity.transform
            transform.scale = simd_max(tween.from.scale + (tween.to.scale - tween.from.scale) * k, SIMD3(repeating: 0.0001))
            transform.translation = tween.from.translation + (tween.to.translation - tween.from.translation) * k
            if tween.animatesRotation {
                transform.rotation = simd_slerp(tween.from.rotation, tween.to.rotation, min(max(k, 0), 1))
            }
            entity.transform = transform

            if t >= 1 {
                entity.components.remove(TweenComponent.self)
                finished.append((entity, tween.onComplete))
            } else {
                entity.components.set(tween)
            }
        }

        for (entity, completion) in finished {
            completion?(entity)
        }
    }
}
