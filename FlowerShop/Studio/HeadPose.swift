import ARKit
import QuartzCore
import simd

/// Reads where the person's head is, once, so the shop can be laid out in front of them.
@MainActor
final class HeadPose {
    private let session = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private var isRunning = false

    func start() async {
        guard WorldTrackingProvider.isSupported, !isRunning else { return }
        do {
            try await session.run([worldTracking])
            isRunning = true
        } catch {
            print("[FlowerShop] World tracking unavailable: \(error)")
        }
    }

    /// The current head transform in immersive-space coordinates, waiting briefly for tracking to start.
    func currentTransform(timeout: Duration = .seconds(1.5)) async -> simd_float4x4? {
        guard isRunning else { return nil }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if worldTracking.state == .running,
               let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
               anchor.isTracked {
                return anchor.originFromAnchorTransform
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    func stop() {
        session.stop()
        isRunning = false
    }
}
