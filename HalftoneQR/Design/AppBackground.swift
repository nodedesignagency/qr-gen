import AVFoundation
import SwiftUI
import UIKit

/// The full-bleed background behind the first screen.
///
/// Three sources, in order of preference: a bundled video loop, the still image
/// in the asset catalogue, then a plain field in the same palette. The design
/// file layers a 20% black fill over the image, which is what keeps the white
/// type legible against the bright water, so the scrim is part of this view
/// rather than something each screen remembers to add.
struct AppBackground: View {
    /// Basename of a video in the bundle, without extension. When present it
    /// wins over the still.
    var videoResource: String = "background"
    /// Asset catalogue name of the still.
    var imageResource: String = "pool-background"
    /// `000000` at 20%, straight from the file.
    var scrimOpacity: Double = 0.20

    var body: some View {
        ZStack {
            Self.fallbackField
            if let url = Self.videoURL(named: videoResource) {
                LoopingPlayerView(url: url)
            } else if UIImage(named: imageResource) != nil {
                Image(imageResource)
                    .resizable()
                    .scaledToFill()
            }
            Color.black.opacity(scrimOpacity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    static func videoURL(named name: String) -> URL? {
        for ext in ["mp4", "mov", "m4v"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    /// Stands in if neither asset is present, so layout never breaks.
    static let fallbackField = LinearGradient(
        colors: [Color(red: 0.22, green: 0.76, blue: 0.80),
                 Color(red: 0.16, green: 0.64, blue: 0.70),
                 Color(red: 0.30, green: 0.82, blue: 0.84)],
        startPoint: .top, endPoint: .bottom)
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
