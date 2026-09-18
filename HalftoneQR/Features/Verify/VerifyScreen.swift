import SwiftUI

/// Step three: prove it scans, and say so plainly.
///
/// The symbol resolves into place while the loop runs. If the loop had to pull
/// the logo back to get a clean decode, that is stated rather than hidden.
struct VerifyScreen: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            QRCard(plan: model.plan,
                   animationKey: model.resolveToken,
                   choreography: model.choreography,
                   isScanning: model.isVerifying)
                .padding(.horizontal, Theme.gutter)
                .frame(maxHeight: .infinity)

            report
                .padding(.horizontal, Theme.gutter)
        }
    }

    @ViewBuilder
    private var report: some View {
        VStack(spacing: 14) {
            HStack {
                if model.isVerifying {
                    StatusPill(text: "Decoding", tone: .working)
                } else if let report = model.verification, report.passed {
                    StatusPill(text: "Verified · \(report.summary)", tone: .good)
                } else if model.verification != nil {
                    StatusPill(text: "Not scannable", tone: .bad)
                }
                Spacer()
                if let render = model.verifiedRender, render.attempts > 1 {
                    Text("\(render.attempts) passes")
                        .font(.railLabel)
                        .foregroundStyle(Theme.tertiary)
                }
            }

            if let report = model.verification, let decoded = report.decoded {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Decoded").railLabelStyle()
                    Text(decoded)
                        .font(.mono(13))
                        .foregroundStyle(Theme.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(15)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.elevated))
                .hairlineBorder(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if let render = model.verifiedRender, render.wasReduced {
                HStack(alignment: .top, spacing: 10) {
                    Capsule().fill(Theme.caution).frame(width: 2.5)
                    Text("The logo was eased back to get a clean decode. Strength is now "
                         + String(format: "%.2f", render.config.logoStrength) + ".")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task {
            if model.verification == nil {
                await model.runVerification()
            }
        }
    }
}

/// Choreography picker for the verify step: the same round control, plus a
/// replay so the sequence can be watched again.
struct VerifyControls: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            CircleControl(label: model.choreography.title, isSelected: true) {
                model.choreography = model.choreography.next
                model.replayResolve()
            } glyph: {
                MotionGlyph(choreography: model.choreography)
            }

            CircleControl(label: "Replay", isSelected: false) {
                model.replayResolve()
            } glyph: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Resolve").railLabelStyle()
                Text(model.choreography.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
        }
    }
}
