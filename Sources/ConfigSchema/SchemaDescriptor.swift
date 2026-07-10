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
//     over a decoded document (`SchemaDescriptor.validate`, Validator.swift) so
//     "editor green" and "loader accepts it" cannot diverge.
//   • the app's own unknown-key check — `ObjectShape.keySet` is the section's
//     accepted key inventory.
//
// Why a SECOND family alongside `Spec<Root>`: `Spec` decodes the family's
// flat-section dialect AND emits; this family models the RICHER surface a
// hand-written imperative-DSL config needs — per-enum-value hover, open
// string/int maps, nested array-of-tables, parser-recognised-to-reject keys,
// and cross-field rules — and does not decode. Since #138 S3 the two share ONE
// lowering: `Spec.jsonSchema()` folds its dotted-header section tree into the
// `ObjectShape` vocabulary here (`objects` = nested single objects, `permissive`
// = dynamic-name tables) and emits through the same `SchemaEmit` primitives.
//
// Generalised from chord's in-repo descriptor (chord #138 B): chord proved the
// type shapes against a real, complex config; this is the app-agnostic move
// into sill so facet / wand / perch / halo can share the emit + validate
// machinery. App-specific spellings (the vendor-constraints key
// name, slash-escaping, trailing newline) are `EmitOptions` knobs, not baked
// in. Pure / Sendable / Foundation-only (zero AppKit, zero Palette, zero Toml).

import Foundation

// MARK: - Leaf field

/// One scalar / array / map leaf in a config.toml input surface.
public struct SchemaField: Sendable, Equatable {
    public enum Shape: Sendable, Equatable {
        case string                 // plain or free-form DSL string
        case integer
        case number                 // a floating-point scalar (JSON `number`)
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
    /// For a `.stringArray`, a finite value set applied to each ELEMENT →
    /// `items.enum`. nil = free-form string elements.
    public let arrayItemEnum: [String]?
    public let defaultBool: Bool?
    public let defaultInt: Int?
    public let defaultString: String?
    public let defaultNumber: Double?
    public let defaultStringArray: [String]?
    /// A `> n` lower bound → `exclusiveMinimum`.
    public let exclusiveMinimum: Int?
    /// Inclusive bounds → `minimum` / `maximum`. Carried as `Double` (the
    /// JSON-number domain): a whole bound on an `.integer` still serialises as
    /// `30`, a fractional one on a `.number` as `0.5` — JSONSerialization picks
    /// the shortest round-trippable form.
    public let minimum: Double?
    public let maximum: Double?
    public let doc: String
    /// A key the app's PARSER recognises but that is NOT schema-valid — it is
    /// listed only so the unknown-key check (via [ObjectShape.keySet]) does not
    /// mis-report it as a typo, while the EMITTED schema OMITS it so
    /// `additionalProperties: false` keeps rejecting it.
    public let rejected: Bool

    public init(_ key: String, _ shape: Shape, doc: String,
                enumDomain: [String]? = nil, enumDocs: [String?]? = nil,
                arrayItemEnum: [String]? = nil,
                defaultBool: Bool? = nil, defaultInt: Int? = nil,
                defaultString: String? = nil, defaultNumber: Double? = nil,
                defaultStringArray: [String]? = nil,
                exclusiveMinimum: Int? = nil,
                minimum: Double? = nil, maximum: Double? = nil,
                rejected: Bool = false) {
        self.key = key; self.shape = shape; self.doc = doc
        self.enumDomain = enumDomain; self.enumDocs = enumDocs
        self.arrayItemEnum = arrayItemEnum
        self.defaultBool = defaultBool; self.defaultInt = defaultInt
        self.defaultString = defaultString; self.defaultNumber = defaultNumber
        self.defaultStringArray = defaultStringArray
        self.exclusiveMinimum = exclusiveMinimum
        self.minimum = minimum; self.maximum = maximum
        self.rejected = rejected
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

// MARK: - Dynamic (open-map) value

/// An OPEN map of dynamic keys → a typed value shape, for a table whose key
/// NAMES can't be enumerated but whose VALUES all share one schema
/// (facet's `[desktop.<N>]`: ordinal keys, each a `{ section[], tab[] }`;
/// perch's `[search.synonyms]`: word keys, each an array of strings).
/// Additive over [ObjectShape.permissive]: when an object carries a
/// `dynamicValue` it WINS over `permissive` — the emitter lowers the value
/// schema (not a bare `true`) and the validator recurses into it.
///
/// - `keyPattern`: a JSON-Schema regex the keys must match → `patternProperties`
///   keyed by it, with `additionalProperties: false` (so a key that does NOT
///   match is rejected, e.g. `[desktop.foo]`). `nil` = accept any key name →
///   `additionalProperties: <value schema>` (typed values, unconstrained keys).
/// - values are sub-tables (`shape`) or one LEAF field (`leaf`) — see the inits.
public struct DynamicValue: Sendable {
    public let keyPattern: String?
    /// Boxed so the `ObjectShape` ⇄ `DynamicValue` value-type recursion has a
    /// finite size (a Swift struct can't be `indirect`; the rest of this family
    /// breaks the same cycle with array-backed `nested` / `objects`).
    private let _shape: ShapeBox
    public var shape: ObjectShape { _shape.shape }
    /// When non-nil the map's values are one LEAF field (scalar / array), not
    /// sub-tables: the emitter lowers the FIELD schema as the value schema and
    /// the validator runs the field check with each dynamic key substituted as
    /// the field's key (so paths read `search.synonyms.close[1]`). `shape` then
    /// holds an empty placeholder — kept non-optional so existing object-valued
    /// call sites stay source-compatible.
    public let leaf: SchemaField?

    /// An open map whose values are sub-tables sharing one object schema.
    public init(keyPattern: String? = nil, shape: ObjectShape) {
        self.keyPattern = keyPattern
        self._shape = ShapeBox(shape)
        self.leaf = nil
    }

    /// An open map whose values are one LEAF field shape — e.g. perch's
    /// `[search.synonyms]` word → array-of-strings. The field's own `key` is a
    /// placeholder (pick a doc-friendly one like `"<word>"`); its `doc` becomes
    /// the value schema's `description`.
    public init(keyPattern: String? = nil, leaf: SchemaField) {
        self.keyPattern = keyPattern
        self._shape = ShapeBox(ObjectShape(fields: []))
        self.leaf = leaf
    }
}

/// Heap box breaking the recursive value-type size of [DynamicValue.shape].
private final class ShapeBox: Sendable {
    let shape: ObjectShape
    init(_ shape: ObjectShape) { self.shape = shape }
}

// MARK: - Object / table shapes

/// A table (or array-of-tables item) shape: its fields, what is required,
/// the cross-field rules, and any nested array-of-tables children.
public struct ObjectShape: Sendable {
    public let fields: [SchemaField]
    public let required: [String]
    public let exclusions: [ExclusionRule]
    public let nested: [NestedTable]
    /// Nested SINGLE-object children (one `[parent.child]` sub-table, not an
    /// array-of-tables) → an object property. The representation a dotted-header
    /// section tree folds into (`[cast.overlay]` → a `cast` shape with an
    /// `overlay` object); empty for the flat array-of-tables surface.
    public let objects: [NestedObject]
    public let doc: String
    /// `additionalProperties` policy. `false` (default) = a strict table that
    /// rejects typo'd keys; `true` = a permissive object for dynamic key names
    /// that can't be enumerated (custom palettes, per-app overrides, the
    /// `[desktop.N]` dialect). NOTE: the typed open-map sections
    /// (`openStringMap` / `openIntMap`) carry their own value schema and do not
    /// use this flag.
    public let permissive: Bool
    /// Keys taplo pre-inserts when autocompleting a new table of this shape
    /// (`x-taplo.initKeys`) — a curated starter set for array-of-tables items.
    public let initKeys: [String]
    /// Cross-cutting rules the app enforces at load that Draft-07 cannot
    /// express (symbol-table lookups, cross-row uniqueness, reserved names, …).
    /// Emitted as a vendor array under [EmitOptions.constraintsKey] for editor
    /// hover. DISCOVERABILITY only — the app's validator remains the
    /// enforcement authority.
    public let constraints: [String]
    /// An open-map value schema for dynamic key names (see [DynamicValue]).
    /// When non-nil it OVERRIDES `permissive`: the emitter lowers the value
    /// `shape` under `patternProperties` / `additionalProperties` and the
    /// validator recurses into it instead of accepting any value.
    public let dynamicValue: DynamicValue?

    public init(fields: [SchemaField], required: [String] = [],
                exclusions: [ExclusionRule] = [], nested: [NestedTable] = [],
                objects: [NestedObject] = [], doc: String = "",
                permissive: Bool = false, initKeys: [String] = [],
                constraints: [String] = [], dynamicValue: DynamicValue? = nil) {
        self.fields = fields; self.required = required
        self.exclusions = exclusions; self.nested = nested
        self.objects = objects; self.doc = doc; self.permissive = permissive
        self.initKeys = initKeys; self.constraints = constraints
        self.dynamicValue = dynamicValue
    }

    /// Every key this object accepts (own fields + nested-table + nested-object
    /// keys) — the app's unknown-key validation surface and the shape tests'
    /// inventory.
    public var keySet: Set<String> {
        Set(fields.map(\.key))
            .union(nested.map(\.key))
            .union(objects.map(\.key))
    }
}

/// A single-object child nested inside an [ObjectShape] — the schema for one
/// `[parent.child]` sub-table (vs [NestedTable]'s `[[parent.child]]` array).
/// The child's `description` comes from its own [ObjectShape.doc].
public struct NestedObject: Sendable {
    public let key: String          // e.g. "overlay", "cursor"
    public let shape: ObjectShape
    public init(key: String, shape: ObjectShape) {
        self.key = key; self.shape = shape
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
/// the ordered sections. The single source the emitter and the generic
/// validator (Validator.swift) consume.
public struct SchemaDescriptor: Sendable {
    public let title: String
    /// Emitted as `$comment` when non-nil (e.g. a "regenerate with …" note).
    public let comment: String?
    public let sections: [SchemaSection]
    public init(title: String, comment: String? = nil, sections: [SchemaSection]) {
        self.title = title; self.comment = comment; self.sections = sections
    }
}
