// ThemeKitUI — the SwiftUI root a non-key AppKit popup (combo/menu) hosts inside its
// panel (#17b M3). It `@Bindable`-observes the imperative `ListController`, so when a
// field key-forwarder / NSEvent monitor mutates `controller.items`/`highlight`/
// `selection`, this view re-renders through the Observation system automatically — the
// host never re-assigns the `NSHostingView.rootView`. Activation/hover/hit-test all
// route through the controller (the SwiftUI rows are inert — `style.hosted == true`).
import SwiftUI
import PaletteKit

public struct HostedThemedList<ID: Hashable & Sendable>: View {
    @Bindable var controller: ListController<ID>
    let style: ThemedListStyle
    let palette: ResolvedPalette

    public init(controller: ListController<ID>, style: ThemedListStyle, palette: ResolvedPalette) {
        self._controller = Bindable(controller)
        self.style = style
        self.palette = palette
    }

    public var body: some View {
        ThemedListView(
            items: controller.items,
            selection: $controller.selection,
            highlight: $controller.highlight,
            style: style,
            palette: palette,
            onActivate: { controller.fireActivate($0) },
            onHover: { controller.setHover($0) },
            onEmptyAction: { controller.onEmptyAction($0) },
            onRowRects: { controller.rowRects = $0 },
            emptyActionRow: controller.emptyActionRow,
            query: controller.query,
            noOptionsText: controller.noOptionsText)
    }
}
