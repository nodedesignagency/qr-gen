import Foundation

/// A render that has been proven to decode.
struct VerifiedRender: Sendable {
    let plan: RenderPlan
    let config: RenderConfig
    let report: VerificationReport
    /// How many renders it took, including the first.
    var attempts: Int { log.count }
    /// True when the verify loop had to pull back from what the user asked for.
    let wasReduced: Bool
    /// Every pass the loop made, in order. The generate animation plays this
    /// back, so what is on screen is the work that actually happened rather than
    /// a timer pretending to be progress.
    let log: [Attempt]

    struct Attempt: Sendable {
        let plan: RenderPlan
        let config: RenderConfig
        let passed: Bool
    }
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

        var log: [VerifiedRender.Attempt] = []
        for (index, candidate) in ([config] + RenderConfig.fallbackLadder(from: config)).enumerated() {
            try Task.checkCancellation()
            let plan = try HalftonePlanner.makePlan(payload: payload, silhouette: silhouette,
                                                    config: candidate, palette: palette)
            let report = await verifier.verify(plan: plan, expecting: payload)
            log.append(VerifiedRender.Attempt(plan: plan, config: candidate, passed: report.passed))
            if report.passed {
                return VerifiedRender(plan: plan, config: candidate, report: report,
                                      wasReduced: index > 0, log: log)
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
        log.append(VerifiedRender.Attempt(plan: plan, config: plain, passed: report.passed))
        guard report.passed else { throw RenderPipelineError.couldNotVerify }
        return VerifiedRender(plan: plan, config: plain, report: report,
                              wasReduced: true, log: log)
    }

    /// A fast, unverified plan for the live preview while a slider is moving.
    /// The verified render replaces it as soon as the gesture settles.
    func preview(payload: String, silhouette: Silhouette?,
                 config: RenderConfig, palette: Palette) throws -> RenderPlan {
        try HalftonePlanner.makePlan(payload: payload, silhouette: silhouette,
                                     config: config, palette: palette)
    }
}
