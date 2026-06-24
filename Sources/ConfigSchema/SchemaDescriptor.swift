// SchemaDescriptor.swift — a declarative descriptor of a config.toml INPUT
// surface (the keys a user writes by hand) that carries NO decode logic: it
// only DESCRIBES a surface and emits its schema. "Decode-free" is the contrast
// with this module's `ConfigSchema.Spec<Root>`, which IS generic over a Swift
// `Root` and carries `apply` decode closures. This family is not generic and
// holds each section/key's type / enum domain / range / default / doc AND its
// cross-field rules (required / anyOf / oneOf / forbids / dependency) as PURE,
// IMMUTABLE DATA.
//
// One descriptor is meant to drive THREE consumers:
//
//   • `jsonSchema(options:)` — a Draft-07 JSON Schema for editor completion
//     (taplo), emitted here (this file's sibling, SchemaDescriptorEmit.swift).
//   • a generic runtime validator — run the SAME structural/cross-field rules
//     over a decoded document (future work; the rules are already pure data).
//   • the app's own unknown-key check — `ObjectShape.keySet` is the section's
//     accepted key inventory.
//
// Why a SECOND family alongside `Spec<Root>`: `Spec` models only flat
// scalar/array fields and decodes the family's flat-section dialect. This
// family models the RICHER surface a hand-written imperative-DSL config needs —
// per-enum-value hover, open string/int maps, nested array-of-tables,
// parser-recognised-to-reject keys, and cross-field rules — and does not
// decode. The two coexist; a later step routes `Spec.jsonSchema()` through this
// emitter so there is ONE lowering.
//
// Generalised from chord's in-repo descriptor (chord #138 B): chord proved the
// type shapes against a real, complex config; this is the app-agnostic move
// into sill so facet / wand / perch / halo can share the emit (and, later,
// validate) machinery. App-specific spellings (the vendor-constraints key
// name, slash-escaping, trailing newline) are `EmitOptions` knobs, not baked
// in. Pure / Sendable / Foundation-only (zero AppKit, zero Palette, zero Toml).

import Foundation

// MARK: - Leaf field

/// One scalar / array / map leaf in a config.toml input surface.
public struct SchemaField: Sendable, Equatable {
    public enum Shape: Sendable, Equatable {
        case string                 // plain or free-form DSL string
        case integer
        case boolean
        case stringOrStringArray    // a string OR an array of strings
        case stringArray            // an array of strings
        case constTrue              // a flag whose only meaningful value is `true`
        case intMap                 // open map of name → integer (additionalProperties: integer)
        case stringMap              // open map of name → string (additionalProperties: string)
    }

    public let key: String
    public let shape: Shape
    /// Finite value set → JSON `enum`. nil for free-form / DSL strings.
    public let enumDomain: [String]?
    /// Per-enum-value hover docs, index-aligned to `enumDomain` (a nil entry
    /// skips that value). Emitted as `x-taplo.docs.enumValues` — taplo's
    /// per-value hover, which a single `description` cannot give.
    public let enumDocs: [String?]?
    public let defaultBool: Bool?
    public let defaultInt: Int?
    /// A `> n` lower bound → `exclusiveMinimum`.
    public let exclusiveMinimum: Int?
    public let doc: String
    /// A key the app's PARSER recognises but that is NOT schema-valid — it is
    /// listed only so the unknown-key check (via [ObjectShape.keySet]) does not
    /// mis-report it as a typo, while the EMITTED schema OMITS it so
    /// `additionalProperties: false` keeps rejecting it.
    public let rejected: Bool

    public init(_ key: String, _ shape: Shape, doc: String,
                enumDomain: [String]? = nil, enumDocs: [String?]? = nil,
                defaultBool: Bool? = nil, defaultInt: Int? = nil,
                exclusiveMinimum: Int? = nil, rejected: Bool = false) {
        self.key = key; self.shape = shape; self.doc = doc
        self.enumDomain = enumDomain; self.enumDocs = enumDocs
        self.defaultBool = defaultBool; self.defaultInt = defaultInt
        self.exclusiveMinimum = exclusiveMinimum; self.rejected = rejected
    }
}

// MARK: - Cross-field rules (pure data; lowered to JSON Schema by the emitter,
// and runnable by a future generic validator over a decoded document).

public enum ExclusionRule: Sendable, Equatable {
    /// ≥1 of these keys must be present (a union where members may co-occur —
    /// NOT exactly-one).
    case anyOfRequired([String])
    /// Exactly one of these is present.
    case oneOfRequired([String])
    /// These keys may not all be present together.
    case forbidsTogether([String])
    /// `key` present ⇒ `needs` present.
    case dependency(key: String, needs: String)
}

// MARK: - Object / table shapes

/// A table (or array-of-tables item) shape: its fields, what is required,
/// the cross-field rules, and any nested array-of-tables children.
public struct ObjectShape: Sendable {
    public let fields: [SchemaField]
    public let required: [String]
    public let exclusions: [ExclusionRule]
    public let nested: [NestedTable]
    public let doc: String
    /// Keys taplo pre-inserts when autocompleting a new table of this shape
    /// (`x-taplo.initKeys`) — a curated starter set for array-of-tables items.
    public let initKeys: [String]
    /// Cross-cutting rules the app enforces at load that Draft-07 cannot
    /// express (symbol-table lookups, cross-row uniqueness, reserved names, …).
    /// Emitted as a vendor array under [EmitOptions.constraintsKey] for editor
    /// hover. DISCOVERABILITY only — the app's validator remains the
    /// enforcement authority.
    public let constraints: [String]

    public init(fields: [SchemaField], required: [String] = [],
                exclusions: [ExclusionRule] = [], nested: [NestedTable] = [],
                doc: String = "", initKeys: [String] = [],
                constraints: [String] = []) {
        self.fields = fields; self.required = required
        self.exclusions = exclusions; self.nested = nested; self.doc = doc
        self.initKeys = initKeys; self.constraints = constraints
    }

    /// Every key this object accepts (own fields + nested-table keys) — the
    /// app's unknown-key validation surface and the shape tests' inventory.
    public var keySet: Set<String> {
        Set(fields.map(\.key)).union(nested.map(\.key))
    }
}

/// An array-of-tables child nested inside an [ObjectShape].
public struct NestedTable: Sendable {
    public let key: String          // e.g. "per-app", "bindings"
    public let item: ObjectShape    // the array-of-tables item shape
    /// The parent must declare this table. Pure descriptor data for a future
    /// validator; the EMITTER does NOT consume it (it never auto-adds the key
    /// to the parent's `required`) — to require a nested table in the emitted
    /// schema, list its key in the parent [ObjectShape.required] too.
    public let required: Bool
    public let nonEmpty: Bool       // minItems: 1
    public init(key: String, item: ObjectShape, required: Bool = false,
                nonEmpty: Bool = false) {
        self.key = key; self.item = item; self.required = required
        self.nonEmpty = nonEmpty
    }
}

// MARK: - Sections

/// One top-level `config.toml` section.
public struct SchemaSection: Sendable {
    public enum Kind: Sendable {
        case table(ObjectShape)                                // `[header]`
        case openStringMap(valueDoc: String)                   // open name→string map
        case openIntMap(valueDoc: String, min: Int, max: Int)  // open name→int map
        case arrayOfTables(ObjectShape)                        // `[[header]]`
    }

    public let name: String          // the TOML key: "options", "bindings", …
    public let kind: Kind
    public let doc: String
    public init(_ name: String, _ kind: Kind, doc: String) {
        self.name = name; self.kind = kind; self.doc = doc
    }
}

// MARK: - Root descriptor

/// The whole config.toml input surface: a title, an optional `$comment`, and
/// the ordered sections. The single source the emitter (and, later, a generic
/// validator) consume.
public struct SchemaDescriptor: Sendable {
    public let title: String
    /// Emitted as `$comment` when non-nil (e.g. a "regenerate with …" note).
    public let comment: String?
    public let sections: [SchemaSection]
    public init(title: String, comment: String? = nil, sections: [SchemaSection]) {
        self.title = title; self.comment = comment; self.sections = sections
    }
}
