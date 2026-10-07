import SwiftUI
import TaktCore
import TaktSystem

/// First launch in three steps, under a minute (PRD "Onboarding"): connect Azure DevOps
/// (skippable), try the shortcut, choose start behaviour and counting.
@MainActor
@Observable
public final class OnboardingModel {
    public enum Step: Int, CaseIterable {
        case azureDevOps, shortcut, behaviour
    }

    public var step: Step = .azureDevOps
    /// Set when the global shortcut was pressed during step 2.
    public private(set) var shortcutTested = false
    public var launchAtLogin = true
    let settings: AppSettings
    /// Step 1; `nil` shows only the explanation.
    let azureDevOps: AzureDevOpsModel?
    @ObservationIgnored public var onFinish: (() -> Void)?

    public init(settings: AppSettings, azureDevOps: AzureDevOpsModel? = nil) {
        self.settings = settings
        self.azureDevOps = azureDevOps
    }

    /// The app forwards the global shortcut here while the onboarding is open.
    public func shortcutPressed() {
        if step == .shortcut { shortcutTested = true }
    }

    public func next() {
        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        } else {
            finish()
        }
    }

    public func back() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    public func finish() {
        try? LoginItem.setEnabled(launchAtLogin)
        settings.onboardingCompleted = true
        onFinish?()
    }
}

public struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    public init(model: OnboardingModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 6) {
                ForEach(OnboardingModel.Step.allCases, id: \.self) { step in
                    Capsule()
                        .fill(step.rawValue <= model.step.rawValue ? Palette.accent : Palette.separator)
                        .frame(height: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Step \(model.step.rawValue + 1) of 3", bundle: .module))

            Group {
                switch model.step {
                case .azureDevOps: azureDevOps
                case .shortcut: shortcut
                case .behaviour: behaviour
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                if model.step != .azureDevOps {
                    Button(String(localized: "Back", bundle: .module)) { model.back() }
                }
                Spacer()
                if model.step == .azureDevOps {
                    Button(String(localized: "Skip", bundle: .module)) { model.next() }
                }
                Button {
                    model.next()
                } label: {
                    Text(model.step == .behaviour ? "Start using Takt" : "Continue", bundle: .module)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520, height: 460)
    }

    private func title(_ text: Text, _ detail: Text) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            text.font(.system(size: 20, weight: .semibold))
            detail.foregroundStyle(Palette.textSecondary)
        }
    }

    @ViewBuilder
    private var azureDevOps: some View {
        VStack(alignment: .leading, spacing: 16) {
            title(
                Text("Connect Azure DevOps", bundle: .module),
                Text(
                    "Link work items and book your time to them. You can do this later in the settings.",
                    bundle: .module)
            )
            if let azureDevOps = model.azureDevOps {
                AzureDevOpsOnboarding(model: azureDevOps)
            }
        }
    }

    private var shortcut: some View {
        VStack(alignment: .leading, spacing: 16) {
            title(
                Text("Your shortcut", bundle: .module),
                Text("Press it in any app to open Takt, type two letters and hit Return.", bundle: .module)
            )
            HStack {
                Text("Open Takt", bundle: .module)
                Spacer()
                ShortcutRecorder(.togglePopover)
            }
            Label {
                Text(model.shortcutTested ? "Works. Takt is one keystroke away." : "Try it now.", bundle: .module)
            } icon: {
                Image(systemName: model.shortcutTested ? "checkmark.circle.fill" : "keyboard")
                    .foregroundStyle(model.shortcutTested ? Palette.accent : Palette.textSecondary)
            }
            .font(.system(size: 14, weight: .medium))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                model.shortcutTested ? Palette.accentSurface : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var behaviour: some View {
        @Bindable var settings = model.settings
        return VStack(alignment: .leading, spacing: 14) {
            title(
                Text("How Takt counts", bundle: .module),
                Text("You can change this at any time, also per entry.", bundle: .module)
            )
            Picker(String(localized: "Starting a timer", bundle: .module), selection: $settings.startMode) {
                Text("Switch: the new timer pauses the running one", bundle: .module).tag(
                    TimerEngine.StartMode.switchTo)
                Text("In parallel: both keep running", bundle: .module).tag(TimerEngine.StartMode.parallel)
            }
            .pickerStyle(.radioGroup)
            Picker(String(localized: "Parallel time", bundle: .module), selection: $settings.countingMode) {
                Text("Full", bundle: .module).tag(CountingMode.full)
                Text("Shared", bundle: .module).tag(CountingMode.split)
            }
            .pickerStyle(.segmented)
            CountingExample(mode: model.settings.countingMode)
            Toggle(String(localized: "Open Takt at login", bundle: .module), isOn: $model.launchAtLogin)
        }
    }
}

/// Meeting 60 min with a ticket worked on in parallel for 30 min.
private struct CountingExample: View {
    let mode: CountingMode

    var body: some View {
        let ticket: Double = mode == .full ? 30 : 15
        let meeting: Double = mode == .full ? 60 : 45
        VStack(alignment: .leading, spacing: 6) {
            bar(String(localized: "Meeting", bundle: .module), counted: meeting, from: 0, length: 1, "#C2410C")
            bar(String(localized: "Ticket", bundle: .module), counted: ticket, from: 0.5, length: 0.5, "#2563EB")
            Text(
                mode == .full
                    ? "Each timer counts the full time: 90 min in total for 60 min of work."
                    : "Parallel time is split: 60 min in total, as on the clock.",
                bundle: .module
            )
            .font(.system(size: 11))
            .foregroundStyle(Palette.textSecondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .animation(.snappy, value: mode)
    }

    /// A bar over the hour from `from` for `length` (fractions of the hour), labelled with the counted minutes.
    private func bar(_ title: String, counted: Double, from: Double, length: Double, _ hex: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).frame(width: 60, alignment: .leading)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 3)
                    .fill(CategoryColors.color(hex).opacity(0.85))
                    .frame(width: proxy.size.width * length)
                    .offset(x: proxy.size.width * from)
            }
            .frame(height: 10)
            Text("\(Int(counted)) min").font(.system(size: 11)).monospacedDigit().frame(width: 48, alignment: .trailing)
        }
    }
}
