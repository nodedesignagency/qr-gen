import UIKit

/// A mark bundled with the app, for trying it without a file to hand.
///
/// Any `sample-*.png` in the bundle is one. Drop a PNG into
/// `HalftoneQR/Resources/Samples/` with that prefix and it appears on the input
/// page; its name comes from the filename. Resources are flattened into the
/// bundle root, so the prefix is also what keeps them apart from everything
/// else in there.
struct SampleLogo: Identifiable {
    let url: URL
    let name: String
    /// For the thumbnail. The planner decodes the file itself, the same way it
    /// decodes a picked one.
    let image: UIImage

    var id: String { url.lastPathComponent }

    static let all: [SampleLogo] = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "png", subdirectory: nil) ?? []
        return urls
            .filter { $0.lastPathComponent.hasPrefix("sample-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let image = UIImage(contentsOfFile: url.path) else { return nil }
                let stem = url.deletingPathExtension().lastPathComponent.dropFirst("sample-".count)
                return SampleLogo(url: url, name: String(stem).capitalized, image: image)
            }
    }()
}
