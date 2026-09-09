import Foundation

/// Raw trackpad finger data, via Apple's private MultitouchSupport framework.
///
/// There is no public API for this. `NSEvent`'s gesture types only arrive for
/// the focused window, and macOS consumes four-finger swipes itself before any
/// app sees them, so a background utility has no supported way to observe them.
/// This is the same route BetterTouchTool, Jitouch and MiddleClick take.
///
/// Being private, it is treated as untrusted:
///
/// * loaded with `dlopen` rather than linked, so a future macOS that drops or
///   renames it makes the volume gesture unavailable instead of stopping the
///   whole app from launching;
/// * only two pieces of data are read — the finger count, which arrives as a
///   plain callback argument, and the first touch's normalised position at a
///   fixed offset. Nothing needs `sizeof(MTTouch)`, so a change to the layout of
///   later fields cannot silently corrupt readings;
/// * positions are range-checked, and the feature switches itself off if they
///   ever stop looking like the 0...1 values they are documented to be.
final class MultitouchReader {

    /// Callback receives (fingerCount, x, y) with coordinates in 0...1.
    var onFrame: ((Int, Double, Double) -> Void)?

    private(set) var isRunning = false
    private(set) var lastFailure: String?

    private var handle: UnsafeMutableRawPointer?
    private var devices: [UnsafeMutableRawPointer] = []
    private var implausibleReadings = 0

    /// Byte offsets of `normalized.position` inside MTTouch. Everything before
    /// it is fixed-width and has been stable for many macOS releases.
    private static let offsetPositionX = 32
    private static let offsetPositionY = 36
    /// Enough consecutive out-of-range values to conclude the layout changed.
    private static let implausibleLimit = 20

    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
    private typealias UnregisterFn = @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias StopFn = @convention(c) (UnsafeMutableRawPointer) -> Void

    /// The C callback cannot capture context, so the live reader is reached
    /// through this. Only one reader is ever created.
    fileprivate static weak var active: MultitouchReader?

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            lastFailure = "MultitouchSupport is not available on this system"
            return false
        }
        self.handle = handle

        guard let createSym = dlsym(handle, "MTDeviceCreateList"),
              let registerSym = dlsym(handle, "MTRegisterContactFrameCallback"),
              let startSym = dlsym(handle, "MTDeviceStart") else {
            lastFailure = "MultitouchSupport changed in this macOS version"
            stop()
            return false
        }

        let createList = unsafeBitCast(createSym, to: CreateListFn.self)
        let register = unsafeBitCast(registerSym, to: RegisterFn.self)
        let startDevice = unsafeBitCast(startSym, to: StartFn.self)

        guard let listRef = createList()?.takeRetainedValue() else {
            lastFailure = "No trackpad found"
            stop()
            return false
        }

        let list = listRef as NSArray
        guard list.count > 0 else {
            lastFailure = "No trackpad found"
            stop()
            return false
        }

        MultitouchReader.active = self
        implausibleReadings = 0

        for entry in list {
            let device = unsafeBitCast(entry as AnyObject, to: UnsafeMutableRawPointer.self)
            register(device, multitouchFrameCallback)
            startDevice(device, 0)
            devices.append(device)
        }

        isRunning = true
        lastFailure = nil
        return true
    }

    func stop() {
        if let handle = handle, !devices.isEmpty {
            let stopSym = dlsym(handle, "MTDeviceStop")
            let unregisterSym = dlsym(handle, "MTUnregisterContactFrameCallback")
            for device in devices {
                if let unregisterSym = unregisterSym {
                    unsafeBitCast(unregisterSym, to: UnregisterFn.self)(device, multitouchFrameCallback)
                }
                if let stopSym = stopSym {
                    unsafeBitCast(stopSym, to: StopFn.self)(device)
                }
            }
        }
        devices.removeAll()
        // The framework handle is deliberately left open: unloading it while
        // its callback thread may still be unwinding risks a crash, and it
        // costs nothing to keep.
        if MultitouchReader.active === self { MultitouchReader.active = nil }
        isRunning = false
    }

    deinit { stop() }

    /// Called from the framework's own thread.
    fileprivate func handleFrame(fingers: Int, touches: UnsafeMutableRawPointer?) {
        guard let onFrame = onFrame else { return }

        var x = 0.0
        var y = 0.0
        if fingers > 0, let touches = touches {
            x = Double(touches.load(fromByteOffset: MultitouchReader.offsetPositionX, as: Float32.self))
            y = Double(touches.load(fromByteOffset: MultitouchReader.offsetPositionY, as: Float32.self))

            let plausible = x >= -0.05 && x <= 1.05 && y >= -0.05 && y <= 1.05 && x.isFinite && y.isFinite
            if plausible {
                implausibleReadings = 0
            } else {
                implausibleReadings += 1
                if implausibleReadings >= MultitouchReader.implausibleLimit {
                    NSLog("[MacToys] trackpad data no longer matches the expected layout; disabling volume gesture")
                    DispatchQueue.main.async { [weak self] in
                        self?.lastFailure = "Trackpad data changed in this macOS version"
                        self?.stop()
                    }
                }
                return
            }
        }

        DispatchQueue.main.async { onFrame(fingers, x, y) }
    }
}

private typealias MTContactCallback =
    @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

private let multitouchFrameCallback: MTContactCallback = { _, touches, fingers, _, _ in
    MultitouchReader.active?.handleFrame(fingers: Int(fingers), touches: touches)
    return 0
}
