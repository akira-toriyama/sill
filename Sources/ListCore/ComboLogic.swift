import Foundation

/// MUI-style default ComboBox filter: an empty query keeps all; otherwise a
/// case/diacritic-insensitive substring match on the projected label. Generic over
/// `Item` via a `label` projection so the core never links a widget's NSImage.
public func comboFilter<Item>(_ options: [Item], query: String, label: (Item) -> String) -> [Item] {
    guard !query.isEmpty else { return options }
    return options.filter { label($0).localizedStandardContains(query) }
}

/// Reconcile a committed ComboBox selection across an options reload (an index into
/// the old list is meaningless): keep the index if still in range; else re-find by
/// the committed label; else clear the index but KEEP `committedValue` (so a freeSolo
/// revert target survives). Mirrors `ThemedComboBox.optionsChanged`. Pure.
public func reconcileSelection(selectedIndex: Int?, committedValue: String,
                               labels: [String]) -> (selectedIndex: Int?, committedValue: String) {
    if let idx = selectedIndex, labels.indices.contains(idx) {
        return (idx, labels[idx])
    } else if !committedValue.isEmpty, let again = labels.firstIndex(of: committedValue) {
        return (again, committedValue)
    } else {
        return (nil, committedValue)
    }
}
