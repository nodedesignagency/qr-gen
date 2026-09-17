import SwiftUI

/// Step three: prove it scans, and say so plainly.
///
/// The symbol resolves into place while the loop runs. If the loop had to pull
/// the logo back to get a clean decode, that is stated rather than hidden.
struct VerifyScreen: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            QRPreview(plan: model.plan,
                      resolveProgress: model.resolveProgress,
                      choreography: model.choreography,
                      isScanning: model.isVerifying)
                .padding(.horizontal, 32)
                .frame(maxHeight: .infinity)

            report
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 10)
        }
        .task {
            if model.verification == nil {
                await model.runVerification()
            }
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Decoded").railLabelStyle()
                    Text(decoded)
                        .font(.mono(13))
                        .foregroundStyle(Theme.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.sunken))
                .hairlineBorder(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let render = model.verifiedRender, render.wasReduced {
                HStack(alignment: .top, spacing: 10) {
                    Rectangle().fill(Theme.caution).frame(width: 2)
                    Text("The logo was eased back to get a clean decode. Strength is now "
                         + String(format: "%.2f", render.config.logoStrength) + ".")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Choreography picker, shown in the bottom bar on the verify step.
struct VerifyControls: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Resolve").railLabelStyle()
                Spacer()
                Text(model.choreography.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Choreography.allCases) { option in
                        Button {
                            model.choreography = option
                            Task { await model.replayResolve() }
                        } label: {
                            Text(option.title)
                                .railLabelStyle(model.choreography == option
                                                ? Theme.primary : Theme.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    Capsule().fill(model.choreography == option
                                                   ? Color.white.opacity(0.06) : .clear))
                                .hairlineBorder(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
            .animation(.easeOut(duration: 0.14), value: model.choreography)
        }
    }
}
