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

public extension ConfigSchema.Spec {
    /// A stable, pretty-printed Draft-07 JSON Schema. Deterministic
    /// (sorted keys) so a committed copy can be drift-checked against this
    /// output in CI. Known sections/keys get type + enum + range + default
    /// + description; `additionalProperties: false` flags typo'd keys in
    /// the editor (the app itself stays lenient at runtime).
    func jsonSchema() -> String {
        var properties: [String: Any] = [:]
        for section in sections {
            switch section.kind {
            case .table where section.header.isEmpty:
                // Top-level scalar keys live directly on the root object.
                for field in section.fields {
                    properties[field.key] = Self.fieldSchema(field)
                }
            case .table:
                properties[section.header] = Self.objectSchema(section)
            case .arrayOfTables:
                properties[section.header] = [
                    "type": "array",
                    "items": Self.objectSchema(section),
                ] as [String: Any]
            case .dynamicTable:
                // Permissive: allow `[header.*]` without enumerating the
                // dynamic names, so top-level strictness doesn't reject it.
                var obj: [String: Any] = ["type": "object", "additionalProperties": true]
                if let doc = section.doc { obj["description"] = doc }
                properties[section.header] = obj
            }
        }
        let root: [String: Any] = [
            "$schema": "http://json-schema.org/draft-07/schema#",
            "title": title,
            "type": "object",
            "properties": properties,
            "additionalProperties": false,
        ]
        return Self.serialize(root)
    }

    private static func objectSchema(_ section: ConfigSchema.Section<Root>) -> [String: Any] {
        var props: [String: Any] = [:]
        for field in section.fields { props[field.key] = fieldSchema(field) }
        var obj: [String: Any] = [
            "type": "object",
            "properties": props,
            "additionalProperties": false,
        ]
        if let doc = section.doc { obj["description"] = doc }
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
