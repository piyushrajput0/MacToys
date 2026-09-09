import Foundation

/// One frame of trackpad data: how many fingers are down, and where the tracked
/// finger is, in the trackpad's normalised 0...1 coordinate space.
public struct GestureSample: Equatable {
    public let fingerCount: Int
    public let x: Double
    public let y: Double
    public let time: Double

    public init(fingerCount: Int, x: Double, y: Double, time: Double) {
        self.fingerCount = fingerCount
        self.x = x
        self.y = y
        self.time = time
    }
}

public enum VolumeGestureOutcome: Equatable {
    case none
    /// Positive raises the volume, negative lowers it.
    case steps(Int)
}

/// Turns a stream of trackpad frames into volume steps.
///
/// Windows 11 offers this as a built-in four-finger gesture ("Change audio and
/// volume"); macOS has no equivalent. The recognition is kept here, free of any
/// framework, so the tricky parts — direction locking, jitter rejection, not
/// firing on a Spaces swipe — can be tested without a trackpad.
public struct VolumeGestureRecognizer {

    /// How many fingers must be down. Four matches Windows.
    public var requiredFingers: Int
    /// Vertical distance, in normalised units, between volume steps. Smaller is
    /// more sensitive.
    public var stepDistance: Double
    /// How much more vertical than horizontal the movement must be before it
    /// counts. A sideways four-finger swipe is macOS switching Spaces, and must
    /// never change the volume.
    public var verticalRatio: Double
    /// Movement below this is treated as the hand resting, not gesturing.
    public var deadZone: Double

    private var anchorX: Double = 0
    private var anchorY: Double = 0
    private var lastY: Double = 0
    private var totalHorizontal: Double = 0
    private var totalVertical: Double = 0
    private var emittedSteps: Int = 0
    private var tracking = false
    /// Set once a gesture is ruled horizontal, so it stays ruled out for its
    /// whole duration rather than flipping to vertical partway through.
    private var rejected = false
    /// The mirror image: once a gesture has proved itself vertical, it stays
    /// vertical. Re-testing the ratio on every frame meant a sideways wobble
    /// halfway through a swipe silently stopped the volume moving, which is a
    /// large part of why long swipes felt like they stalled.
    private var lockedVertical = false

    public init(requiredFingers: Int = 4,
                stepDistance: Double = 0.028,
                verticalRatio: Double = 1.6,
                deadZone: Double = 0.012) {
        self.requiredFingers = requiredFingers
        self.stepDistance = max(0.005, stepDistance)
        self.verticalRatio = verticalRatio
        self.deadZone = deadZone
    }

    public var isTracking: Bool { tracking }

    /// Ends the current gesture. Called when fingers lift or the feature is
    /// switched off.
    public mutating func reset() {
        tracking = false
        rejected = false
        lockedVertical = false
        emittedSteps = 0
        totalHorizontal = 0
        totalVertical = 0
    }

    public mutating func feed(_ sample: GestureSample) -> VolumeGestureOutcome {
        guard sample.fingerCount == requiredFingers else {
            // Any other number of fingers ends the gesture. Lifting one finger
            // mid-swipe must stop the volume moving, not keep tracking the rest.
            reset()
            return .none
        }

        if !tracking {
            tracking = true
            rejected = false
            lockedVertical = false
            anchorX = sample.x
            anchorY = sample.y
            lastY = sample.y
            totalHorizontal = 0
            totalVertical = 0
            emittedSteps = 0
            return .none
        }

        totalHorizontal += abs(sample.x - anchorX)
        totalVertical += abs(sample.y - lastY)
        lastY = sample.y

        let dx = abs(sample.x - anchorX)
        let dy = abs(sample.y - anchorY)

        if rejected { return .none }

        if !lockedVertical {
            // Wait until there is enough movement to have a direction at all.
            guard dy > deadZone || dx > deadZone else { return .none }

            // Predominantly sideways: this is a Spaces swipe, leave it alone
            // for the rest of the gesture.
            if dx > dy * verticalRatio {
                rejected = true
                return .none
            }
            guard dy > dx * verticalRatio else { return .none }
            lockedVertical = true
        }

        // The trackpad's y grows upward, which matches "swipe up = louder".
        let travelled = sample.y - anchorY
        let wanted = Int((travelled / stepDistance).rounded(.towardZero))
        let delta = wanted - emittedSteps
        guard delta != 0 else { return .none }
        emittedSteps = wanted
        return .steps(delta)
    }
}
