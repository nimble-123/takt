import SwiftUI
import TaktCore

/// "Inaktivität erkannt": mini timeline with hatched inactivity and four choices,
/// "count as pause" preselected (docs/DESIGN.md).
struct IdleDialog: View {
    enum Choice: Hashable, CaseIterable {
        case keep, pause, discard, reassign
    }

    let model: MenuBarModel
    let event: IdleEvent
    @State private var choice = Choice.pause
    @State private var reassignTitle = ""

    private var duration: TimeInterval { event.end.seconds(since: event.start) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(Palette.warning)
                    .accessibilityHidden(true)
                Text("Inactivity detected", bundle: .module)
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(
                "Away from \(event.start.date, format: .dateTime.hour().minute()) to \(event.end.date, format: .dateTime.hour().minute()) (\(DurationText.span(duration))).",
                bundle: .module
            )
            .font(.system(size: 12))
            .foregroundStyle(Palette.textSecondary)

            IdleTimeline(event: event)
                .frame(height: 10)

            Picker(selection: $choice) {
                Text("Keep as work time", bundle: .module).tag(Choice.keep)
                Text("Count as pause", bundle: .module).tag(Choice.pause)
                Text("Discard", bundle: .module).tag(Choice.discard)
                Text("Assign to another task", bundle: .module).tag(Choice.reassign)
            } label: {
                EmptyView()
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .font(.system(size: 12))

            if choice == .reassign {
                TextField(String(localized: "Task", bundle: .module), text: $reassignTitle)
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        if reassignTitle.isEmpty { reassignTitle = model.recents.first?.title ?? "" }
                    }
            }

            HStack {
                Spacer()
                Button {
                    Task { await model.resolveIdle(decision) }
                } label: {
                    Text("Apply", bundle: .module)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(choice == .reassign && reassignTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
        .background(Palette.warningSurface, in: RoundedRectangle(cornerRadius: 8))
    }

    private var decision: IdleDecision {
        switch choice {
        case .keep: .keep
        case .pause: .pause
        case .discard: .discard
        case .reassign: .reassign(EntryDraft(title: reassignTitle.trimmingCharacters(in: .whitespaces)))
        }
    }
}

/// Tracked time before the inactivity, then the inactivity hatched in amber.
struct IdleTimeline: View {
    let event: IdleEvent

    var body: some View {
        Canvas { context, size in
            let idle = event.end.seconds(since: event.start)
            // Show at least as much tracked time before as the inactivity lasted, capped at 1 h.
            let before = min(max(idle, 15 * 60), 3600)
            let split = size.width * before / (before + idle)
            let bar = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            context.clip(to: bar)
            context.fill(Path(CGRect(x: 0, y: 0, width: split, height: size.height)), with: .color(Palette.accent))
            let idleRect = CGRect(x: split, y: 0, width: size.width - split, height: size.height)
            context.fill(Path(idleRect), with: .color(Palette.warningSurface))
            var hatch = Path()
            var x = split - size.height
            while x < size.width {
                hatch.move(to: CGPoint(x: x, y: size.height))
                hatch.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 5
            }
            context.clip(to: Path(idleRect))
            context.stroke(hatch, with: .color(Palette.warning), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}
