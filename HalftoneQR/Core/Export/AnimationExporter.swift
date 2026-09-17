import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders the resolve animation to a shareable file.
///
/// Frames are produced by the same planner and renderer the stills use, just
/// sampled at successive points along the choreography, so the last frame is
/// pixel-identical to the exported PNG.
enum AnimationExporter {

    struct Settings: Sendable {
        var choreography: Choreography = .structureFirst
        var frameCount: Int = 48
        var frameRate: Double = 30
        var pixelSize: Int = 640
        /// Frames held on the finished symbol at the end, so the loop reads.
        var holdFrames: Int = 14
    }

    /// An animated GIF. Universally shareable, and small at these dimensions.
    static func gif(for plan: RenderPlan, settings: Settings = Settings()) -> Data? {
        let frames = renderFrames(plan: plan, settings: settings)
        guard !frames.isEmpty else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.gif.identifier as CFString,
            frames.count, nil) else { return nil }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        let delay = 1.0 / settings.frameRate
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: delay]
        ] as CFDictionary
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// An H.264 movie, for anywhere a GIF would look coarse.
    static func movie(for plan: RenderPlan, settings: Settings = Settings(),
                      to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        // H.264 requires even dimensions.
        let side = settings.pixelSize - (settings.pixelSize % 2)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: side,
            AVVideoHeightKey: side,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: side,
                kCVPixelBufferHeightKey as String: side,
            ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var frameSettings = settings
        frameSettings.pixelSize = side
        let frames = renderFrames(plan: plan, settings: frameSettings)
        let timescale = CMTimeScale(600)
        let step = CMTime(value: CMTimeValue(600.0 / settings.frameRate), timescale: timescale)

        for (index, frame) in frames.enumerated() {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 4_000_000)
            }
            guard let pool = adaptor.pixelBufferPool,
                  let buffer = pixelBuffer(from: frame, pool: pool, side: side) else { continue }
            adaptor.append(buffer, withPresentationTime: CMTimeMultiply(step, multiplier: Int32(index)))
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed, let error = writer.error { throw error }
    }

    // MARK: - Frames

    private static func renderFrames(plan: RenderPlan, settings: Settings) -> [CGImage] {
        var frames: [CGImage] = []
        frames.reserveCapacity(settings.frameCount + settings.holdFrames)
        let steps = max(settings.frameCount, 2)
        for index in 0..<steps {
            let time = Double(index) / Double(steps - 1)
            let frame = plan.revealed(by: settings.choreography, at: time)
            if let image = RasterRenderer.image(for: frame, pixelSize: settings.pixelSize) {
                frames.append(image)
            }
        }
        if let last = frames.last {
            frames.append(contentsOf: Array(repeating: last, count: max(settings.holdFrames, 0)))
        }
        return frames
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool,
                                    side: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return buffer
    }
}
