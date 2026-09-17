import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// What we can learn about a site from its own markup.
struct SiteMetadata: Sendable {
    var iconURL: URL?
    var themeColour: RGB?
    var title: String?
}

/// Fetches a fallback mark and brand colour from the URL the user typed.
///
/// Best effort by design: it runs in the background, and every failure just means
/// the user uploads a logo instead. Nothing is uploaded anywhere — the app only
/// reads the page the user already pointed at.
enum SiteMetadataFetcher {

    private static let maximumBytes = 512 * 1024

    static func fetch(for url: URL) async -> SiteMetadata {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        // Some sites serve a stripped page to unknown agents; ask for the normal one.
        request.setValue("Mozilla/5.0 (iPhone) AppleWebKit/605.1.15 HalftoneQR/1.0",
                         forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode)
        else { return SiteMetadata() }

        let head = String(decoding: data.prefix(maximumBytes), as: UTF8.self)
        let base = http.url ?? url
        return parse(html: head, base: base)
    }

    static func parse(html: String, base: URL) -> SiteMetadata {
        var metadata = SiteMetadata()

        if let colour = firstMatch(in: html, pattern: #"<meta[^>]+name=["']theme-color["'][^>]+content=["']([^"']+)["']"#)
            ?? firstMatch(in: html, pattern: #"<meta[^>]+content=["']([^"']+)["'][^>]+name=["']theme-color["']"#) {
            metadata.themeColour = RGB(hex: colour)
        }

        // Prefer a square, purpose-made icon over the social card, which is
        // usually a wide screenshot and makes a poor silhouette.
        let iconPatterns = [
            #"<link[^>]+rel=["'](?:apple-touch-icon|apple-touch-icon-precomposed)["'][^>]+href=["']([^"']+)["']"#,
            #"<link[^>]+href=["']([^"']+)["'][^>]+rel=["'](?:apple-touch-icon|apple-touch-icon-precomposed)["']"#,
            #"<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']"#,
            #"<link[^>]+rel=["'][^"']*icon[^"']*["'][^>]+href=["']([^"']+)["']"#,
        ]
        for pattern in iconPatterns {
            if let found = firstMatch(in: html, pattern: pattern),
               let resolved = URL(string: found, relativeTo: base)?.absoluteURL {
                metadata.iconURL = resolved
                break
            }
        }

        if let title = firstMatch(in: html, pattern: #"<title[^>]*>([^<]{1,120})</title>"#) {
            metadata.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return metadata
    }

    /// Downloads and decodes the icon we found.
    static func loadIcon(at url: URL) async -> CGImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return ImageDecoder.decode(data)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captured])
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Normalises whatever the user typed into something encodable.
enum URLNormaliser {

    /// Adds a scheme when the user omitted it, and reports whether the result
    /// looks like a real address.
    static func normalise(_ text: String) -> (value: String, url: URL?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", nil) }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate), let host = url.host, host.contains(".") else {
            return (trimmed, nil)
        }
        return (candidate, url)
    }

    /// Rough guidance on payload length, since every extra character can push the
    /// symbol to a higher version and shrink every module.
    static func lengthAdvice(for text: String, correction: QRErrorCorrection = .high) -> (version: Int, warning: String?)? {
        guard !text.isEmpty,
              let symbol = try? QREncoder.encode(text: text, correction: correction, maskChoice: .fixed(0))
        else { return nil }
        let version = symbol.version
        switch version {
        case ..<5:
            return (version, nil)
        case 5..<9:
            return (version, "\(symbol.size) modules. Still roomy — the mark will read clearly.")
        case 9..<14:
            return (version, "\(symbol.size) modules. Blocks are getting small; the likeness will soften.")
        default:
            return (version, "\(symbol.size) modules. This is dense — consider a short link for a stronger mark.")
        }
    }
}
