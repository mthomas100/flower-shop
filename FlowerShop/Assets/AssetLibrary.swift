import FlowerAssets
import Foundation
import RealityKit
import UIKit

/// Measurements of a flower in "flower space": meters, Y-up, origin at the bottom of the stem.
struct FlowerGeometry {
    var height: Float
    var stemBottom: SIMD3<Float>
    /// Where the stem meets the bloom.
    var stemTop: SIMD3<Float>
    var bloomCenter: SIMD3<Float>
    var bloomRadius: Float
    /// Radius used for the stem's physics capsule (a bit thicker than the real stem for stable contacts).
    var stemRadius: Float

    var stemAxis: SIMD3<Float> { simd_normalize(stemTop - stemBottom) }
}

/// Measurements of the vase in "vase space": meters, Y-up, origin at the bottom center.
struct VaseGeometry {
    var height: Float
    var rimHeight: Float
    var innerRadius: Float
    var outerRadius: Float
    var floorHeight: Float
}

struct FlowerAsset {
    /// Normalized model in flower space. Clone it, never mutate it.
    let template: Entity
    let geometry: FlowerGeometry
    let isPlaceholder: Bool
}

struct VaseAsset {
    let template: Entity
    let geometry: VaseGeometry
    let isPlaceholder: Bool
}

/// Loads the Meshy-generated USDZ models (falling back to procedural stand-ins), normalizes them to real-world
/// scale with a predictable origin, and derives the measurements the physics needs.
@MainActor
final class AssetLibrary {
    private(set) var flowers: [FlowerKind: FlowerAsset] = [:]
    private(set) var vase: VaseAsset?

    static let vaseHeight: Float = 0.25

    func loadAll() async {
        let manifest = AssetManifest.load()

        await withTaskGroup(of: Void.self) { group in
            for kind in FlowerKind.allCases {
                group.addTask { @MainActor in
                    self.flowers[kind] = await Self.loadFlower(kind, manifest: manifest?.models[kind.rawValue])
                }
            }
            group.addTask { @MainActor in
                self.vase = await Self.loadVase(manifest: manifest?.models["vase"])
            }
        }
    }

    // MARK: - Flowers

    private static func loadFlower(_ kind: FlowerKind, manifest: AssetManifest.Model?) async -> FlowerAsset {
        guard let loaded = await loadModel(named: kind.resourceName) else {
            let (entity, geometry) = ProceduralModels.flower(kind)
            return FlowerAsset(template: entity, geometry: geometry, isPlaceholder: true)
        }

        // With a manifest the asset already has its stem base on the origin; keep it rather than re-centering.
        let (container, bounds) = normalize(loaded, toHeight: kind.height, centerXZ: manifest == nil)
        let geometry = flowerGeometry(kind: kind, bounds: bounds, manifest: manifest)
        prepareForDisplay(container)
        return FlowerAsset(template: container, geometry: geometry, isPlaceholder: false)
    }

    private static func flowerGeometry(kind: FlowerKind, bounds: BoundingBox, manifest: AssetManifest.Model?) -> FlowerGeometry {
        let height = bounds.extents.y
        let spread = max(bounds.extents.x, bounds.extents.z)

        // Heuristic fallback: the bloom sits at the top and is roughly as wide as the model.
        let fallbackRadius = min(max(spread * 0.42, 0.025), 0.10)
        var geometry = FlowerGeometry(
            height: height,
            stemBottom: [0, 0, 0],
            stemTop: [0, height - fallbackRadius * 1.6, 0],
            bloomCenter: [0, height - fallbackRadius, 0],
            bloomRadius: fallbackRadius,
            stemRadius: 0.0065
        )

        // Prefer the measured manifest, mapped through the same normalization as the mesh.
        if let manifest, let map = manifest.mapper(into: bounds) {
            if let p = manifest.bloomCenter.flatMap(SIMD3<Float>.init(array:)) { geometry.bloomCenter = map(p) }
            if let p = manifest.stemBottom.flatMap(SIMD3<Float>.init(array:)) { geometry.stemBottom = map(p) }
            if let p = manifest.stemTop.flatMap(SIMD3<Float>.init(array:)) { geometry.stemTop = map(p) }
            if let r = manifest.bloomRadius, let h = manifest.height ?? manifest.measuredHeight, h > 0 {
                geometry.bloomRadius = min(max(r * height / h, 0.02), 0.12)
            }
        }

        // Sanity: the bloom must be above the stem bottom and the stem must point mostly up.
        let axis = geometry.stemTop - geometry.stemBottom
        if geometry.bloomCenter.y < height * 0.5 || simd_length(axis) < height * 0.3 || simd_normalize(axis).y < 0.6 {
            geometry.stemBottom = [0, 0, 0]
            geometry.bloomCenter = [0, height - fallbackRadius, 0]
            geometry.stemTop = [0, height - fallbackRadius * 1.6, 0]
            geometry.bloomRadius = fallbackRadius
        }
        geometry.stemBottom.y = max(geometry.stemBottom.y, 0)
        return geometry
    }

    // MARK: - Vase

    private static func loadVase(manifest: AssetManifest.Model?) async -> VaseAsset {
        guard let loaded = await loadModel(named: "vase") else {
            let (entity, geometry) = ProceduralModels.vase()
            return VaseAsset(template: entity, geometry: geometry, isPlaceholder: true)
        }

        let (container, bounds) = normalize(loaded, toHeight: vaseHeight, centerXZ: true)
        let height = bounds.extents.y
        let outer = max(bounds.extents.x, bounds.extents.z) / 2
        var geometry = VaseGeometry(
            height: height,
            rimHeight: height,
            innerRadius: outer * 0.62,
            outerRadius: outer,
            floorHeight: height * 0.12
        )
        if let manifest, let h = manifest.height ?? manifest.measuredHeight, h > 0 {
            let k = height / h
            if let r = manifest.rimInnerRadius { geometry.innerRadius = r * k }
            if let r = manifest.outerRadiusMax { geometry.outerRadius = r * k }
            if let y = manifest.rimHeight { geometry.rimHeight = min(y * k, height) }
            if let y = manifest.cavityFloorHeight { geometry.floorHeight = y * k }
            // The cavity narrows toward the base. Put the collision floor where the inner wall is still about as
            // wide as the mouth, so a stem resting against the wall can't poke through the narrow foot.
            if let profile = manifest.wallProfile, let rim = manifest.rimInnerRadius,
               let wide = profile.filter({ $0.count >= 2 && $0[1] >= rim - 0.006 }).map({ $0[0] }).min() {
                geometry.floorHeight = max(geometry.floorHeight, wide * k)
            }
        }
        // Keep the mouth usable even if a measurement is off.
        geometry.innerRadius = min(max(geometry.innerRadius, 0.035), geometry.outerRadius - 0.004)
        geometry.floorHeight = min(max(geometry.floorHeight, 0.012), geometry.rimHeight * 0.5)
        prepareForDisplay(container)
        return VaseAsset(template: container, geometry: geometry, isPlaceholder: false)
    }

    // MARK: - Helpers

    /// Loads a model from the compiled `FlowerAssets` package. Models are compiled from USDZ to RealityKit's runtime
    /// format at build time, which loads faster and avoids parsing USD on device.
    private static func loadModel(named name: String) async -> Entity? {
        guard !ProcessInfo.processInfo.arguments.contains("-placeholders") else { return nil }
        do {
            return try await Entity(named: name, in: flowerAssetsBundle)
        } catch {
            print("[FlowerShop] Couldn't load \(name): \(error). Using a stand-in.")
            return nil
        }
    }

    /// Scales `loaded` to `height` meters and moves its bottom to y = 0 in a new container, centering it in X/Z
    /// when asked.
    private static func normalize(_ loaded: Entity, toHeight height: Float, centerXZ: Bool) -> (Entity, BoundingBox) {
        let container = Entity()
        container.addChild(loaded)
        let raw = loaded.visualBounds(relativeTo: container)
        let scale = height / max(raw.extents.y, 0.0001)
        loaded.scale *= scale
        let scaled = loaded.visualBounds(relativeTo: container)
        loaded.position += centerXZ ? SIMD3(-scaled.center.x, -scaled.min.y, -scaled.center.z) : SIMD3(0, -scaled.min.y, 0)
        return (container, loaded.visualBounds(relativeTo: container))
    }

    private static func prepareForDisplay(_ entity: Entity) {
        entity.forEachDescendant(withComponent: ModelComponent.self) { model, _ in
            model.components.set(GroundingShadowComponent(castsShadow: true))
        }
    }
}

// MARK: - Manifest

/// Measurements written by the asset pipeline (`FlowerShop/Resources/manifest.json`).
struct AssetManifest: Decodable {
    struct Model: Decodable {
        var boundsMin: [Float]?
        var boundsMax: [Float]?
        var height: Float?
        var bloomCenter: [Float]?
        var bloomRadius: Float?
        var stemBottom: [Float]?
        var stemTop: [Float]?
        var stemRadius: Float?
        var rimHeight: Float?
        var rimInnerRadius: Float?
        var rimOuterRadius: Float?
        var outerRadiusMax: Float?
        var cavityFloorHeight: Float?
        /// `[height, innerRadius, outerRadius]` samples up the vase wall.
        var wallProfile: [[Float]]?
        var isHollow: Bool?

        var measuredHeight: Float? {
            guard let lo = boundsMin, let hi = boundsMax, lo.count == 3, hi.count == 3 else { return nil }
            return hi[1] - lo[1]
        }

        /// Maps a point measured in the asset's own coordinates into our normalized bounds.
        func mapper(into bounds: BoundingBox) -> ((SIMD3<Float>) -> SIMD3<Float>)? {
            guard let lo = boundsMin.flatMap(SIMD3<Float>.init(array:)),
                  let hi = boundsMax.flatMap(SIMD3<Float>.init(array:))
            else { return nil }
            let size = hi - lo
            guard size.x > 0, size.y > 0, size.z > 0 else { return nil }
            return { p in
                let t = (p - lo) / size
                return bounds.min + t * bounds.extents
            }
        }
    }

    var models: [String: Model]

    static func load() -> AssetManifest? {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(AssetManifest.self, from: data)
    }
}

extension SIMD3 where Scalar == Float {
    init?(array: [Float]) {
        guard array.count == 3 else { return nil }
        self.init(array[0], array[1], array[2])
    }
}

extension Entity {
    /// Visits this entity and every descendant that carries component `T`.
    func forEachDescendant<T: Component>(withComponent type: T.Type, _ body: (Entity, T) -> Void) {
        if let component = components[T.self] { body(self, component) }
        for child in children { child.forEachDescendant(withComponent: type, body) }
    }
}
