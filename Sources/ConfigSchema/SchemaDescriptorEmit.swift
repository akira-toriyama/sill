// SchemaDescriptorEmit.swift — lower a config-surface model to a Draft-07 JSON
// Schema string for editor completion (taplo).
//
// THE ONE LOWERING. Both config-surface front-ends in this module emit through
// the `SchemaEmit` primitives here:
//
//   • `SchemaDescriptor` (the decode-free, cross-field-rule-bearing surface) —
//     `SchemaDescriptor.jsonSchema(options:)` below.
//   • `ConfigSchema.Spec<Root>` (the decode + emit surface) — its
//     `jsonSchema()` folds dotted headers into an `ObjectShape` tree and emits
//     it through these same `SchemaEmit.emitObject` / `.serialize` calls, so a
//     field/object lowering change lands in ONE place (ConfigSchema #138 S3).
//
// Deterministic: built with `JSONSerialization [.sortedKeys, .prettyPrinted]`
// so a freshly emitted string is byte-stable across runs/platforms — a CI
// drift guard (committed schema == emitted) can rely on it.
//
// App-agnostic. Spellings that differ between apps are `EmitOptions` knobs:
//   • `escapeSlashes`   — JSONSerialization escapes `/` → `\/` by default;
//                         pass `false` to emit bare slashes.
//   • `trailingNewline` — append a final `\n` (POSIX-text style) or not.
//   • `constraintsKey`  — the vendor key an [ObjectShape.constraints] array is
//                         emitted under (e.g. `x-chord-constraints`).
// `x-taplo` (enumValues hover, initKeys) is taplo's own universal vendor
// extension, so it is fixed.

import Foundation

public extension SchemaDescriptor {

    /// Knobs for app-specific output spelling. The defaults match the
    /// JSONSerialization baseline (slashes escaped, no trailing newline) so a
    /// caller that wants that byte shape can omit the argument.
    struct EmitOptions: Sendable {
        public var escapeSlashes: Bool
        public var trailingNewline: Bool
        /// The JSON-Schema vendor key the [ObjectShape.constraints] array is
        /// emitted under. Convention: `x-<app>-constraints` (e.g.
        /// `x-chord-constraints`) so the key never collides with another
        /// vendor's extension. The generic default `"x-constraints"` is a
        /// fallback; an app with constraints should override it.
        public var constraintsKey: String
        public init(escapeSlashes: Bool = true,
                    trailingNewline: Bool = false,
                    constraintsKey: String = "x-constraints") {
            self.escapeSlashes = escapeSlashes
            self.trailingNewline = trailingNewline
            self.constraintsKey = constraintsKey
        }
    }

    /// The emitted Draft-07 JSON Schema for this descriptor.
    func jsonSchema(options: EmitOptions = EmitOptions()) -> String {
        var root: [String: Any] = [
            "$schema": "http://json-schema.org/draft-07/schema#",
            "title": title,
            "type": "object",
            "additionalProperties": false,
        ]
        if let comment { root["$comment"] = comment }
        var props: [String: Any] = [:]
        for section in sections {
            props[section.name] = SchemaEmit.emitSection(section, options)
        }
        root["properties"] = props
        return SchemaEmit.serialize(root, options)
    }
}

// MARK: - The shared lowering (model → Draft-07 dict → string)

/// The single field/object/serialize lowering shared by both `SchemaDescriptor`
/// and `ConfigSchema.Spec`. Internal: the public entry points are the two
/// `jsonSchema(…)` methods; these are their common machinery.
enum SchemaEmit {

    typealias EmitOptions = SchemaDescriptor.EmitOptions

    static func emitSection(_ s: SchemaSection, _ options: EmitOptions) -> [String: Any] {
        switch s.kind {
        case .table(let shape):
            return emitObject(shape, sectionDoc: s.doc, options)
        case .openStringMap(let valueDoc):
            return [
                "type": "object",
                "description": s.doc,
                "additionalProperties": ["type": "string", "description": valueDoc],
            ]
        case .openIntMap(let valueDoc, let min, let max):
            return [
                "type": "object",
                "description": s.doc,
                "additionalProperties": ["type": "integer", "description": valueDoc,
                                         "minimum": min, "maximum": max],
            ]
        case .arrayOfTables(let shape):
            return [
                "type": "array",
                "description": s.doc,
                "items": emitObject(shape, sectionDoc: shape.doc, options),
            ]
        }
    }

    static func emitObject(_ shape: ObjectShape, sectionDoc: String,
                           _ options: EmitOptions) -> [String: Any] {
        var obj: [String: Any] = ["type": "object"]
        if let dv = shape.dynamicValue {
            // Open map of dynamic keys → a typed value schema (wins over
            // `permissive`). A key pattern → `patternProperties` keyed by it with
            // `additionalProperties: false` (non-matching keys rejected); no
            // pattern → the value schema IS `additionalProperties` (any key).
            // A `leaf` value lowers the FIELD schema; otherwise the object shape.
            let valueSchema = dv.leaf.map { emitField($0) }
                ?? emitObject(dv.shape, sectionDoc: dv.shape.doc, options)
            if let pattern = dv.keyPattern {
                obj["patternProperties"] = [pattern: valueSchema]
                obj["additionalProperties"] = false
            } else {
                obj["additionalProperties"] = valueSchema
            }
        } else {
            // false = strict (reject typo'd keys); true = permissive (dynamic
            // key names the schema can't enumerate).
            obj["additionalProperties"] = shape.permissive
        }
        if !sectionDoc.isEmpty { obj["description"] = sectionDoc }

        var props: [String: Any] = [:]
        // `rejected` fields are parser-recognised-to-reject, not schema-valid;
        // omit them so `additionalProperties: false` keeps rejecting them.
        for f in shape.fields where !f.rejected { props[f.key] = emitField(f) }
        for n in shape.nested {
            var arr: [String: Any] = ["type": "array",
                                      "items": emitObject(n.item, sectionDoc: n.item.doc, options)]
            if n.nonEmpty { arr["minItems"] = 1 }
            props[n.key] = arr
        }
        // Nested SINGLE objects (dotted-header folding): each is its own
        // strict/permissive object, described by its shape's own doc.
        for o in shape.objects {
            props[o.key] = emitObject(o.shape, sectionDoc: o.shape.doc, options)
        }
        // A bare permissive object (dynamic key names, no enumerable keys) has
        // no `properties`; omit the empty map rather than emit `{}`.
        if !props.isEmpty { obj["properties"] = props }

        if !shape.required.isEmpty { obj["required"] = shape.required }

        // dependency rules → Draft-07 `dependencies`
        var deps: [String: Any] = [:]
        for rule in shape.exclusions {
            if case .dependency(let key, let needs) = rule { deps[key] = [needs] }
        }
        if !deps.isEmpty { obj["dependencies"] = deps }

        // anyOf / oneOf / not rules → `allOf` of small clauses
        var allOf: [[String: Any]] = []
        for rule in shape.exclusions {
            switch rule {
            case .anyOfRequired(let keys):
                allOf.append(["anyOf": keys.map { ["required": [$0]] }])
            case .oneOfRequired(let keys):
                allOf.append(["oneOf": keys.map { ["required": [$0]] }])
            case .forbidsTogether(let keys):
                allOf.append(["not": ["required": keys]])
            case .dependency:
                break // handled above
            }
        }
        if !allOf.isEmpty { obj["allOf"] = allOf }

        // taplo autocompletion pre-fill for a new table of this shape.
        if !shape.initKeys.isEmpty { obj["x-taplo"] = ["initKeys": shape.initKeys] }
        // Runtime-only rules the app enforces that Draft-07 can't express —
        // editor hover discoverability only (not enforcement). The vendor key
        // name is app-chosen (chord: `x-chord-constraints`).
        if !shape.constraints.isEmpty { obj[options.constraintsKey] = shape.constraints }

        return obj
    }

    static func emitField(_ f: SchemaField) -> [String: Any] {
        var out: [String: Any] = [:]
        switch f.shape {
        case .string:
            out["type"] = "string"
        case .integer:
            out["type"] = "integer"
        case .number:
            out["type"] = "number"
        case .boolean:
            out["type"] = "boolean"
        case .stringOrStringArray:
            out["oneOf"] = [["type": "string"], ["type": "array", "items": ["type": "string"]]]
        case .stringArray:
            out["type"] = "array"
            var items: [String: Any] = ["type": "string"]
            if let e = f.arrayItemEnum { items["enum"] = e }
            out["items"] = items
        case .constTrue:
            out["const"] = true
        case .intMap:
            out["type"] = "object"
            out["additionalProperties"] = ["type": "integer"]
            out["minProperties"] = 1
        case .stringMap:
            out["type"] = "object"
            out["additionalProperties"] = ["type": "string"]
        }
        if let e = f.enumDomain { out["enum"] = e }
        if let d = f.defaultBool { out["default"] = d }
        if let d = f.defaultInt { out["default"] = d }
        if let d = f.defaultString { out["default"] = d }
        if let d = f.defaultNumber { out["default"] = d }
        if let d = f.defaultStringArray { out["default"] = d }
        if let m = f.exclusiveMinimum { out["exclusiveMinimum"] = m }
        if let m = f.minimum { out["minimum"] = m }
        if let m = f.maximum { out["maximum"] = m }
        if !f.doc.isEmpty { out["description"] = f.doc }
        // Per-enum-value hover (taplo `x-taplo.docs.enumValues`, index-aligned
        // to `enum`; a nil entry → JSON null skips that value). taplo does NOT
        // surface JSON-Schema `examples` on hover, so callers fold examples
        // into `description` (markdown-rendered by taplo) instead.
        if let docs = f.enumDocs {
            let enumValues: [Any] = docs.map { $0.map { $0 as Any } ?? NSNull() }
            out["x-taplo"] = ["docs": ["enumValues": enumValues]]
        }
        return out
    }

    static func serialize(_ obj: [String: Any], _ options: EmitOptions) -> String {
        var writing: JSONSerialization.WritingOptions = [.sortedKeys, .prettyPrinted]
        if !options.escapeSlashes { writing.insert(.withoutEscapingSlashes) }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: writing),
              let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return options.trailingNewline ? s + "\n" : s
    }
}
