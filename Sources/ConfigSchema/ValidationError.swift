// ValidationError.swift — the structured result of running a SchemaDescriptor's
// structural + cross-field rules over a decoded config document
// (`SchemaDescriptor.validate`, in Validator.swift).
//
// Pure / Sendable / Foundation-only (zero Toml, zero AppKit) — same purity as
// the descriptor data types it pairs with. The validator (Validator.swift) is
// the only part that touches `Toml.Value`; the ERROR model stays decode-free so
// a consumer can branch on `rule` and render `path` without importing Toml.
//
// Each app maps these generic rules onto its own diagnostic vocabulary (chord's
// `ConfigWarning.Kind`, facet's loader warnings, …) — the validator deliberately
// does NOT know app-specific kinds. The contract: the SAME structural /
// cross-field rules the emitted Draft-07 schema expresses are enforced here, so
// "the editor is green" and "the loader accepts it" cannot diverge.

import Foundation

/// One structural / cross-field validation failure, located by a `path` from
/// the document root (e.g. `["bindings", "[2]", "action-keys-delay-ms"]`).
public struct ValidationError: Sendable, Equatable {

    /// Which rule was violated. Generic (schema-level), NOT app-specific — a
    /// consumer maps these onto its own diagnostic kinds. Mirrors the Draft-07
    /// constructs the emitter lowers each rule to.
    public enum Rule: Sendable, Equatable {
        /// A key not in the object's accepted `keySet` (strict table only;
        /// skipped for a `permissive` object). ↔ `additionalProperties: false`.
        case unknownKey(key: String)
        /// A key listed in `ObjectShape.required` (or a `required` NestedTable)
        /// is absent. ↔ `required`.
        case requiredMissing(key: String)
        /// A present value's TOML type doesn't match the field's `Shape`.
        /// `expected` names the wanted shape (e.g. "integer", "array of strings").
        case typeMismatch(key: String, expected: String)
        /// A scalar (or array element) value outside the field's finite domain.
        /// ↔ `enum` / `items.enum`.
        case notInEnum(key: String, value: String, allowed: [String])
        /// A numeric value violating `exclusiveMinimum` / `minimum` / `maximum`.
        case outOfRange(key: String, detail: String)
        /// Fewer than one of these keys present. ↔ `allOf.anyOf` + `required`.
        case anyOfRequired(keys: [String])
        /// Not exactly one of these present. ↔ `allOf.oneOf` + `required`.
        case oneOfRequired(keys: [String], presentCount: Int)
        /// Two or more of these present together. ↔ `allOf.not.required`.
        case forbidsTogether(keys: [String])
        /// `key` present without its required `needs`. ↔ `dependencies`.
        case dependency(key: String, needs: String)
        /// A `nonEmpty` array-of-tables that is present but empty. ↔ `minItems: 1`.
        case emptyArrayOfTables(key: String)
    }

    /// Location from the document root. Array-of-tables indices appear as
    /// `"[i]"` segments (e.g. `["bindings", "[0]", "input"]`).
    public let path: [String]
    public let rule: Rule
    /// A human-readable one-liner (the app may show it verbatim or re-render
    /// from `rule` + `path`).
    public let message: String

    public init(path: [String], rule: Rule, message: String) {
        self.path = path
        self.rule = rule
        self.message = message
    }

    /// `path` joined for display: `bindings[0].input` (array indices fold onto
    /// the preceding segment; dotted otherwise).
    public var pathString: String {
        var out = ""
        for seg in path {
            if seg.hasPrefix("[") {
                out += seg                       // index folds onto the prior key
            } else if out.isEmpty {
                out = seg
            } else {
                out += "." + seg
            }
        }
        return out
    }
}
