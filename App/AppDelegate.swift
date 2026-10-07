import AppKit
import TaktCore
import TaktSystem
import TaktUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var composition: Composition?
    private var statusItem: NSStatusItem?
    private var panel: PopoverPanel?
    private var mainWindow: MainWindowController?
    private var onboarding: OnboardingWindowController?
    private var titleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let composition: Composition
        do {
            composition = try Composition()
        } catch {
            showLaunchFailure(error)
            return
        }
        self.composition = composition
        panel = PopoverPanel(rootView: PopoverView(model: composition.menuBar))
        statusItem = makeStatusItem()
        mainWindow = MainWindowController(model: composition.mainWindow)
        composition.menuBar.openMainWindow = { [weak self] in self?.showMainWindow() }
        composition.onIdleNeedsDecision = { [weak self] in self?.showPanel() }
        composition.launch()

        GlobalShortcut.togglePopover.onKeyUp { [weak self] in
            // During the onboarding the shortcut is being tried out (step 2).
            if let onboarding = self?.onboarding, onboarding.isVisible {
                onboarding.model.shortcutPressed()
            } else {
                self?.togglePanel()
            }
        }
        GlobalShortcut.togglePauseAll.onKeyUp {
            Task { await composition.menuBar.togglePauseAll() }
        }
        observeStatus()
        scheduleTitleUpdates()
        if !composition.settings.onboardingCompleted {
            showOnboarding(composition.settings)
        }

        #if DEBUG
            // For screenshots and UI tests: `-openPopover YES` / `-openMainWindow YES` show the popover or
            // main window at launch, `-appearance dark|light` forces an appearance and
            // `-onboardingCompleted YES` skips the onboarding.
            if let appearance = UserDefaults.standard.string(forKey: "appearance") {
                NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            }
            if UserDefaults.standard.bool(forKey: "openMainWindow") {
                if let section = UserDefaults.standard.string(forKey: "mainSection")
                    .flatMap(MainWindowModel.Section.init(rawValue:))
                {
                    composition.mainWindow.section = section
                }
                showMainWindow()
                if UserDefaults.standard.bool(forKey: "selectFirstEntry") {
                    Task {
                        await composition.mainWindow.reload()
                        composition.mainWindow.selection = Set(composition.mainWindow.data.entries.suffix(1).map(\.id))
                    }
                }
            }
            if UserDefaults.standard.bool(forKey: "openPopover") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.togglePanel() }
            }
        #endif
    }

    // MARK: Status item

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        return item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(
            withTitle: String(localized: "Open Takt"),
            action: #selector(openMainWindowFromMenu),
            keyEquivalent: "0"
        ).target = self
        menu.addItem(
            withTitle: String(localized: "Settings …"),
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Quit Takt"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openMainWindowFromMenu() {
        showMainWindow()
    }

    @objc private func openSettingsFromMenu() {
        composition?.mainWindow.section = .settings
        showMainWindow()
    }

    private func showOnboarding(_ settings: AppSettings) {
        let controller = OnboardingWindowController(
            model: OnboardingModel(settings: settings, azureDevOps: composition?.azureDevOps)
        )
        controller.model.onFinish = { [weak self] in
            self?.onboarding?.close()
            self?.onboarding = nil
            self?.showPanel()
        }
        onboarding = controller
        #if DEBUG
            if let step = OnboardingModel.Step(rawValue: UserDefaults.standard.integer(forKey: "onboardingStep")) {
                controller.model.step = step
            }
        #endif
        controller.show()
    }

    private func showMainWindow() {
        panel?.orderOut(nil)
        mainWindow?.show()
    }

    private func togglePanel() {
        if panel?.isVisible == true {
            panel?.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel, let button = statusItem?.button, !panel.isVisible else { return }
        composition?.menuBar.popoverDidOpen()
        panel.show(below: button)
    }

    /// Redraws the status item whenever the timer state changes.
    private func observeStatus() {
        withObservationTracking {
            updateStatusItem()
        } onChange: {
            Task { @MainActor [weak self] in self?.observeStatus() }
        }
    }

    /// The running time in the title changes once a minute, aligned to the minute boundary.
    private func scheduleTitleUpdates() {
        let now = Date()
        let nextMinute =
            Calendar.current.nextDate(
                after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime
            ) ?? now.addingTimeInterval(60)
        let timer = Timer(fire: nextMinute, interval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatusItem() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        titleTimer = timer
    }

    private func updateStatusItem() {
        guard let composition, let button = statusItem?.button else { return }
        let status = MenuBarStatus(snapshot: composition.menuBar.snapshot, now: composition.clock.now())
        let image = NSImage(
            systemSymbolName: status.symbolName,
            accessibilityDescription: String(localized: "Takt")
        )
        image?.isTemplate = true
        button.image = image
        let showTitle = composition.settings.showElapsedInMenuBar
        button.title = showTitle ? status.title.map { " \($0)" } ?? "" : ""
    }

    private func showLaunchFailure(_ error: any Error) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Takt could not open its database.")
        alert.informativeText = error.localizedDescription
        alert.runModal()
        NSApp.terminate(nil)
    }
}
