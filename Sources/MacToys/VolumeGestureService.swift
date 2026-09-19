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

    /// When the trackpad last delivered anything. Frames only arrive while the
    /// pad is being touched, so this cannot prove the subscription is alive —
    /// but a value from before the last sleep is strong evidence it is not.
    private(set) var lastFrameTime: Date?

    private var wakeObserver: NSObjectProtocol?
    private var currentFingers = 4
    private var currentSensitivity = 0.028

    /// Most steps one frame may apply. Anything above this is carried over to
    /// the next frame rather than dropped, so the volume still travels the full
    /// distance the swipe asked for — just spread over a frame or two.
    private let maximumStepsPerFrame = 4

    @discardableResult
    func start(fingers: Int, sensitivity: Double) -> Bool {
        stop()
        currentFingers = fingers
        currentSensitivity = sensitivity
        recognizer = VolumeGestureRecognizer(requiredFingers: fingers,
                                             stepDistance: sensitivity)
        observeWake()
        reader.onFrame = { [weak self] fingers, x, y in
            self?.lastFrameTime = Date()
            self?.handle(fingers: fingers, x: x, y: y)
        }
        isRunning = reader.start()
        return isRunning
    }

    /// The multitouch subscription does not survive the machine sleeping: the
    /// callback is simply never invoked again, with no error and no indication
    /// that anything is wrong. Re-registering on wake is the fix, and is why
    /// the gesture used to work until the first time the lid was closed.
    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            // A moment for the trackpad to be re-enumerated before re-attaching.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard self.isRunning else { return }
                self.reattach()
            }
        }
    }

    /// Tears the subscription down and builds it again, preserving settings.
    private func reattach() {
        reader.stop()
        reader.onFrame = { [weak self] fingers, x, y in
            self?.lastFrameTime = Date()
            self?.handle(fingers: fingers, x: x, y: y)
        }
        recognizer.reset()
        pendingSteps = 0
        if !reader.start() {
            NSLog("[MacToys] could not re-attach to the trackpad after wake: \(reader.lastFailure ?? "unknown")")
            isRunning = false
        }
    }

    func stop() {
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
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
