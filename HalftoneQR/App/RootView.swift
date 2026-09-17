import SwiftUI

/// The whole app: a rail at the top, the hero in the middle, chrome at the
/// bottom, and nothing else competing for attention.
struct RootView: View {
    @State private var model = AppModel()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 6)
                    .padding(.bottom, 18)

                stageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                BottomBar {
                    VStack(spacing: 16) {
                        controls
                        primaryAction
                    }
                }
                .glassGroup()
            }
        }
        .environment(\.signalAccent, model.accentColour)
        .preferredColorScheme(.dark)
        .tint(model.accentColour)
        .animation(.easeOut(duration: 0.22), value: model.stage)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            StageRail(stages: Stage.allCases.map(\.title), current: model.stage.rawValue)
            if model.stage != .input {
                Button {
                    model.startOver()
                } label: {
                    Text("Reset").railLabelStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var stageContent: some View {
        switch model.stage {
        case .input:
            InputScreen(model: model)
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
        HStack(spacing: 10) {
            if model.stage != .input {
                Button {
                    model.back()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: Theme.controlHeight, height: Theme.controlHeight)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                .background(Circle().fill(.clear).liquidGlass(Circle()))
            }

            Button(action: primaryActionTapped) {
                Text(primaryTitle)
            }
            .buttonStyle(GlassButtonStyle(prominent: true, tint: model.accentColour))
            .disabled(!primaryEnabled)
            .opacity(primaryEnabled ? 1 : 0.4)
        }
    }

    private var primaryTitle: String {
        switch model.stage {
        case .input: return "Generate"
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
