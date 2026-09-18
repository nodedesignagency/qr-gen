import AVFoundation
import SwiftUI
import UIKit

/// A silent, looping video filling the screen behind everything else.
///
/// The player is muted and set not to disturb audio already playing, so opening
/// the app never interrupts someone's music. When no video is bundled it falls
/// back to a still field in the same palette, so the layout is never broken by a
/// missing asset.
struct VideoBackground: View {
    /// Basename of a video in the app bundle, without extension.
    var resource: String = "background"
    var fallback: LinearGradient = Palette.waterFallback

    var body: some View {
        ZStack {
            fallback
            if let url = Self.url(for: resource) {
                LoopingPlayerView(url: url)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    static func url(for resource: String) -> URL? {
        for ext in ["mp4", "mov", "m4v"] {
            if let url = Bundle.main.url(forResource: resource, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    enum Palette {
        /// Stands in for the water loop until the asset is added.
        static let waterFallback = LinearGradient(
            colors: [Color(red: 0.22, green: 0.76, blue: 0.80),
                     Color(red: 0.16, green: 0.64, blue: 0.70),
                     Color(red: 0.30, green: 0.82, blue: 0.84)],
            startPoint: .top, endPoint: .bottom)
    }
}

/// Wraps an `AVPlayerLayer` because SwiftUI's `VideoPlayer` insists on transport
/// controls, which a background must not have.
private struct LoopingPlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.load(url: url)
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.teardown()
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var looper: AVPlayerLooper?
        private var queuePlayer: AVQueuePlayer?
        private var foregroundObserver: NSObjectProtocol?

        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        func load(url: URL) {
            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            player.actionAtItemEnd = .advance
            // AVPlayerLooper gives a gapless loop; seeking on end does not.
            looper = AVPlayerLooper(player: player, templateItem: item)
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            queuePlayer = player
            player.play()

            // Playback is suspended on backgrounding, so resume on return.
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil, queue: .main) { [weak player] _ in
                    player?.play()
                }
        }

        func teardown() {
            queuePlayer?.pause()
            if let foregroundObserver {
                NotificationCenter.default.removeObserver(foregroundObserver)
            }
            looper = nil
            queuePlayer = nil
            playerLayer.player = nil
        }
    }
}
