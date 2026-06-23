import Foundation

/// Resolve a proposed selection id to a committed one, mirroring
/// `ThemedList.setSelection`'s resolution: keep `proposed` iff it is a present,
/// selectable row (the caller encodes "present AND selectable" in `isSelectable`);
/// otherwise nil. `didChange` is `resolved != current`. Pure / Foundation-only.
public func resolveSelection(proposed: String?, current: String?,
                             isSelectable: (String) -> Bool) -> (resolved: String?, didChange: Bool) {
    let resolved = proposed.flatMap { isSelectable($0) ? $0 : nil }
    return (resolved, resolved != current)
}
