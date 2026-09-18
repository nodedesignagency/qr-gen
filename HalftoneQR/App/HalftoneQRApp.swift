import SwiftUI

@main
struct HalftoneQRApp: App {

    init() {
        // Picks up any font files bundled under Resources, so the design's
        // typeface takes over as soon as the files are added.
        AppFont.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
