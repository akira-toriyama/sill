// ConfigSchema — one declarative source that BOTH decodes a config and
// emits its JSON Schema.
//
// The atelier family's apps each ship a `config.toml` the user edits by
// hand. Phase 1.6 already gave them ONE parser (`Toml`); this module is
// the next step: a declarative `Spec<Root>` that maps TOML sections/keys
// onto a Swift config struct AND knows each key's type / enum domain /
// range / default / doc — so the SAME spec drives
//
//   • `decode(_:into:)`     — populate the struct from `Toml.parseFlat`
//   • `jsonSchema()`        — emit a Draft-07 JSON Schema for taplo
//
// One source ⇒ the schema can never drift from the decode: add a key in
// the spec and both the parse and the editor-completion schema gain it.
//
// Pure / Sendable / Foundation-only, depending ONLY on `Toml` (zero
// AppKit, zero Palette) — a third pure atom alongside `Palette` and
// `Toml`. Enum DOMAINS (theme / effect names, app-local enums) are passed
// IN by the consuming app, so this module stays theming-agnostic.
//
// Scope (the family's flat-section dialect): a `.table` section is one
// `[header]` whose fields are scalars or string arrays; `.arrayOfTables`
// is `[[header]]` (schema: an array of objects); `.dynamicTable` is a
// permissive object for dynamic section names (e.g. facet's `[desktop.N]`).
// `decode` drives ONLY `.table` sections (the uniform bulk) — an app keeps
// its own bespoke decode for arrays-of-tables / dynamic sections, which
// the spec still DESCRIBES for the schema.
//
// A SECOND, decode-free type family lives alongside `Spec<Root>` in this
// module (SchemaDescriptor.swift): `SchemaDescriptor` / `SchemaSection` /
// `ObjectShape` / `SchemaField` / `ExclusionRule`. It models the RICHER input
// surface a hand-written imperative-DSL config needs (per-enum-value hover,
// open maps, nested arrays-of-tables, cross-field rules) and EMITS + VALIDATES
// (Validator.swift) — it does not decode. Since #138 S3 there is ONE lowering:
// `Spec.jsonSchema()` folds its dotted-header section tree into that family's
// `ObjectShape` vocabulary and emits through the shared `SchemaEmit` emitter.

import Foundation
import Toml

public enum ConfigSchema {

    /// JSON-Schema scalar types we emit (the family's config grammar).
    public enum Scalar: Sendable, Equatable {
        case string, integer, number, boolean
    }

    /// The shape of one config key.
    public enum Kind: Sendable, Equatable {
        case scalar(Scalar)
        /// A TOML array of strings; `item` is the optional enum domain
        /// applied to each element (e.g. `canonicalLinePetNames`).
        case stringArray(item: [String]?)
    }

    /// A schema `default` (shown by the editor; purely descriptive — the
    /// real default lives in the app's `effective*` accessor).
    public enum DefaultValue: Sendable, Equatable {
        case string(String)
        case int(Int)
        case number(Double)
        case bool(Bool)
        case stringArray([String])
    }

    /// One config key: how to DECODE it (`apply`) and how to DESCRIBE it
    /// (everything else). `apply` reads the already-parsed `Toml.Value`
    /// (only when the key is present) and writes the typed field — the
    /// app supplies the closure (so type coercions like Int→CGFloat stay
    /// in the app and this module needs no CoreGraphics).
    ///
    /// Not `Sendable`: the `apply` closure captures a `WritableKeyPath`
    /// (not `Sendable`), and a spec is a deeply-immutable value built &
    /// used synchronously (consumers expose it as a computed property, not
    /// shared mutable state), so Sendability buys nothing here.
    public struct Field<Root> {
        public let key: String
        public let kind: Kind
        public let apply: (inout Root, Toml.Value) -> Void
        public var domain: [String]?        // enum values for a string scalar
        /// Per-enum-value hover docs, index-aligned to `domain` (a nil entry
        /// skips that value) → taplo's `x-taplo.docs.enumValues`, the per-value
        /// hover a single `description` can't give. Only meaningful with `domain`.
        public var enumDocs: [String?]?
        public var def: DefaultValue?
        public var min: Double?
        public var max: Double?
        public var doc: String?

        public init(
            key: String,
            kind: Kind,
            apply: @escaping (inout Root, Toml.Value) -> Void,
            domain: [String]? = nil,
            enumDocs: [String?]? = nil,
            def: DefaultValue? = nil,
            min: Double? = nil,
            max: Double? = nil,
            doc: String? = nil
        ) {
            self.key = key
            self.kind = kind
            self.apply = apply
            self.domain = domain
            self.enumDocs = enumDocs
            self.def = def
            self.min = min
            self.max = max
            self.doc = doc
        }
    }

    public enum SectionKind: Sendable, Equatable {
        /// `[header]` (or the top-level scope when `header == ""`). Decoded.
        case table
        /// `[[header]]` — schema is an array of objects. NOT decoded here.
        case arrayOfTables
        /// Dynamic section names under `header` (e.g. `[desktop.1]`,
        /// `[desktop.2]`). Schema is a permissive object; NOT decoded here.
        case dynamicTable
    }

    public struct Section<Root> {
        public let header: String         // "theme", "grid", … ("" = root)
        public let kind: SectionKind
        public var fields: [Field<Root>]
        public var doc: String?
        public init(
            _ header: String,
            kind: SectionKind = .table,
            doc: String? = nil,
            fields: [Field<Root>] = []
        ) {
            self.header = header
            self.kind = kind
            self.doc = doc
            self.fields = fields
        }
    }

    public struct Spec<Root> {
        public let title: String
        public let sections: [Section<Root>]
        public init(title: String, sections: [Section<Root>]) {
            self.title = title
            self.sections = sections
        }
    }
}

// MARK: - Decode (drives the app's `from(toml:)`)

public extension ConfigSchema.Spec {
    /// Populate `root` from the FLAT `tables` map (`Toml.parseFlat(_).tables`,
    /// keyed by literal header text — `""` = top level). Drives every
    /// `.table` section; a field is applied only when its key is present
    /// (so a missing key leaves the struct's Optional untouched — identical
    /// to the hand-written `if case .x? = toml[…]` idiom). `.arrayOfTables`
    /// / `.dynamicTable` sections are skipped (the app decodes those).
    func decode(_ tables: [String: [String: Toml.Value]], into root: inout Root) {
        for section in sections {
            guard section.kind == .table,
                  let table = tables[section.header] else { continue }
            for field in section.fields {
                if let value = table[field.key] {
                    field.apply(&root, value)
                }
            }
        }
    }
}

// MARK: - JSON Schema emission (drives `--emit-schema`)

/// A mutable node while folding the spec's (possibly dotted) section
/// headers into a tree. The fold builds typed leaves (`fields` / `arrays` /
/// child `children`) which are then converted to an `ObjectShape` tree and
/// lowered through the SHARED `SchemaEmit` emitter — so `Spec` and
/// `SchemaDescriptor` share ONE field/object lowering (ConfigSchema #138 S3).
/// `permissive` flips `additionalProperties` to `true` for dynamic-name tables
/// (custom palettes / per-app overrides / synonym maps) whose keys can't be
/// enumerated; otherwise it stays `false` so taplo flags typo'd keys.
private final class SchemaNode {
    var fields: [SchemaField] = []                          // scalar / array leaves
    var arrays: [(key: String, item: ObjectShape)] = []     // `[[header]]` children
    var children: [String: SchemaNode] = [:]                // nested object sub-tables
    var description: String?
    var permissive = false

    /// Fold this node into the shared `ObjectShape` vocabulary. Child sub-tables
    /// become nested objects and array-of-tables become nested tables; both
    /// land in `properties` alongside this node's own scalar fields when
    /// `SchemaEmit.emitObject` lowers the result.
    func toObjectShape() -> ObjectShape {
        ObjectShape(
            fields: fields,
            nested: arrays.map { NestedTable(key: $0.key, item: $0.item) },
            objects: children.map { NestedObject(key: $0.key, shape: $0.value.toObjectShape()) },
            doc: description ?? "",
            permissive: permissive)
    }
}

public extension ConfigSchema.Spec {
    /// A stable, pretty-printed Draft-07 JSON Schema. Deterministic
    /// (sorted keys) so a committed copy can be drift-checked against this
    /// output in CI. Known sections/keys get type + enum + range + default
    /// + description; `additionalProperties: false` flags typo'd keys.
    ///
    /// Section headers fold into a NESTED object tree on `.` — so a flat
    /// `Toml.parseFlat` header like `cast.overlay.trail` (what `decode`
    /// reads) becomes the `cast → overlay → trail` object tree that taplo
    /// validates the raw TOML against. Single-segment headers (no dot)
    /// stay top-level, byte-identical to a flat emission. A section's own
    /// leaf keys merge with its nested children (e.g. `[cast]` scalars +
    /// `[cast.overlay]`). One source (`sections`) ⇒ schema can't drift
    /// from the decode.
    ///
    /// The fold builds an `ObjectShape` tree and lowers it through the shared
    /// `SchemaEmit` emitter (the same one `SchemaDescriptor` uses), so the
    /// JSON-shape rules live in ONE place. Output spelling matches the historic
    /// `Spec` emission byte-for-byte (bare slashes + a trailing newline), with
    /// ONE deliberate normalization: an EXPLICIT empty-string `doc` ("") is now
    /// treated like an absent doc and OMITS `description` — where the old
    /// lowering emitted `"description": ""`. No real spec passes `doc: ""` (the
    /// field/section builders default it to nil), and an empty description is
    /// noise; the shared `doc: String` ("" = none) is not widened to `Optional`
    /// just to reproduce that wart. See SpecEmitLoweringTests.
    func jsonSchema() -> String {
        let options = SchemaDescriptor.EmitOptions(escapeSlashes: false, trailingNewline: true)
        // The root carries the top-level `Section("")` doc (if any) on its own
        // shape — pass it as the root's sectionDoc so a documented top-level
        // scope keeps its `description` (emitObject reads the parameter, not
        // shape.doc, for the object's own description).
        let rootShape = foldedRoot().toObjectShape()
        var schema = SchemaEmit.emitObject(rootShape, sectionDoc: rootShape.doc, options)
        schema["$schema"] = "http://json-schema.org/draft-07/schema#"
        schema["title"] = title
        return SchemaEmit.serialize(schema, options)
    }

    /// Fold the (possibly dotted) section headers into the shared `SchemaNode`
    /// tree. The ONE fold consumed by BOTH `jsonSchema()` (→ `ObjectShape` →
    /// Draft-07) and `makeDescriptor()` (→ `SchemaDescriptor` → runtime
    /// validate), so emit and validate can't drift from the single `sections`
    /// source (ConfigSchema #138 — the validation half of S3's single-source
    /// promise).
    private func foldedRoot() -> SchemaNode {
        let root = SchemaNode()
        for section in sections {
            switch section.kind {
            case .table:
                let node = Self.descend(root, Self.pathComponents(section.header))
                node.description = node.description ?? section.doc
                node.fields.append(contentsOf: section.fields.map(Self.schemaField))
            case .arrayOfTables:
                // `[[a.b.name]]` → an array of objects at `a → b → name`. The
                // section doc rides the ITEM (not the array node) — the shared
                // NestedTable convention, matching the historic Spec emission.
                let path = Self.pathComponents(section.header)
                guard let last = path.last else { break }
                let parent = Self.descend(root, Array(path.dropLast()))
                let item = ObjectShape(fields: section.fields.map(Self.schemaField),
                                       doc: section.doc ?? "")
                parent.arrays.append((key: last, item: item))
            case .dynamicTable:
                if section.header.contains("\"") {
                    // A literal-quote header (`behavior."<bundle-id>"`) marks
                    // its PARENT table as accepting arbitrary sub-tables —
                    // fold permissive onto the parent, not a `"<id>"` child.
                    let parent = String(section.header.prefix { $0 != "." })
                    let node = Self.descend(root, parent.isEmpty ? [] : [parent])
                    node.permissive = true
                    if let doc = section.doc { node.description = doc }
                } else {
                    // A named dynamic sub-table (`overlay.themes`,
                    // `search.synonyms`, facet's `desktop`): permissive object.
                    let node = Self.descend(root, Self.pathComponents(section.header))
                    node.permissive = true
                    node.description = section.doc ?? node.description
                }
            }
        }
        return root
    }
}

// MARK: - Runtime validate (drives the app's `config --validate`)

public extension ConfigSchema.Spec {
    /// Lower this spec to a decode-free [SchemaDescriptor] — the surface the
    /// generic runtime validator (`SchemaDescriptor.validate`) and the JSON
    /// emitter both consume. Built from the SAME `foldedRoot()` fold as
    /// `jsonSchema()`, so the schema taplo checks and the rules the loader
    /// enforces are one source: "editor green" and "loader accepts it" cannot
    /// diverge.
    ///
    /// Each top-level folded node becomes a `[header]` table section; a
    /// top-level `[[header]]` becomes an array-of-tables section. Nested dotted
    /// children (`[cast.overlay]`, `[[cast.cursor.rule]]`) ride inside their
    /// parent section's `ObjectShape` (objects / nested), matching the NESTED
    /// `Toml.parse` document the validator walks. `.dynamicTable` sections fold
    /// to `permissive` object shapes (arbitrary keys accepted) — the same
    /// `additionalProperties: true` the emitter produces.
    ///
    /// Section order is by key (deterministic); the validator is
    /// order-independent. Top-level bare scalar keys (a `Section("")` with
    /// fields) are NOT represented — the validator walks named sections only.
    /// No family spec currently uses a bare top-level field.
    func makeDescriptor() -> SchemaDescriptor {
        let root = foldedRoot()
        var sections: [SchemaSection] = []
        for (name, node) in root.children.sorted(by: { $0.key < $1.key }) {
            sections.append(SchemaSection(name, .table(node.toObjectShape()),
                                          doc: node.description ?? ""))
        }
        for (key, item) in root.arrays {
            sections.append(SchemaSection(key, .arrayOfTables(item), doc: item.doc))
        }
        return SchemaDescriptor(title: title, sections: sections)
    }

    /// Validate a decoded NESTED config document (`Toml.parse(_).` root, NOT
    /// the flat `parseFlat` map `decode` reads) against this spec's structural +
    /// cross-field rules. Convenience for `makeDescriptor().validate(root)` so a
    /// consumer's `config --validate` is one call on the same `configSpec` it
    /// already uses for decode + emit. Returns every violation (does not stop at
    /// the first); an empty array means structurally valid.
    func validate(_ root: [String: Toml.Value]) -> [ValidationError] {
        makeDescriptor().validate(root)
    }

    /// Split a (possibly dotted) section header into path components.
    /// `""` → `[]` (the root scope); `"overlay.effect"` → `["overlay",
    /// "effect"]`. Quote-bearing dynamic headers are handled before this.
    private static func pathComponents(_ header: String) -> [String] {
        header.split(separator: ".").map(String.init)
    }

    /// Walk (creating as needed) child nodes down `path`, returning the
    /// leaf node. An empty path returns `root`.
    private static func descend(_ root: SchemaNode, _ path: [String]) -> SchemaNode {
        var cur = root
        for name in path {
            if let next = cur.children[name] {
                cur = next
            } else {
                let next = SchemaNode()
                cur.children[name] = next
                cur = next
            }
        }
        return cur
    }

    /// Convert a decode-bearing `Spec.Field` into the decode-free `SchemaField`
    /// the shared emitter consumes. `apply` is dropped (emission ignores it);
    /// type / enum / range / default / doc carry over so the output is identical
    /// to the historic per-field lowering.
    private static func schemaField(_ field: ConfigSchema.Field<Root>) -> SchemaField {
        let shape: SchemaField.Shape
        var itemEnum: [String]?
        // Scalar-only metadata. The historic `fieldSchema` emitted `enum` /
        // `minimum` / `maximum` ONLY in the `.scalar` branch, so a `.stringArray`
        // field's stray `domain` / `min` / `max` was dropped (the element enum
        // rides `.stringArray(item:)` instead). Gate them on the kind to keep
        // that exact contract; `enumDocs` pairs with the scalar enum, so it
        // follows the same gate.
        var domain: [String]?
        var enumDocs: [String?]?
        var minimum: Double?
        var maximum: Double?
        switch field.kind {
        case .scalar(let scalar):
            switch scalar {
            case .string:  shape = .string
            case .integer: shape = .integer
            case .number:  shape = .number
            case .boolean: shape = .boolean
            }
            domain = field.domain
            enumDocs = field.enumDocs
            minimum = field.min
            maximum = field.max
        case .stringArray(let item):
            shape = .stringArray
            itemEnum = item
        }
        // `default` and `doc` carried for BOTH kinds (matching the historic
        // lowering). Map the descriptive default onto its typed slot purely by
        // the DefaultValue case, mirroring the old `defaultJSON` switch.
        var defBool: Bool?; var defInt: Int?; var defString: String?
        var defNumber: Double?; var defStringArray: [String]?
        switch field.def {
        case .bool(let b):        defBool = b
        case .int(let i):         defInt = i
        case .string(let s):      defString = s
        case .number(let d):      defNumber = d
        case .stringArray(let a): defStringArray = a
        case nil:                 break
        }
        return SchemaField(
            field.key, shape, doc: field.doc ?? "",
            enumDomain: domain, enumDocs: enumDocs,
            arrayItemEnum: itemEnum,
            defaultBool: defBool, defaultInt: defInt, defaultString: defString,
            defaultNumber: defNumber, defaultStringArray: defStringArray,
            minimum: minimum, maximum: maximum)
    }
}
