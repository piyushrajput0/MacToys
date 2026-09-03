import AppKit
import MacToysCore

/// Grabs the colour of any pixel on screen and copies it in the format you
/// actually need — PowerToys' Color Picker.
///
/// `NSColorSampler` is used rather than reading the framebuffer directly: it is
/// a system-provided loupe, it works across displays and Spaces, and crucially
/// it needs no Screen Recording permission.
enum ColorPickerService {

    static func pick(format: ColorFormat, completion: @escaping (String?, NSColor?) -> Void) {
        NSColorSampler().show { picked in
            guard let picked = picked else {
                completion(nil, nil)
                return
            }
            // Components are only defined in an RGB space; the sampler can hand
            // back a colour tagged with a display profile, which would trap on
            // redComponent.
            let rgb = picked.usingColorSpace(.sRGB) ?? picked.usingColorSpace(.deviceRGB)
            guard let c = rgb else {
                completion(nil, nil)
                return
            }
            let text = ColorFormatter.string(red: Double(c.redComponent),
                                             green: Double(c.greenComponent),
                                             blue: Double(c.blueComponent),
                                             alpha: Double(c.alphaComponent),
                                             format: format)
            completion(text, c)
        }
    }
}
