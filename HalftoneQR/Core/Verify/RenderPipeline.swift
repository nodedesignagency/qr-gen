import Foundation

/// A render that has been proven to decode.
struct VerifiedRender: Sendable {
    let plan: RenderPlan
    let config: RenderConfig
    let report: VerificationReport
    /// How many renders it took, including the first.
    let attempts: Int
    /// True when the verify loop had to pull back from what the user asked for.
    let wasReduced: Bool
}

enum RenderPipelineError: Error, LocalizedError {
    case couldNotVerify

    var errorDescription: String? {
        "Could not produce a scannable code for this text."
    }
}

/// Renders, verifies, and retreats until the result actually scans.
///
/// Nothing reaches the UI without having decoded first. When a render fails, the
/// loop walks a ladder that trades likeness for robustness one rung at a time,
/// ending at a plain QR code. That last rung was measured to decode under every
/// simulated capture condition at every symbol size the app can produce, so the
/// loop always terminates with something valid.
actor RenderPipeline {

    private let verifier = QRVerifier()

    func render(payload: String,
                silhouette: Silhouette?,
                config: RenderConfig,
                palette: Palette) async throws -> VerifiedRender {

        var attempts = 0
        for (index, candidate) in ([config] + RenderConfig.fallbackLadder(from: config)).enumerated() {
            try Task.checkCancellation()
            attempts += 1
            let plan = try HalftonePlanner.makePlan(payload: payload, silhouette: silhouette,
                                                    config: candidate, palette: palette)
            let report = await verifier.verify(plan: plan, expecting: payload)
            if report.passed {
                return VerifiedRender(plan: plan, config: candidate, report: report,
                                      attempts: attempts, wasReduced: index > 0)
            }
        }

        // Every rung failed, which should not happen. Fall back to a plain symbol
        // with no artwork at all rather than showing something broken.
        var plain = config
        plain.logoStrength = 0
        plain.centreFraction = 0.72
        plain.showsEmblem = false
        let plan = try HalftonePlanner.makePlan(payload: payload, silhouette: nil,
                                                config: plain, palette: palette)
        let report = await verifier.verify(plan: plan, expecting: payload)
        guard report.passed else { throw RenderPipelineError.couldNotVerify }
        return VerifiedRender(plan: plan, config: plain, report: report,
                              attempts: attempts + 1, wasReduced: true)
    }

    /// A fast, unverified plan for the live preview while a slider is moving.
    /// The verified render replaces it as soon as the gesture settles.
    func preview(payload: String, silhouette: Silhouette?,
                 config: RenderConfig, palette: Palette) throws -> RenderPlan {
        try HalftonePlanner.makePlan(payload: payload, silhouette: silhouette,
                                     config: config, palette: palette)
    }
}
