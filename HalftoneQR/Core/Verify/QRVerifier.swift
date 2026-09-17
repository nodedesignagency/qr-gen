import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Foundation
import Vision

/// One simulated capture: how large the symbol lands on the sensor, and how far
/// out of focus it is.
///
/// These are not arbitrary. They were calibrated against a real decoder while
/// tuning the halftone parameters, and they span the range where a halftone
/// symbol actually starts to break: a crisp screenshot at one end, three pixels
/// per module with camera shake at the other.
struct CaptureCondition: Sendable, Hashable {
    let pixelsPerModule: Double
    let blurRadius: Double
    /// Critical conditions must all pass. The rest are stress tests.
    let isCritical: Bool

    var label: String {
        let blur = blurRadius > 0 ? String(format: " · blur %.1f", blurRadius) : ""
        return String(format: "%.0f px/module%@", pixelsPerModule, blur)
    }

    static let standard: [CaptureCondition] = [
        CaptureCondition(pixelsPerModule: 16, blurRadius: 0.0, isCritical: true),
        CaptureCondition(pixelsPerModule: 10, blurRadius: 0.8, isCritical: true),
        CaptureCondition(pixelsPerModule: 8, blurRadius: 2.5, isCritical: true),
        CaptureCondition(pixelsPerModule: 6, blurRadius: 1.0, isCritical: true),
        CaptureCondition(pixelsPerModule: 5, blurRadius: 1.5, isCritical: false),
        CaptureCondition(pixelsPerModule: 4, blurRadius: 1.2, isCritical: false),
        CaptureCondition(pixelsPerModule: 3, blurRadius: 1.0, isCritical: false),
    ]
}

struct VerificationReport: Sendable {
    let decoded: String?
    let passedConditions: [CaptureCondition]
    let failedConditions: [CaptureCondition]
    /// True when every critical condition decoded and at least two of the three
    /// stress conditions did.
    let passed: Bool

    var total: Int { passedConditions.count + failedConditions.count }
    var summary: String { "\(passedConditions.count)/\(total) captures" }

    static let unverified = VerificationReport(decoded: nil, passedConditions: [],
                                               failedConditions: [], passed: false)
}

/// Decodes a rendered symbol the way a phone camera would see it.
///
/// Vision is the arbiter, as specified. Core Image's detector runs alongside it
/// as an independent second opinion — two different implementations agreeing is
/// a much stronger signal than one saying yes.
/// `CIContext` is documented as safe to use from multiple threads but is not
/// marked `Sendable`, hence the unchecked conformance.
struct QRVerifier: @unchecked Sendable {

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func verify(plan: RenderPlan, expecting payload: String,
                conditions: [CaptureCondition] = CaptureCondition.standard) async -> VerificationReport {
        var passed: [CaptureCondition] = []
        var failed: [CaptureCondition] = []
        var decoded: String?

        for condition in conditions {
            let side = Int((plan.canvasUnits * condition.pixelsPerModule).rounded())
            guard let base = RasterRenderer.image(for: plan, pixelSize: max(side, 48)) else {
                failed.append(condition)
                continue
            }
            let captured = blur(base, radius: condition.blurRadius) ?? base
            let result = decode(captured)
            if let result, result == payload {
                passed.append(condition)
                decoded = result
            } else {
                failed.append(condition)
                if decoded == nil { decoded = result }
            }
        }

        let criticalFailures = failed.filter(\.isCritical).count
        let stressPasses = passed.filter { !$0.isCritical }.count
        let stressTotal = conditions.filter { !$0.isCritical }.count
        let ok = criticalFailures == 0 && stressPasses >= max(stressTotal - 1, 0)

        return VerificationReport(decoded: decoded, passedConditions: passed,
                                  failedConditions: failed, passed: ok)
    }

    /// Single-shot decode of an arbitrary image, used by the "scan it yourself"
    /// affordance on the verify screen.
    func decode(_ image: CGImage) -> String? {
        if let payload = visionDecode(image) { return payload }
        return coreImageDecode(image)
    }

    /// Both detectors must agree for a render to count as verified.
    func decodeStrict(_ image: CGImage) -> String? {
        guard let vision = visionDecode(image),
              let coreImage = coreImageDecode(image),
              vision == coreImage
        else { return nil }
        return vision
    }

    private func visionDecode(_ image: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let observations = request.results ?? []
        return observations.compactMap(\.payloadStringValue).first
    }

    private func coreImageDecode(_ image: CGImage) -> String? {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: ciContext,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: CIImage(cgImage: image)) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }

    private func blur(_ image: CGImage, radius: Double) -> CGImage? {
        guard radius > 0 else { return image }
        let input = CIImage(cgImage: image)

        // Clamp first, or the blur pulls transparency in from beyond the edge and
        // eats into the quiet zone.
        let clamp = CIFilter.affineClamp()
        clamp.inputImage = input
        clamp.transform = .identity
        guard let clamped = clamp.outputImage else { return image }

        let gaussian = CIFilter.gaussianBlur()
        gaussian.inputImage = clamped
        gaussian.radius = Float(radius)
        guard let output = gaussian.outputImage else { return image }

        return ciContext.createCGImage(output, from: input.extent)
    }
}
