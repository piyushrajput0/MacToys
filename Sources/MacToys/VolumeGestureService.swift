import AppKit
import MacToysCore

/// Four fingers up and down on the trackpad to change the volume — the one
/// Windows 11 offers under "Change audio and volume", which macOS has no
/// equivalent for.
final class VolumeGestureService {

    private let reader = MultitouchReader()
    private var recognizer = VolumeGestureRecognizer()
    private var lastStepTime: TimeInterval = 0

    private(set) var isRunning = false
    var lastFailure: String? { reader.lastFailure }

    /// Rate limit, so a fast swipe cannot slam the volume from 0 to 100.
    private let minimumStepInterval: TimeInterval = 0.035

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

        guard case .steps(let steps) = outcome, steps != 0 else { return }
        guard now - lastStepTime >= minimumStepInterval else { return }
        lastStepTime = now

        // Clamp per frame: a single frame should never move more than a couple
        // of notches, however fast the swipe.
        let bounded = max(-2, min(2, steps))
        guard let level = AudioController.adjust(steps: bounded) else { return }
        VolumeHUD.show(level: level, muted: AudioController.isMuted)
    }
}
