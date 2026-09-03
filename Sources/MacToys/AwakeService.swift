import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac awake, the way PowerToys Awake does on Windows.
///
/// Uses an IOKit power assertion rather than shelling out to `caffeinate`, so
/// the assertion dies with the app and cannot be orphaned into a process that
/// keeps a laptop awake in a bag.
final class AwakeService {

    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?

    private(set) var isActive = false
    private(set) var expiry: Date?

    /// - Parameter keepDisplayOn: when true the screen stays lit as well as the
    ///   machine staying awake; when false only sleep is prevented, which is
    ///   what you want for a long download.
    /// - Parameter duration: nil means indefinitely.
    @discardableResult
    func activate(keepDisplayOn: Bool, duration: TimeInterval? = nil) -> Bool {
        deactivate()

        let type = keepDisplayOn
            ? kIOPMAssertionTypeNoDisplaySleep as CFString
            : kIOPMAssertionTypeNoIdleSleep as CFString

        let reason = "MacToys: Keep Awake" as CFString
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id)

        guard result == kIOReturnSuccess else {
            NSLog("[MacToys] power assertion failed: \(result)")
            return false
        }

        assertionID = id
        isActive = true

        if let duration = duration {
            expiry = Date().addingTimeInterval(duration)
            timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.deactivate()
                NotificationCenter.default.post(name: AwakeService.didChange, object: nil)
            }
        } else {
            expiry = nil
        }
        NotificationCenter.default.post(name: AwakeService.didChange, object: nil)
        return true
    }

    func deactivate() {
        timer?.invalidate()
        timer = nil
        expiry = nil
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }

    deinit { deactivate() }

    static let didChange = Notification.Name("MacToysAwakeDidChange")
}
