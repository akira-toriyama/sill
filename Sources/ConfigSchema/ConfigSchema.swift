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
        public var def: DefaultValue?
        public var min: Double?
        public var max: Double?
        public var doc: String?

        public init(
            key: String,
            kind: Kind,
            apply: @escaping (inout Root, Toml.Value) -> Void,
            domain: [String]? = nil,
            def: DefaultValue? = nil,
            min: Double? = nil,
            max: Double? = nil,
            doc: String? = nil
        ) {
            self.key = key
            self.kind = kind
            self.apply = apply
            self.domain = domain
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

/// A mutable object-schema node while folding the spec's (possibly
/// dotted) section headers into a tree. `permissive` flips
/// `additionalProperties` to `true` for dynamic-name tables (custom
/// palettes / per-app overrides / synonym maps) whose keys can't be
/// enumerated; otherwise it stays `false` so taplo flags typo'd keys.
private final class SchemaNode {
    var properties: [String: Any] = [:]   // scalar/array field schemas
    var children: [String: SchemaNode] = [:]
    var description: String?
    var permissive = false
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
    func jsonSchema() -> String {
        let root = SchemaNode()
        for section in sections {
            switch section.kind {
            case .table:
                let node = Self.descend(root, Self.pathComponents(section.header))
                node.description = node.description ?? section.doc
                for field in section.fields {
                    node.properties[field.key] = Self.fieldSchema(field)
                }
            case .arrayOfTables:
                // `[[a.b.name]]` → an array of objects at `a → b → name`.
                let path = Self.pathComponents(section.header)
                guard let last = path.last else { break }
                let parent = Self.descend(root, Array(path.dropLast()))
                var props: [String: Any] = [:]
                for field in section.fields { props[field.key] = Self.fieldSchema(field) }
                var items: [String: Any] = ["type": "object", "additionalProperties": false]
                if !props.isEmpty { items["properties"] = props }
                if let doc = section.doc { items["description"] = doc }
                parent.properties[last] = ["type": "array", "items": items] as [String: Any]
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
        var schema = Self.objectSchema(root)
        schema["$schema"] = "http://json-schema.org/draft-07/schema#"
        schema["title"] = title
        return Self.serialize(schema)
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

    /// Serialize a node to a JSON-Schema object. Child sub-objects merge
    /// into `properties` alongside the node's own scalar fields; an empty
    /// `properties` is omitted (a bare permissive/dynamic object).
    private static func objectSchema(_ node: SchemaNode) -> [String: Any] {
        var props = node.properties
        for (name, child) in node.children { props[name] = objectSchema(child) }
        var obj: [String: Any] = [
            "type": "object",
            "additionalProperties": node.permissive,
        ]
        if !props.isEmpty { obj["properties"] = props }
        if let doc = node.description { obj["description"] = doc }
        return obj
    }

    private static func fieldSchema(_ field: ConfigSchema.Field<Root>) -> [String: Any] {
        var s: [String: Any] = [:]
        switch field.kind {
        case .scalar(let scalar):
            s["type"] = jsonType(scalar)
            if let domain = field.domain { s["enum"] = domain }
            if let lo = field.min { s["minimum"] = lo }
            if let hi = field.max { s["maximum"] = hi }
        case .stringArray(let item):
            s["type"] = "array"
            var items: [String: Any] = ["type": "string"]
            if let item { items["enum"] = item }
            s["items"] = items
        }
        if let def = field.def { s["default"] = defaultJSON(def) }
        if let doc = field.doc { s["description"] = doc }
        return s
    }

    private static func jsonType(_ scalar: ConfigSchema.Scalar) -> String {
        switch scalar {
        case .string:  return "string"
        case .integer: return "integer"
        case .number:  return "number"
        case .boolean: return "boolean"
        }
    }

    private static func defaultJSON(_ def: ConfigSchema.DefaultValue) -> Any {
        switch def {
        case .string(let s):      return s
        case .int(let i):         return i
        case .number(let d):      return d
        case .bool(let b):        return b
        case .stringArray(let a): return a
        }
    }

    private static func serialize(_ root: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text + "\n"
    }
}
