// prism — WindowShell bench. The window-shell factory builds a long-lived NSPanel
// whose KEY behavior / chrome / level / click-through are knobs and whose content is
// SwiftUI (NSHostingView). A shell is a real WINDOW — it cannot sit in a static
// screencapture of prism's main window — so the per-theme card shows an INLINE MOCK
// of a shell surface (themed panel + shadow), and a row of LIVE TRIGGERS spawns the
// REAL shell in each configuration. The triggers are the single-display verification
// checklist:
//   • key-on-demand  — the "editable" shell takes keyboard focus on demand: click
//     into its field and TYPE (incl. 日本語 IME) while it floats, without the host losing key.
//   • click-through  — the overlay passes mouse clicks through to whatever is beneath.
//   • Esc / outside-click dismiss — Esc / an outside click close a demo WHILE prism is the
//     active app; the click-through overlay deactivates prism the moment you click through,
//     so it is closed by the "dismiss all" button. "dismiss all" always works.
//   • fade + auto-size — show/hide opacity fade; the auto-size shell fits its content.
//   • screen-union — the overlay spans the whole desktop (every display); the
//     multi-display HOTPLUG reflow needs a second monitor to exercise (single-display
//     can't prove that one path — the union MATH is unit-tested).
//
// prism imports no app View: this draws the REAL ThemeKit shell so the bench can't drift.

import AppKit
import SwiftUI
import Palette
import PaletteKit
import ThemeKit

// MARK: - Spawned demo content (SwiftUI — the shell hosts this via NSHostingView)

private struct ShellDemoContent: View {
    let p: ResolvedPalette
    let title: String
    let note: String
    var editable = false
    @State private var text = ""

    private var surface: Color { Color(nsColor: p.background ?? .windowBackgroundColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(sysFont(13, weight: .bold))
                .foregroundColor(Color(nsColor: p.foreground))
            Text(note)
                .font(sysFont(10, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
                .fixedSize(horizontal: false, vertical: true)
            if editable {
                TextField("type here — 日本語 IME too…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(sysFont(12))
            }
            Spacer(minLength: 0)
            Text("Esc · click outside to dismiss")
                .font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: p.primary), lineWidth: 1.5))
    }
}

private struct ShellOverlayContent: View {
    let p: ResolvedPalette
    let label: String
    var body: some View {
        ZStack {
            Color(nsColor: p.primary).opacity(0.10)
            Text(label)
                .font(sysFont(13, weight: .bold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.foreground))
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Capsule().fill(Color(nsColor: p.background ?? .black).opacity(0.85)))
                .overlay(Capsule().stroke(Color(nsColor: p.primary), lineWidth: 1))
        }
    }
}

// MARK: - Live shell controller (owns each spawned shell + its teardown)

@MainActor private final class ShellDemo: ObservableObject {
    /// One spawned shell plus everything that must die WITH it. Bundling these (vs.
    /// parallel arrays + a panel-only `forget`) is what makes a single dismiss stop the
    /// monitor + observer too, instead of leaking live NSEvent monitors / observers
    /// until `dismissAll()`.
    @MainActor private final class Live {
        let panel: ShellPanel
        let monitor: ShellDismissMonitor
        let reconfig: ScreenReconfigGlue?
        init(_ panel: ShellPanel, _ monitor: ShellDismissMonitor, _ reconfig: ScreenReconfigGlue? = nil) {
            self.panel = panel; self.monitor = monitor; self.reconfig = reconfig
        }
        func teardown() {
            monitor.stop()
            reconfig?.stop()
            ShellFade().fadeOut(panel)
        }
    }
    private var live: [Live] = []

    func dismissAll() {
        for l in live { l.teardown() }
        live.removeAll()
    }

    private func dismiss(_ entry: Live) {
        entry.teardown()
        live.removeAll { $0 === entry }
    }

    /// Spawn `content` in a shell built from `spec`, centred on the main screen, faded
    /// in, dismissable (Esc / outside click while prism is active, or "dismiss all").
    private func present<C: View>(_ spec: WindowShellSpec, size: CGSize, content: C) {
        let panel = makeWindowShell(spec)
        let host = NSHostingView(rootView: content)
        host.frame = CGRect(origin: .zero, size: size)
        panel.contentView = host
        if let vf = NSScreen.main?.visibleFrame {
            let o = CGPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2)
            panel.setFrame(CGRect(origin: o, size: size), display: true)
        }
        let mon = ShellDismissMonitor()
        let entry = Live(panel, mon)
        mon.start(panel: panel) { [weak self, weak entry] in
            guard let self, let entry else { return }
            self.dismiss(entry)
        }
        live.append(entry)
        ShellFade().fadeIn(panel)
    }

    // The four key behaviors + chromes, plus the screen-union overlay.

    func editableOnDemand(_ p: ResolvedPalette) {
        present(WindowShellSpec(keyMode: .onDemand), size: CGSize(width: 380, height: 200),
                content: ShellDemoContent(p: p, title: "key-on-demand shell",
                                          note: "borderless · .nonactivatingPanel · onDemand key.\nClick the field and TYPE — the shell takes focus only because the field needs it.",
                                          editable: true))
    }

    func titledResizable(_ p: ResolvedPalette) {
        present(WindowShellSpec(keyMode: .always, chrome: .titled(resizable: true, closable: true),
                                nonactivating: false),
                size: CGSize(width: 420, height: 240),
                content: ShellDemoContent(p: p, title: "titled · resizable",
                                          note: ".titled + .resizable + .closable.\nDrag the title bar; drag an edge to resize."))
    }

    func hud(_ p: ResolvedPalette) {
        present(WindowShellSpec(chrome: .hud), size: CGSize(width: 360, height: 180),
                content: ShellDemoContent(p: p, title: "HUD panel",
                                          note: ".hudWindow translucent system chrome."))
    }

    func clickThroughOverlay(_ p: ResolvedPalette) {
        // Screen-UNION sized, click-through: clicks pass through to apps beneath. It is
        // never-key + non-activating, so a LOCAL Esc monitor only fires WHILE prism is
        // the active app — the instant you click through, prism deactivates and Esc no
        // longer reaches it, so "dismiss all" is the guaranteed exit (a real overlay app
        // would wire its own global hotkey / event tap, which the library leaves to the
        // caller). A ScreenReconfigGlue re-spans it when the display arrangement changes.
        let union = screenUnionFrame()
        let spec = WindowShellSpec(level: .floating,
                                   collectionBehavior: [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary],
                                   clickThrough: true)
        let panel = makeWindowShell(spec)
        let host = NSHostingView(rootView: ShellOverlayContent(
            p: p, label: "click-through · screen-union overlay  (Esc while prism active · or “dismiss all”)"))
        host.frame = CGRect(origin: .zero, size: union.size)
        panel.contentView = host
        panel.setFrame(union, display: true)
        let reconfig = ScreenReconfigGlue()
        reconfig.start { [weak panel] in
            guard let panel else { return }
            panel.setFrame(screenUnionFrame(), display: true)
        }
        let mon = ShellDismissMonitor()
        let entry = Live(panel, mon, reconfig)
        mon.start(panel: panel, onOutsideClick: false) { [weak self, weak entry] in
            guard let self, let entry else { return }
            self.dismiss(entry)
        }
        live.append(entry)
        ShellFade().fadeIn(panel)
    }
}

// MARK: - Showcase card

struct MockWindowShell: View {
    let p: ResolvedPalette
    @StateObject private var demo = ShellDemo()

    private var surface: Color { Color(nsColor: p.background ?? .underPageBackgroundColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ThemeKit · WindowShell — the family's ONE parameterized AppKit window shell (key-mode / chrome / level / collectionBehavior / click-through), content via NSHostingView (SwiftUI). The card shows an INLINE MOCK of a shell surface; the LIVE TRIGGERS spawn the REAL shell so you can verify single-display behavior: key-on-demand typing, click-through, Esc/outside-click dismiss, fade, auto-size. (Multi-display hotplug reflow needs a 2nd monitor; the union MATH is unit-tested.)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 24) {
                cell("inline mock · a shell surface") {
                    ShellDemoContent(p: p, title: "shell surface", note: "themed content\nhosted in the panel")
                        .frame(width: 220, height: 132)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.30), radius: 10, y: 5)
                }

                cell("live triggers · spawn the real shell") {
                    VStack(alignment: .leading, spacing: 8) {
                        trigger("key-on-demand + text field") { demo.editableOnDemand(p) }
                        trigger("titled · resizable")         { demo.titledResizable(p) }
                        trigger("HUD panel")                  { demo.hud(p) }
                        trigger("click-through · screen-union") { demo.clickThroughOverlay(p) }
                        Button { demo.dismissAll() } label: {
                            Text("dismiss all").font(sysFont(9, weight: .semibold, design: .monospaced))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Color(nsColor: p.tertiary))
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: panelStroke(p)), lineWidth: 1))
    }

    @ViewBuilder
    private func cell<V: View>(_ caption: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            content()
        }
    }

    @ViewBuilder
    private func trigger(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(sysFont(10, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.onPrimary()))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: p.primary)))
        }
        .buttonStyle(.plain)
    }
}
