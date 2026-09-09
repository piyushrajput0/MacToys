import CoreAudio
import AudioToolbox
import Foundation

/// Reads and writes the system output volume through CoreAudio.
///
/// The alternative — synthesising the media keys — would give the native volume
/// HUD for free, but posting system events needs Accessibility permission.
/// CoreAudio needs none at all, which keeps the volume gesture usable without
/// granting anything; MacToys draws its own HUD instead.
enum AudioController {

    private static var outputDevice: AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Current output volume as 0...1, or nil when the device exposes no
    /// software volume control (some external DACs and HDMI outputs).
    static var volume: Float? {
        guard let device = outputDevice else { return nil }
        var address = volumeAddress()
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    @discardableResult
    static func setVolume(_ newValue: Float) -> Bool {
        guard let device = outputDevice else { return false }
        var address = volumeAddress()
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return false }

        var clamped = Float32(min(max(newValue, 0), 1))
        let status = AudioObjectSetPropertyData(device, &address, 0, nil,
                                                UInt32(MemoryLayout<Float32>.size), &clamped)
        // Raising the volume from zero should also unmute, or the gesture looks
        // broken: the number goes up and nothing is audible.
        if status == noErr && clamped > 0 { setMuted(false) }
        return status == noErr
    }

    static var isMuted: Bool {
        guard let device = outputDevice else { return false }
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    @discardableResult
    static func setMuted(_ muted: Bool) -> Bool {
        guard let device = outputDevice else { return false }
        var address = muteAddress()
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return false }
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(device, &address, 0, nil,
                                          UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    /// Nudges the volume by `steps` increments of `stepSize`, returning the new
    /// level for the HUD, or nil if the device has no adjustable volume.
    @discardableResult
    static func adjust(steps: Int, stepSize: Float = 1.0 / 16.0) -> Float? {
        guard let current = volume else { return nil }
        let target = min(max(current + Float(steps) * stepSize, 0), 1)
        guard setVolume(target) else { return nil }
        return target
    }
}
