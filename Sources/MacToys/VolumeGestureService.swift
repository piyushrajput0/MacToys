import AppKit
import MacToysCore

/// Four fingers up and down on the trackpad to change the volume — the one
/// Windows 11 offers under "Change audio and volume", which macOS has no
/// equivalent for.
final class VolumeGestureService {

    private let reader = MultitouchReader()
    private var recognizer = VolumeGestureRecognizer()
    /// Steps the recogniser has produced but that have not been applied yet.
    /// Nothing is ever discarded — see `handle`.
    private var pendingSteps = 0

    private(set) var isRunning = false
    var lastFailure: String? { reader.lastFailure }

    /// Most steps one frame may apply. Anything above this is carried over to
    /// the next frame rather than dropped, so the volume still travels the full
    /// distance the swipe asked for — just spread over a frame or two.
    private let maximumStepsPerFrame = 4

    @discardableResult
    func start(fingers: Int, sensitivity: Double) -> Bool {
        stop()
        recognizer = VolumeGestureRecognizer(requiredFingers: fingers,
                                             stepDistance: sensitivity)
        reader.onFrame = { [weak self] fingers, x, y in
            self?.handle(fingers: fingers, x: x, y: y)
        }
        isRunning = reader.start()
        return isRunning
    }

    func stop() {
        reader.onFrame = nil
        reader.stop()
        recognizer.reset()
        pendingSteps = 0
        isRunning = false
    }

    func update(fingers: Int, sensitivity: Double) {
        guard isRunning else { return }
        recognizer.requiredFingers = fingers
        recognizer.stepDistance = max(0.005, sensitivity)
    }

    private func handle(fingers: Int, x: Double, y: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        let outcome = recognizer.feed(GestureSample(fingerCount: fingers, x: x, y: y, time: now))

        if case .steps(let steps) = outcome { pendingSteps += steps }
        guard pendingSteps != 0 else { return }

        // Frames arrive about every 12 ms. An earlier version refused to act
        // when they came in faster than a fixed interval and simply returned —
        // but the recogniser had already counted those steps as delivered, so
        // they were lost for good and a quick swipe moved the volume a fraction
        // of the distance it should have. Whatever cannot be applied now is
        // kept for the next frame instead.
        let applied = max(-maximumStepsPerFrame, min(maximumStepsPerFrame, pendingSteps))
        pendingSteps -= applied

        guard let level = AudioController.adjust(steps: applied) else {
            pendingSteps = 0   // no adjustable output; do not queue up forever
            return
        }
        VolumeHUD.show(level: level, muted: AudioController.isMuted)
    }
}
