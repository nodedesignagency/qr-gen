import SwiftUI

/// The whole app: a quiet title, the card, and one action.
///
/// Every screen has the same shape — name at the top, the symbol occupying the
/// middle, controls confined to the bottom bar. Content never sits on chrome.
struct RootView: View {
    @State private var model = AppModel()

    var body: some View {
        ZStack {
            // The input screen is built to the design file and owns its whole
            // canvas, video background included. The later stages still run on
            // the dark chrome until they are redrawn in turn.
            if model.stage == .input {
                InputScreen(model: model)
            } else {
                Theme.background.ignoresSafeArea()
                darkStage
            }

            if model.generatePhase.isRunning {
                PrintSequenceOverlay(phase: model.generatePhase,
                                     plan: model.generatingPlan,
                                     choreography: model.choreography,
                                     accent: model.accentColour)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .environment(\.signalAccent, model.accentColour)
        .preferredColorScheme(.dark)
        .tint(model.accentColour)
        .animation(.easeOut(duration: 0.24), value: model.stage)
    }

    /// Header, content and bottom bar, as the remaining stages still expect.
    private var darkStage: some View {
        VStack(spacing: 0) {
            StageHeader(title: title,
                        step: model.stage.rawValue,
                        stepCount: Stage.allCases.count,
                        trailingLabel: "Reset",
                        showsTrailing: true,
                        onTrailing: { model.startOver() })
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 4)
                .padding(.bottom, 20)

            stageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomBar {
                VStack(spacing: 20) {
                    controls
                    primaryAction
                }
            }
        }
    }

    private var title: String {
        switch model.stage {
        case .input: return "New code"
        case .tune: return "Customise"
        case .verify: return "Verify"
        case .export: return "Export"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var stageContent: some View {
        switch model.stage {
        case .input:
            EmptyView()
        case .tune:
            TuneScreen(model: model)
        case .verify:
            VerifyScreen(model: model)
        case .export:
            ExportScreen(model: model)
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private var controls: some View {
        switch model.stage {
        case .input:
            EmptyView()
        case .tune:
            TuneControls(model: model)
        case .verify:
            VerifyControls(model: model)
        case .export:
            ExportControls(model: model)
        }
    }

    private var primaryAction: some View {
        HStack(spacing: 12) {
            if model.stage != .input {
                Button {
                    model.back()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: Theme.controlHeight, height: Theme.controlHeight)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                        .hairlineBorder(Circle())
                }
                .buttonStyle(.plain)
            }

            Button(action: primaryActionTapped) {
                Text(primaryTitle)
            }
            .buttonStyle(PrimaryButtonStyle(tint: model.accentColour))
            .disabled(!primaryEnabled)
        }
    }

    private var primaryTitle: String {
        switch model.stage {
        case .input: return "Generate"   // input draws its own action
        case .tune: return "Verify"
        case .verify: return model.verification?.passed == true ? "Export" : "Verifying"
        case .export: return model.exportBundle == nil ? "Write files" : "Done"
        }
    }

    private var primaryEnabled: Bool {
        switch model.stage {
        case .input: return model.canContinueFromInput
        case .tune: return model.plan != nil
        case .verify: return model.verification?.passed == true
        case .export: return model.selected != nil && !model.isExporting
        }
    }

    private func primaryActionTapped() {
        switch model.stage {
        case .input, .tune, .verify:
            model.advance()
        case .export:
            if model.exportBundle == nil {
                Task { await model.export() }
            }
        }
    }
}
