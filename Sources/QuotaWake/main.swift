import AppKit

// Executable entry point. App model, delegate, views, and the DEBUG-only
// UI-QA harness live in the sibling files of this target.
let application = NSApplication.shared
let delegate = QuotaWakeApplicationDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
