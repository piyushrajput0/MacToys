import AppKit

// MacToys runs as a menu-bar agent: no Dock icon, no main window. The delegate
// is retained by a local binding for the lifetime of the run loop.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
