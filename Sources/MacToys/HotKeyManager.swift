import AppKit
import Carbon.HIToolbox
import MacToysCore

/// Registers system-wide shortcuts through Carbon's `RegisterEventHotKey`.
///
/// Carbon is the only public API that delivers a hotkey to a background app
/// without Accessibility permission, which is why the clipboard picker, the snip
/// tool and window snapping all work the moment the app launches. The modern
/// `NSEvent.addGlobalMonitor` alternative cannot swallow the keystroke and does
/// require Accessibility, so it is the wrong tool here.
final class HotKeyManager {

    private struct Registration {
        let ref: EventHotKeyRef
        let action: () -> Void
        let spec: HotKeySpec
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x4D544B59   // 'MTKY'

    /// Names of shortcuts that could not be claimed because something else owns
    /// them. Surfaced in the menu so the user is not left wondering.
    private(set) var conflicts: [String] = []

    func start() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return status }
            manager.fire(id: hotKeyID.id)
            return noErr
        }, 1, &spec, context, &eventHandler)
    }

    private func fire(id: UInt32) {
        registrations[id]?.action()
    }

    /// Claims a shortcut. Returns false when the combination is already taken by
    /// the system or another app, in which case the caller should keep running
    /// without that one binding rather than failing to launch.
    @discardableResult
    func register(_ spec: HotKeySpec, name: String, action: @escaping () -> Void) -> Bool {
        start()
        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(UInt32(spec.keyCode),
                                         HotKeyManager.carbonModifiers(spec.mods),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)

        guard status == noErr, let ref = ref else {
            conflicts.append("\(name) (\(spec))")
            NSLog("[MacToys] could not register \(name) = \(spec): OSStatus \(status)")
            return false
        }
        registrations[id] = Registration(ref: ref, action: action, spec: spec)
        return true
    }

    func unregisterAll() {
        for (_, reg) in registrations { UnregisterEventHotKey(reg.ref) }
        registrations.removeAll()
        conflicts.removeAll()
    }

    /// Translates our modifier set into Carbon's bitmask.
    static func carbonModifiers(_ mods: Mods) -> UInt32 {
        var carbon: UInt32 = 0
        if mods.contains(.command) { carbon |= UInt32(cmdKey) }
        if mods.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if mods.contains(.option)  { carbon |= UInt32(optionKey) }
        if mods.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }
}
