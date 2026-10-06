import RealityKit
import SwiftUI
import UIKit

/// Owns the immersive flower shop: the shop panel, the flowers on display, the vase, and the physics that
/// turns a pile of stems into a bouquet.
@MainActor
@Observable
final class BouquetStudio {

    // MARK: Panel-facing state

    private(set) var isStocked = false
    private(set) var usingPlaceholderModels = false
    private(set) var arranged: [FlowerKind: Int] = [:]
    @ObservationIgnored private var hasCelebrated = false
    var onLeave: (() -> Void)?

    static let bouquetSize = 7

    var stemCount: Int { arranged.values.reduce(0, +) }
    var bouquetIsComplete: Bool { stemCount >= Self.bouquetSize }
    var total: Double { arranged.reduce(0) { $0 + $1.key.price * Double($1.value) } }

    // MARK: Scene

    @ObservationIgnored let root = Entity()
    @ObservationIgnored private let assets = AssetLibrary()
    @ObservationIgnored private let headPose = HeadPose()
    @ObservationIgnored private let panel = Entity()
    /// The SwiftUI shop panel, provided by the RealityView's attachments.
    @ObservationIgnored private var panelView: Entity?
    @ObservationIgnored private let floor = Entity()
    @ObservationIgnored private var vase: Entity?
    @ObservationIgnored private var celebrationEmitter: Entity?
    @ObservationIgnored private var landingEmitter: Entity?
    @ObservationIgnored private var landingSound: AudioFileResource?
    @ObservationIgnored private var bouquetSound: AudioFileResource?
    @ObservationIgnored private var subscriptions: [EventSubscription] = []
    @ObservationIgnored private var slotFrames: [Transform] = []
    @ObservationIgnored private var slotScales: [FlowerKind: Float] = [:]
    @ObservationIgnored private var started = false
    @ObservationIgnored private var loading: Task<Void, Never>?

    /// Layout relative to the head at launch (meters; -Z is forward).
    private enum Layout {
        // The panel sits a little left of center and the vase off to the right, so a growing bouquet never
        // blocks the shop.
        static let panelPosition: SIMD3<Float> = [-0.12, -0.04, -1.35]
        static let panelYaw: Float = atan2(0.12, 1.35)
        static let panelWidth: Float = 1.1
        static var vasePosition: SIMD3<Float> {
            ProcessInfo.processInfo.arguments.contains("-vaseInFront") ? [0, -0.42, -0.75] : [0.46, -0.52, -0.66]
        }
        static let fallbackHeadHeight: Float = 1.45
        static let maxLooseFlowers = 36
    }

    // MARK: Setup

    /// Call from the RealityView make closure.
    func install(in content: RealityViewContent, panelView: Entity?) {
        BouquetSystem.studio = self
        root.name = "Workspace"
        root.components.set(PhysicsSimulationComponent())
        content.add(root)

        // An invisible floor so stems that miss the vase land on the real floor instead of falling forever.
        floor.name = "Floor"
        let floorShape = ShapeResource.generateBox(size: [8, 0.02, 8])
        floor.components.set(CollisionComponent(shapes: [floorShape]))
        floor.components.set(PhysicsBodyComponent(shapes: [floorShape], mass: 0,
                                                  material: .generate(staticFriction: 0.9, dynamicFriction: 0.8, restitution: 0.05),
                                                  mode: .static))
        root.addChild(floor)

        panel.name = "ShopPanel"
        root.addChild(panel)
        if let panelView {
            self.panelView = panelView
            panel.addChild(panelView)
        }

        subscriptions.append(content.subscribe(to: ManipulationEvents.WillBegin.self) { [weak self] event in
            MainActor.assumeIsolated { self?.manipulationWillBegin(event.entity) }
        })
        subscriptions.append(content.subscribe(to: ManipulationEvents.WillEnd.self) { [weak self] event in
            MainActor.assumeIsolated { self?.manipulationDidEnd(event.entity) }
        })
        subscriptions.append(content.subscribe(to: AccessibilityEvents.Activate.self) { [weak self] event in
            MainActor.assumeIsolated { self?.accessibilityActivated(event.entity) }
        })
    }

    /// Loads models and sounds. Call from the RealityView make closure, before `install(in:panelView:)`.
    /// Safe to call more than once; later callers wait for the same load.
    func loadAssets() async {
        if loading == nil {
            loading = Task {
                await assets.loadAll()
                landingSound = try? await AudioFileResource(contentsOf: Self.soundURL("vase_tink"))
                bouquetSound = try? await AudioFileResource(contentsOf: Self.soundURL("bouquet_chime"))
            }
        }
        await loading?.value
    }

    /// Lays out the shop. Call once, from a `.task`.
    func start() async {
        guard !started else { return }
        started = true

        await headPose.start()
        await loadAssets()
        await placeWorkspace(animated: false)
        panel.position = Layout.panelPosition
        panel.orientation = simd_quatf(angle: Layout.panelYaw, axis: [0, 1, 0])

        let pointsToMeters = await measurePanel()

        usingPlaceholderModels = FlowerKind.allCases.contains { assets.flowers[$0]?.isPlaceholder ?? true }
            || (assets.vase?.isPlaceholder ?? true)

        buildVase()
        buildShelf(pointsToMeters: pointsToMeters)
        isStocked = true
        print("[FlowerShop] Shop stocked (placeholder models: \(usingPlaceholderModels)).")

        if ProcessInfo.processInfo.arguments.contains("-demoBouquet") {
            await runDemo()
        }
    }

    func stop() {
        headPose.stop()
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
    }

    /// Places the workspace at the person's head, facing their forward direction (yaw only, so gravity stays down).
    private func placeWorkspace(animated: Bool) async {
        var position: SIMD3<Float> = [0, Layout.fallbackHeadHeight, 0]
        var yaw: Float = 0
        // The simulator reports the device at the floor origin; only trust a plausible eye height.
        if let head = await headPose.currentTransform(), head.columns.3.y > 0.6 {
            position = head.columns.3.xyz
            let forward = -head.columns.2.xyz
            if simd_length(SIMD2(forward.x, forward.z)) > 0.01 {
                yaw = atan2(-forward.x, -forward.z)
            }
        }
        let target = Transform(scale: .one, rotation: simd_quatf(angle: yaw, axis: [0, 1, 0]), translation: position)
        if animated {
            root.tween(to: target, duration: 0.6)
        } else {
            root.transform = target
        }
        floor.position = [0, -position.y - 0.01, 0]
    }

    /// Scales the panel to its intended physical width and returns the meters-per-point factor for layout.
    private func measurePanel() async -> Float {
        var width: Float = 0
        for _ in 0..<60 {
            width = panelView?.components[ViewAttachmentComponent.self]?.bounds.extents.x ?? 0
            if width > 0 { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let nativeMetersPerPoint = width > 0 ? width / Float(PanelLayout.size.width) : 1 / 1360
        let scale = Layout.panelWidth / (nativeMetersPerPoint * Float(PanelLayout.size.width))
        panel.scale = SIMD3(repeating: scale)
        return nativeMetersPerPoint * scale
    }

    // MARK: Vase

    private func buildVase() {
        guard let asset = assets.vase else { return }
        let g = asset.geometry
        let vase = Entity()
        vase.name = "Vase"
        vase.addChild(asset.template.clone(recursive: true))
        vase.position = Layout.vasePosition
        vase.components.set(VaseComponent(geometry: g))

        // A hollow tube of boxes plus a floor: stems can only enter through the mouth.
        var shapes: [ShapeResource] = []
        let segments = 20
        let wall = max(g.outerRadius - g.innerRadius, 0.016)
        let wallHeight = g.rimHeight
        let chord = 2 * (g.innerRadius + wall) * tan(.pi / Float(segments)) * 1.08
        for i in 0..<segments {
            let angle = Float(i) / Float(segments) * 2 * .pi
            let rotation = simd_quatf(angle: angle, axis: [0, 1, 0])
            let center = rotation.act([0, wallHeight / 2, g.innerRadius + wall / 2])
            shapes.append(ShapeResource.generateBox(size: [chord, wallHeight, wall]).offsetBy(rotation: rotation, translation: center))
        }
        let floorThickness = max(g.floorHeight, 0.015)
        shapes.append(ShapeResource.generateBox(size: [g.innerRadius * 2.2, floorThickness, g.innerRadius * 2.2])
            .offsetBy(translation: [0, g.floorHeight - floorThickness / 2, 0]))

        makeManipulable(vase, shapes: shapes, inertia: .medium)
        var body = PhysicsBodyComponent(shapes: shapes, mass: 1.2,
                                        material: .generate(staticFriction: 0.8, dynamicFriction: 0.6, restitution: 0.02),
                                        mode: .kinematic)
        body.isAffectedByGravity = false
        vase.components.set(body)

        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Vase"
        accessibility.value = "Empty"
        vase.components.set(accessibility)

        let landing = Self.makeSparkleEmitter(count: 26, speed: 0.12, size: 0.005, colors: (.white, UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1)))
        landing.position = [0, g.rimHeight + 0.01, 0]
        vase.addChild(landing)
        landingEmitter = landing

        let celebration = Self.makeSparkleEmitter(count: 160, speed: 0.45, size: 0.008, colors: (UIColor(red: 1, green: 0.75, blue: 0.85, alpha: 1), UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1)))
        celebration.position = [0, g.rimHeight + 0.18, 0]
        vase.addChild(celebration)
        celebrationEmitter = celebration

        vase.components.set(SpatialAudioComponent(gain: -8))
        root.addChild(vase)
        self.vase = vase

        // Grow in.
        vase.scale = .init(repeating: 0.01)
        vase.tween(to: Transform(scale: .one, rotation: vase.orientation, translation: vase.position),
                   duration: 0.6, easing: .easeOutBack)
    }

    // MARK: Shelf

    private func buildShelf(pointsToMeters: Float) {
        slotFrames = FlowerKind.allCases.indices.map { index in
            let center = PanelLayout.flowerCenter(index)
            let x = Float(center.x - PanelLayout.size.width / 2) * pointsToMeters
            let y = Float(PanelLayout.size.height / 2 - center.y) * pointsToMeters
            let rotation = simd_quatf(angle: Layout.panelYaw, axis: [0, 1, 0])
            return Transform(rotation: rotation, translation: Layout.panelPosition + rotation.act([x, y, 0.07]))
        }
        let displayHeight = Float(PanelLayout.flowerAreaHeight) * pointsToMeters
        for (index, kind) in FlowerKind.allCases.enumerated() {
            if let asset = assets.flowers[kind] {
                slotScales[kind] = min(displayHeight / asset.geometry.height, 0.7)
            }
            stockShelf(slot: index, kind: kind, delay: Double(index) * 0.08)
        }
    }

    private func stockShelf(slot: Int, kind: FlowerKind, delay: Double = 0) {
        guard let asset = assets.flowers[kind], let scale = slotScales[kind] else { return }
        let g = asset.geometry
        let flower = makeFlower(kind: kind, asset: asset)
        let spinner = flower.children[0]
        let model = spinner.children[0]

        // Center the scaled flower vertically on its card.
        let top = g.bloomRadius * scale
        let bottom = -g.bloomCenter.y * scale
        var frame = slotFrames[slot]
        frame.translation.y -= (top + bottom) / 2
        flower.transform = frame

        model.transform = Transform(scale: .init(repeating: scale), translation: -g.bloomCenter * scale)
        spinner.orientation = simd_quatf(angle: Float.random(in: 0..<(2 * .pi)), axis: [0, 1, 0])
        spinner.components.set(ShelfSpinComponent(speed: 0.35))

        var state = FlowerComponent(kind: kind, phase: .shelf, geometry: g)
        state.slot = slot
        flower.components.set(state)
        makeManipulable(flower, shapes: Self.flowerShapes(g, scale: scale, forDisplay: true), inertia: .low)

        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(stringLiteral: kind.displayName)
        accessibility.value = LocalizedStringResource(stringLiteral: "\(kind.price.asPrice) a stem. Pull it out, or activate to add one to the vase.")
        accessibility.traits = [.button]
        accessibility.systemActions = [.activate]
        flower.components.set(accessibility)

        root.addChild(flower)

        // Grow in.
        spinner.scale = .init(repeating: 0.01)
        spinner.tween(to: Transform(scale: .one, rotation: spinner.orientation, translation: .zero),
                      duration: 0.5, delay: Float(delay), easing: .easeOutBack, animatesRotation: false)
    }

    /// root (bloom center) → spinner → model (offset so the bloom sits on the root's origin).
    private func makeFlower(kind: FlowerKind, asset: FlowerAsset) -> Entity {
        let flower = Entity()
        flower.name = kind.displayName
        let spinner = Entity()
        spinner.name = "Spinner"
        flower.addChild(spinner)
        let model = asset.template.clone(recursive: true)
        model.position = -asset.geometry.bloomCenter
        spinner.addChild(model)
        return flower
    }

    private func makeManipulable(_ entity: Entity, shapes: [ShapeResource], inertia: ManipulationComponent.Dynamics.Inertia) {
        ManipulationComponent.configureEntity(
            entity,
            hoverEffect: .spotlight(.init(color: .white, strength: 0.7)),
            allowedInputTypes: .all,
            collisionShapes: shapes
        )
        var manipulation = entity.components[ManipulationComponent.self] ?? ManipulationComponent()
        manipulation.releaseBehavior = .stay
        manipulation.dynamics.scalingBehavior = .none
        manipulation.dynamics.inertia = inertia
        entity.components.set(manipulation)
    }

    /// Collision shapes in the flower root's space: a sphere for the bloom and a capsule along the stem.
    private static func flowerShapes(_ g: FlowerGeometry, scale: Float, forDisplay: Bool) -> [ShapeResource] {
        let bottom = (g.stemBottom - g.bloomCenter) * scale
        let top = (g.stemTop - g.bloomCenter) * scale
        let axis = top - bottom
        let length = max(simd_length(axis), 0.01)
        let radius = forDisplay ? max(g.stemRadius * scale, 0.012) : g.stemRadius
        let stem = ShapeResource.generateCapsule(height: length, radius: radius)
            .offsetBy(rotation: simd_quatf(from: [0, 1, 0], to: axis / length), translation: (top + bottom) / 2)
        // On the shelf the whole bloom is a target; in the vase a smaller core lets blooms nestle together.
        let bloomRadius = forDisplay ? g.bloomRadius * scale : min(max(g.bloomRadius * 0.55, 0.025), 0.065)
        let bloom = ShapeResource.generateSphere(radius: bloomRadius)
        return [bloom, stem]
    }

    // MARK: Manipulation

    private func manipulationWillBegin(_ entity: Entity) {
        entity.cancelTween()
        if var flower = entity.components[FlowerComponent.self] {
            let previous = flower.phase
            flower.phase = .held
            flower.grabbedFromShelf = previous == .shelf
            flower.grabStartTime = CACurrentMediaTime()
            flower.grabStartPosition = entity.position(relativeTo: nil)
            flower.vaseOffset = nil
            entity.components.set(flower)

            if previous == .shelf {
                popOffShelf(entity)
            } else {
                setBody(entity, dynamic: false)
            }
            if previous == .arranged { removeFromBouquet(flower.kind) }
        } else if entity.components.has(VaseComponent.self) {
            // Anything still tumbling around inside freezes where it is so it travels with the vase.
            for flower in looseFlowers() where flower.components[FlowerComponent.self]?.phase == .settling {
                flowerCameToRest(flower)
            }
        }
    }

    private func manipulationDidEnd(_ entity: Entity) {
        if let flower = entity.components[FlowerComponent.self], flower.phase == .held {
            let heldFor = CACurrentMediaTime() - flower.grabStartTime
            let moved = simd_distance(entity.position(relativeTo: nil), flower.grabStartPosition)
            if flower.grabbedFromShelf && heldFor < 0.35 && moved < 0.03 {
                // A quick pinch on the shelf: send the stem to the vase for them.
                autoPlace(entity)
            } else if let pose = insertionPose(for: entity) {
                drop(entity, at: pose, snapDuration: 0.12)
            } else {
                setPhase(entity, .floating)
                setBody(entity, dynamic: false)
            }
        } else if entity.components.has(VaseComponent.self) {
            standVaseUpright()
        }
    }

    private func accessibilityActivated(_ entity: Entity) {
        guard var flower = entity.components[FlowerComponent.self], flower.phase == .shelf else { return }
        flower.phase = .held
        flower.grabbedFromShelf = true
        entity.components.set(flower)
        popOffShelf(entity)
        autoPlace(entity)
    }

    /// Adds a stem of `kind` to the vase without pulling it by hand (the card's "+" button).
    func quickAdd(_ kind: FlowerKind) {
        guard let flower = root.children.first(where: {
            $0.components[FlowerComponent.self]?.kind == kind && $0.components[FlowerComponent.self]?.phase == .shelf
        }) else { return }
        accessibilityActivated(flower)
    }

    /// The flower on display becomes a full-size stem in the person's hand, and the shelf restocks.
    private func popOffShelf(_ entity: Entity) {
        guard var flower = entity.components[FlowerComponent.self] else { return }
        let spinner = entity.children[0]
        let model = spinner.children[0]
        spinner.components.remove(ShelfSpinComponent.self)

        let g = flower.geometry
        spinner.tween(to: Transform(scale: .one, rotation: spinner.orientation, translation: .zero), duration: 0.2)
        model.tween(to: Transform(scale: .one, rotation: model.orientation, translation: -g.bloomCenter),
                    duration: 0.35, easing: .easeOutBack)

        let shapes = Self.flowerShapes(g, scale: 1, forDisplay: false)
        entity.components.set(CollisionComponent(shapes: shapes))
        var body = PhysicsBodyComponent(shapes: shapes, mass: 0.035,
                                        material: .generate(staticFriction: 0.7, dynamicFriction: 0.5, restitution: 0.02),
                                        mode: .kinematic)
        body.isAffectedByGravity = false
        body.linearDamping = 0.6
        body.angularDamping = 3
        entity.components.set(body)
        entity.components.set(PhysicsMotionComponent())

        if var accessibility = entity.components[AccessibilityComponent.self] {
            accessibility.value = LocalizedStringResource(stringLiteral: "Loose stem")
            accessibility.systemActions = []
            entity.components.set(accessibility)
        }

        if let slot = flower.slot {
            flower.slot = nil
            entity.components.set(flower)
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                stockShelf(slot: slot, kind: flower.kind)
            }
        }
        trimLooseFlowers()
    }

    // MARK: Vase physics

    /// If a released stem is over or in the vase mouth, returns a nearby pose (in workspace space) from which it can
    /// slide in without starting inside the vase wall. Returns nil when the stem isn't aimed at the vase.
    private func insertionPose(for entity: Entity) -> Transform? {
        guard let vase, let flower = entity.components[FlowerComponent.self],
              let g = vase.components[VaseComponent.self]?.geometry else { return nil }

        let vaseToRoot = vase.transformMatrix(relativeTo: root)
        let flowerInVase = vaseToRoot.inverse * entity.transformMatrix(relativeTo: root)
        let bottom = (flowerInVase * SIMD4(flower.stemBottomLocal, 1)).xyz
        let top = (flowerInVase * SIMD4(flower.stemTopLocal, 1)).xyz
        let axis = simd_normalize(top - bottom)
        guard axis.y > 0.4 else { return nil } // Upside down or sideways: not going in a vase.

        let radial = simd_length(SIMD2(bottom.x, bottom.z))
        let inside = bottom.y <= g.rimHeight && bottom.y >= g.floorHeight - 0.04 && radial < g.innerRadius + 0.02
        let above = bottom.y > g.rimHeight && bottom.y < g.rimHeight + 0.25 && radial < g.innerRadius + 0.06
        guard inside || above else { return nil }

        let leanLimit: Float = 0.5 // ~28°
        var lean = min(acos(min(axis.y, 1)), leanLimit)
        var direction = SIMD2(axis.x, axis.z)
        direction = simd_length(direction) > 0.001 ? simd_normalize(direction) : SIMD2(1, 0)

        let usable = g.innerRadius - flower.geometry.stemRadius - 0.004
        let bottomY = max(bottom.y, g.floorHeight + 0.01)
        let depth = max(g.rimHeight - bottomY, 0)
        if depth > 0.001 { lean = min(lean, atan(2 * usable / depth)) }
        let span = depth * tan(lean)

        var bottomXZ = SIMD2(bottom.x, bottom.z)
        if simd_length(bottomXZ) > usable { bottomXZ = simd_normalize(bottomXZ) * usable }
        if simd_length(bottomXZ + direction * span) > usable { bottomXZ = -direction * span / 2 }

        let targetAxis = SIMD3(direction.x * sin(lean), cos(lean), direction.y * sin(lean))
        let currentRotation = simd_quatf(flowerInVase)
        let rotation = simd_quatf(from: axis, to: targetAxis) * currentRotation
        let targetBottom = SIMD3(bottomXZ.x, bottomY, bottomXZ.y)
        let position = targetBottom - rotation.act(flower.stemBottomLocal)

        let inVase = Transform(scale: .one, rotation: rotation, translation: position)
        return Transform(matrix: vaseToRoot * inVase.matrix)
    }

    /// Sends a stem from wherever it is to just above the vase mouth, leaning a little, then lets it fall in.
    private func autoPlace(_ entity: Entity) {
        guard let vase, var flower = entity.components[FlowerComponent.self],
              let g = vase.components[VaseComponent.self]?.geometry else { return }
        flower.phase = .placing
        entity.components.set(flower)
        setBody(entity, dynamic: false)

        let lean = Float.random(in: 0.18...0.42)
        let heading = Float.random(in: 0..<(2 * .pi))
        let direction = SIMD2(cos(heading), sin(heading))
        let targetAxis = SIMD3(direction.x * sin(lean), cos(lean), direction.y * sin(lean))
        // Blooms face +Z in the model; turn each one to face outward over the rim, like a florist would.
        let facing = atan2(direction.x, direction.y) + Float.random(in: -0.5...0.5)
        let spin = simd_quatf(angle: facing, axis: flower.geometry.stemAxis)
        let rotation = simd_quatf(from: flower.geometry.stemAxis, to: targetAxis) * spin
        let offset = SIMD2(-direction.x, -direction.y) * min(0.012, g.innerRadius * 0.3)
        let bottom = SIMD3(offset.x, g.rimHeight + 0.03, offset.y)
        let inVase = Transform(scale: .one, rotation: rotation, translation: bottom - rotation.act(flower.stemBottomLocal))
        let target = Transform(matrix: vase.transformMatrix(relativeTo: root) * inVase.matrix)

        drop(entity, at: target, snapDuration: 0.75)
    }

    private func drop(_ entity: Entity, at pose: Transform, snapDuration: TimeInterval) {
        setPhase(entity, .placing)
        setBody(entity, dynamic: false)
        entity.tween(to: pose, duration: Float(snapDuration)) { [weak self] entity in
            guard var flower = entity.components[FlowerComponent.self], flower.phase == .placing else { return }
            flower.phase = .settling
            flower.settleTime = 0
            flower.calmTime = 0
            entity.components.set(flower)
            self?.setBody(entity, dynamic: true)
        }
    }

    /// Called by `BouquetSystem` when a dropped stem stops moving (or takes too long).
    func flowerCameToRest(_ entity: Entity) {
        guard let vase, var flower = entity.components[FlowerComponent.self], flower.phase == .settling,
              let g = vase.components[VaseComponent.self]?.geometry else { return }

        let vaseWorld = vase.transformMatrix(relativeTo: nil)
        let flowerWorld = entity.transformMatrix(relativeTo: nil)
        let bottom = (vaseWorld.inverse * flowerWorld * SIMD4(flower.stemBottomLocal, 1)).xyz
        let radial = simd_length(SIMD2(bottom.x, bottom.z))
        let inVase = bottom.y < g.rimHeight + 0.01 && bottom.y > g.floorHeight - 0.05 && radial < g.innerRadius + 0.025

        setBody(entity, dynamic: false)
        if inVase {
            flower.phase = .arranged
            flower.vaseOffset = vaseWorld.inverse * flowerWorld
            entity.components.set(flower)
            addToBouquet(flower.kind)
        } else {
            flower.phase = .floating
            entity.components.set(flower)
        }
    }

    func discard(_ entity: Entity) {
        entity.removeFromParent()
    }

    private func standVaseUpright() {
        guard let vase else { return }
        let forward = vase.orientation.act([0, 0, 1])
        let yaw = atan2(forward.x, forward.z)
        let upright = simd_quatf(angle: yaw, axis: [0, 1, 0])
        guard abs(simd_dot(vase.orientation.act([0, 1, 0]), [0, 1, 0])) < 0.9995 else { return }
        vase.tween(to: Transform(scale: .one, rotation: upright, translation: vase.position), duration: 0.45)
    }

    private func setBody(_ entity: Entity, dynamic: Bool) {
        guard var body = entity.components[PhysicsBodyComponent.self] else { return }
        body.mode = dynamic ? .dynamic : .kinematic
        body.isAffectedByGravity = dynamic
        body.isContinuousCollisionDetectionEnabled = dynamic
        entity.components.set(body)
        entity.components.set(PhysicsMotionComponent())
    }

    private func setPhase(_ entity: Entity, _ phase: FlowerComponent.Phase) {
        guard var flower = entity.components[FlowerComponent.self] else { return }
        flower.phase = phase
        entity.components.set(flower)
    }

    // MARK: Bouquet

    private func addToBouquet(_ kind: FlowerKind) {
        arranged[kind, default: 0] += 1
        burst(landingEmitter)
        if let landingSound { vase?.playAudio(landingSound) }
        updateVaseAccessibility()
        if bouquetIsComplete && !hasCelebrated {
            hasCelebrated = true
            burst(celebrationEmitter)
            if let bouquetSound { vase?.playAudio(bouquetSound) }
            AccessibilityNotification.Announcement("Your bouquet is ready").post()
        }
    }

    private func removeFromBouquet(_ kind: FlowerKind) {
        arranged[kind] = max((arranged[kind] ?? 0) - 1, 0)
        if arranged[kind] == 0 { arranged[kind] = nil }
        if !bouquetIsComplete { hasCelebrated = false }
        updateVaseAccessibility()
    }

    private func updateVaseAccessibility() {
        guard let vase, var accessibility = vase.components[AccessibilityComponent.self] else { return }
        accessibility.value = LocalizedStringResource(stringLiteral: stemCount == 0 ? "Empty" : "\(stemCount) stems")
        vase.components.set(accessibility)
    }

    /// Clears every stem out of the room and the vase.
    func startNewBouquet() {
        for flower in looseFlowers() {
            flower.components.remove(ManipulationComponent.self)
            flower.components.remove(InputTargetComponent.self)
            if var body = flower.components[PhysicsBodyComponent.self] {
                body.mode = .kinematic
                flower.components.set(body)
            }
            setPhase(flower, .floating)
            var shrunk = flower.transform
            shrunk.scale = .init(repeating: 0.01)
            flower.tween(to: shrunk, duration: 0.3, easing: .easeIn) { $0.removeFromParent() }
        }
        arranged = [:]
        hasCelebrated = false
        updateVaseAccessibility()
    }

    /// Brings the whole shop back in front of the person.
    func recenter() {
        Task { await placeWorkspace(animated: true) }
    }

    private func looseFlowers() -> [Entity] {
        root.children.filter {
            guard let phase = $0.components[FlowerComponent.self]?.phase else { return false }
            return phase != .shelf
        }
    }

    /// Keeps the scene light: once there are too many stems lying around, the oldest floating one fades away.
    private func trimLooseFlowers() {
        let loose = looseFlowers()
        guard loose.count > Layout.maxLooseFlowers,
              let oldest = loose.first(where: { $0.components[FlowerComponent.self]?.phase == .floating }) else { return }
        oldest.removeFromParent()
    }

    // MARK: Effects

    private static func soundURL(_ name: String) -> URL {
        Bundle.main.url(forResource: name, withExtension: "wav") ?? URL(fileURLWithPath: "/dev/null")
    }

    private func burst(_ emitter: Entity?) {
        guard let emitter, var particles = emitter.components[ParticleEmitterComponent.self] else { return }
        particles.burst()
        emitter.components.set(particles)
    }

    private static func makeSparkleEmitter(count: Int, speed: Float, size: Float, colors: (UIColor, UIColor)) -> Entity {
        var particles = ParticleEmitterComponent()
        particles.emitterShape = .sphere
        particles.emitterShapeSize = [0.04, 0.02, 0.04]
        particles.speed = speed
        particles.speedVariation = speed * 0.5
        particles.isEmitting = false
        particles.burstCount = count
        particles.burstCountVariation = count / 4
        particles.mainEmitter.birthRate = 0
        particles.mainEmitter.lifeSpan = 1.2
        particles.mainEmitter.lifeSpanVariation = 0.4
        particles.mainEmitter.size = size
        particles.mainEmitter.sizeVariation = size * 0.4
        particles.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.2
        particles.mainEmitter.acceleration = [0, -0.25, 0]
        particles.mainEmitter.dampingFactor = 1.5
        particles.mainEmitter.spreadingAngle = .pi
        particles.mainEmitter.opacityCurve = .quickFadeInOut
        particles.mainEmitter.blendMode = .additive
        particles.mainEmitter.color = .evolving(start: .single(colors.0), end: .single(colors.1))
        let entity = Entity()
        entity.name = "Sparkles"
        entity.components.set(particles)
        return entity
    }

    // MARK: Demo (simulator)

    /// `-demoBouquet` launch argument: drops a handful of stems into the vase so physics can be checked without hands.
    private func runDemo() async {
        try? await Task.sleep(for: .seconds(1.2))
        let order: [FlowerKind] = [.rose, .peony, .tulip, .lily, .sunflower, .daisy, .rose, .tulip]
        for kind in order {
            quickAdd(kind)
            try? await Task.sleep(for: .seconds(1.1))
        }
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
