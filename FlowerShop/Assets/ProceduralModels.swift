import RealityKit
import UIKit

/// Simple stand-ins used when a Meshy model is missing, so the shop always works.
@MainActor
enum ProceduralModels {

    // MARK: Flowers

    static func flower(_ kind: FlowerKind) -> (Entity, FlowerGeometry) {
        let height = kind.height
        let bloomRadius: Float = switch kind {
        case .sunflower: 0.075
        case .peony: 0.055
        case .lily: 0.06
        case .daisy: 0.045
        case .rose, .tulip: 0.035
        }
        let root = Entity()
        let stemTop = height - bloomRadius * 1.1
        let green = material(UIColor(red: 0.22, green: 0.45, blue: 0.18, alpha: 1), roughness: 0.6)

        let stem = ModelEntity(mesh: .generateCylinder(height: stemTop, radius: 0.0035), materials: [green])
        stem.position.y = stemTop / 2
        root.addChild(stem)

        for (i, y) in [0.38, 0.55].enumerated() {
            let leaf = ModelEntity(mesh: .generateSphere(radius: 1), materials: [green])
            leaf.scale = [0.035, 0.002, 0.012]
            let side: Float = i == 0 ? 1 : -1
            leaf.position = [side * 0.03, Float(y) * height, 0]
            leaf.orientation = simd_quatf(angle: side * 0.5, axis: [0, 0, 1])
            root.addChild(leaf)
        }

        let bloom = Entity()
        bloom.position.y = height - bloomRadius
        root.addChild(bloom)
        let petal = material(kind.bloomColor, roughness: 0.55)

        switch kind {
        case .rose:
            addBlob(to: bloom, radius: bloomRadius, scale: [1, 0.9, 1], material: petal)
            addBlob(to: bloom, radius: bloomRadius * 0.6, scale: [1, 1, 1], offset: [0, bloomRadius * 0.45, 0],
                    material: material(UIColor(red: 0.6, green: 0.04, blue: 0.1, alpha: 1), roughness: 0.5))
        case .tulip:
            addBlob(to: bloom, radius: bloomRadius, scale: [0.85, 1.35, 0.85], material: petal)
        case .peony:
            addBlob(to: bloom, radius: bloomRadius, scale: [1, 0.78, 1], material: petal)
            for i in 0..<6 {
                let a = Float(i) / 6 * 2 * .pi
                addBlob(to: bloom, radius: bloomRadius * 0.45, scale: [1, 0.7, 1],
                        offset: [cos(a) * bloomRadius * 0.7, bloomRadius * 0.15, sin(a) * bloomRadius * 0.7], material: petal)
            }
        case .sunflower:
            let face = Entity()
            face.orientation = simd_quatf(angle: .pi / 3, axis: [1, 0, 0])
            bloom.addChild(face)
            addRing(to: face, count: 18, length: bloomRadius * 0.55, width: 0.016, radius: bloomRadius * 0.6, material: petal)
            let center = ModelEntity(mesh: .generateCylinder(height: 0.012, radius: bloomRadius * 0.48),
                                     materials: [material(UIColor(red: 0.35, green: 0.2, blue: 0.08, alpha: 1), roughness: 0.9)])
            face.addChild(center)
        case .daisy:
            let face = Entity()
            face.orientation = simd_quatf(angle: .pi / 5, axis: [1, 0, 0])
            bloom.addChild(face)
            addRing(to: face, count: 16, length: bloomRadius * 0.6, width: 0.009, radius: bloomRadius * 0.5, material: petal)
            addBlob(to: face, radius: bloomRadius * 0.28, scale: [1, 0.6, 1],
                    material: material(UIColor(red: 0.98, green: 0.78, blue: 0.1, alpha: 1), roughness: 0.8))
        case .lily:
            for i in 0..<6 {
                let a = Float(i) / 6 * 2 * .pi
                let holder = Entity()
                holder.orientation = simd_quatf(angle: a, axis: [0, 1, 0]) * simd_quatf(angle: -0.7, axis: [0, 0, 1])
                bloom.addChild(holder)
                let p = ModelEntity(mesh: .generateSphere(radius: 1), materials: [petal])
                p.scale = [bloomRadius * 0.6, 0.003, 0.016]
                p.position = [bloomRadius * 0.55, 0, 0]
                holder.addChild(p)
            }
            addBlob(to: bloom, radius: 0.008, scale: [1, 2, 1], offset: [0, 0.01, 0],
                    material: material(UIColor(red: 0.85, green: 0.5, blue: 0.2, alpha: 1), roughness: 0.7))
        }

        root.forEachDescendant(withComponent: ModelComponent.self) { model, _ in
            model.components.set(GroundingShadowComponent(castsShadow: true))
        }

        let geometry = FlowerGeometry(
            height: height,
            stemBottom: [0, 0, 0],
            stemTop: [0, stemTop, 0],
            bloomCenter: [0, height - bloomRadius, 0],
            bloomRadius: bloomRadius,
            stemRadius: 0.0065
        )
        return (root, geometry)
    }

    private static func addBlob(to parent: Entity, radius: Float, scale: SIMD3<Float>, offset: SIMD3<Float> = .zero,
                                material: RealityKit.Material) {
        let blob = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
        blob.scale = scale
        blob.position = offset
        parent.addChild(blob)
    }

    private static func addRing(to parent: Entity, count: Int, length: Float, width: Float, radius: Float,
                                material: RealityKit.Material) {
        for i in 0..<count {
            let a = Float(i) / Float(count) * 2 * .pi
            let holder = Entity()
            holder.orientation = simd_quatf(angle: a, axis: [0, 1, 0])
            parent.addChild(holder)
            let p = ModelEntity(mesh: .generateSphere(radius: 1), materials: [material])
            p.scale = [length, 0.002, width]
            p.position = [radius + length * 0.6, 0, 0]
            holder.addChild(p)
        }
    }

    private static func material(_ color: UIColor, roughness: Float) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0)
        return m
    }

    // MARK: Vase

    /// A glazed ceramic vase built by lathing a profile, hollow so stems really go inside.
    static func vase() -> (Entity, VaseGeometry) {
        let rim: Float = 0.25
        let inner: Float = 0.047
        let floor: Float = 0.025
        // (radius, height) traversed bottom-center → outside up → over the lip → inside down → floor center.
        let profile: [SIMD2<Float>] = [
            [0.0, 0.0], [0.050, 0.0], [0.058, 0.004],
            [0.068, 0.04], [0.073, 0.09], [0.069, 0.14], [0.060, 0.19], [0.054, 0.225], [0.056, 0.245],
            [0.0545, rim], [0.050, rim], [inner, rim - 0.006],
            [inner - 0.002, 0.2], [inner + 0.008, 0.13], [inner + 0.011, 0.08], [inner + 0.004, floor + 0.01],
            [inner - 0.012, floor], [0.0, floor],
        ]
        let mesh = lathe(profile: profile, segments: 64)
        var glaze = PhysicallyBasedMaterial()
        glaze.baseColor = .init(tint: UIColor(red: 0.56, green: 0.67, blue: 0.58, alpha: 1))
        glaze.roughness = .init(floatLiteral: 0.32)
        glaze.metallic = .init(floatLiteral: 0)
        glaze.clearcoat = .init(floatLiteral: 1)
        glaze.clearcoatRoughness = .init(floatLiteral: 0.08)
        glaze.faceCulling = .none

        let root = Entity()
        if let mesh {
            let model = ModelEntity(mesh: mesh, materials: [glaze])
            model.components.set(GroundingShadowComponent(castsShadow: true))
            root.addChild(model)
        } else {
            let model = ModelEntity(mesh: .generateCylinder(height: rim, radius: 0.065), materials: [glaze])
            model.position.y = rim / 2
            root.addChild(model)
        }
        return (root, VaseGeometry(height: rim, rimHeight: rim, innerRadius: inner, outerRadius: 0.073, floorHeight: floor))
    }

    private static func lathe(profile: [SIMD2<Float>], segments: Int) -> MeshResource? {
        // Per-profile-point normal in the (r, y) plane: the profile direction rotated clockwise.
        func segmentNormal(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> SIMD2<Float> {
            let d = b - a
            return simd_normalize(SIMD2(d.y, -d.x))
        }
        var normals2D: [SIMD2<Float>] = []
        for i in profile.indices {
            let prev = i > 0 ? segmentNormal(profile[i - 1], profile[i]) : nil
            let next = i < profile.count - 1 ? segmentNormal(profile[i], profile[i + 1]) : nil
            switch (prev, next) {
            case let (p?, n?): normals2D.append(simd_normalize(p + n))
            case let (p?, nil): normals2D.append(p)
            case let (nil, n?): normals2D.append(n)
            default: normals2D.append([0, 1])
            }
        }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        let ring = segments + 1
        for (i, p) in profile.enumerated() {
            let n = normals2D[i]
            for j in 0...segments {
                let theta = Float(j) / Float(segments) * 2 * .pi
                let (s, c) = (sin(theta), cos(theta))
                positions.append([p.x * s, p.y, p.x * c])
                normals.append(simd_normalize([n.x * s, n.y, n.x * c] + [0, 0.00001, 0]))
            }
        }
        var indices: [UInt32] = []
        for i in 0..<(profile.count - 1) {
            for j in 0..<segments {
                let a = UInt32(i * ring + j)
                let b = UInt32(i * ring + j + 1)
                let c = UInt32((i + 1) * ring + j + 1)
                let d = UInt32((i + 1) * ring + j)
                indices += [a, b, c, a, c, d]
            }
        }
        var descriptor = MeshDescriptor(name: "vase")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
