// Validator.swift — the generic runtime validator for a SchemaDescriptor.
//
// Given a SchemaDescriptor + a decoded config document (`Toml.parse`'s nested
// `[String: Toml.Value]` root), run the SAME structural + cross-field rules the
// emitter (SchemaDescriptorEmit.swift) lowers to Draft-07, and return structured
// `[ValidationError]`. The contract: "the editor is green" (taplo against the
// emitted schema) and "the loader accepts it" (this validator) cannot diverge —
// both read the one descriptor.
//
// This is the ONLY file in the descriptor family that imports Toml: the data
// types (SchemaDescriptor.swift) and the error model (ValidationError.swift)
// stay decode-free, while the validate LOGIC walks a `Toml.Value` document —
// exactly mirroring `Spec.decode`, which already consumes `Toml.Value` in this
// same module.
//
// Scope (matches the emitter): structural (type / enum / range / required /
// unknown-key) + cross-field (anyOf / oneOf / forbidsTogether / dependency) +
// nested objects / array-of-tables. OUT of scope — app-bespoke semantics (alias
// resolution, derived-key uniqueness, reserved names): those stay the app's own
// validator (surfaced as `ObjectShape.constraints` hover, enforced at load).

import Foundation
import Toml

public extension SchemaDescriptor {

    /// Validate a decoded config document (the nested `Toml.parse` root) against
    /// this descriptor's structural + cross-field rules. Returns every violation
    /// found (does not stop at the first), each located by a root-relative path.
    /// A missing top-level section is NOT an error here (sections are optional;
    /// an app requires one via its own check) — only PRESENT values are walked.
    func validate(_ root: [String: Toml.Value]) -> [ValidationError] {
        var errors: [ValidationError] = []
        for section in sections {
            guard let value = root[section.name] else { continue }
            validateSection(section, value: value, path: [section.name], into: &errors)
        }
        return errors
    }

    // MARK: - sections

    private func validateSection(
        _ section: SchemaSection, value: Toml.Value, path: [String],
        into errors: inout [ValidationError]
    ) {
        switch section.kind {
        case .table(let shape):
            guard let table = value.asTable else {
                errors.append(typeError(path: path, key: section.name,
                                        expected: "table [\(section.name)]"))
                return
            }
            validateObject(shape, table: table, path: path, into: &errors)

        case .arrayOfTables(let shape):
            guard let rows = value.asArrayOfTables else {
                errors.append(typeError(path: path, key: section.name,
                                        expected: "array of tables [[\(section.name)]]"))
                return
            }
            for (i, row) in rows.enumerated() {
                validateObject(shape, table: row.fields,
                               path: path + ["[\(i)]"], into: &errors)
            }

        case .openStringMap:
            guard let table = value.asTable else {
                errors.append(typeError(path: path, key: section.name, expected: "table"))
                return
            }
            for (k, v) in table where v.asString == nil {
                errors.append(typeError(path: path + [k], key: k, expected: "string"))
            }

        case .openIntMap(_, let min, let max):
            guard let table = value.asTable else {
                errors.append(typeError(path: path, key: section.name, expected: "table"))
                return
            }
            for (k, v) in table {
                guard let i = v.asInt else {
                    errors.append(typeError(path: path + [k], key: k, expected: "integer"))
                    continue
                }
                if i < min || i > max {
                    errors.append(ValidationError(
                        path: path + [k],
                        rule: .outOfRange(key: k, detail: "\(min)…\(max)"),
                        message: "\(joined(path + [k])): \(i) out of range \(min)…\(max)"))
                }
            }
        }
    }

    // MARK: - object / table

    private func validateObject(
        _ shape: ObjectShape, table: [String: Toml.Value], path: [String],
        into errors: inout [ValidationError]
    ) {
        // 1. unknown-key (strict tables only). Keys handled by an open-map
        //    `dynamicValue` are checked in step 7 instead (pattern + recurse).
        if !shape.permissive && shape.dynamicValue == nil {
            let known = shape.keySet
            for key in table.keys where !known.contains(key) {
                errors.append(ValidationError(
                    path: path + [key], rule: .unknownKey(key: key),
                    message: "\(joined(path + [key])): unknown key '\(key)'"))
            }
        }
        // 2. required scalar/array keys.
        for key in shape.required where table[key] == nil {
            errors.append(ValidationError(
                path: path + [key], rule: .requiredMissing(key: key),
                message: "\(joined(path)): required key '\(key)' is missing"))
        }
        // 3. field-level type / enum / range (present fields only).
        for field in shape.fields {
            guard let value = table[field.key] else { continue }
            validateField(field, value: value, path: path, into: &errors)
        }
        // 4. cross-field rules.
        for rule in shape.exclusions {
            validateExclusion(rule, table: table, path: path, into: &errors)
        }
        // 5. nested single-object children.
        for child in shape.objects {
            guard let value = table[child.key] else { continue }
            guard let childTable = value.asTable else {
                errors.append(typeError(path: path + [child.key], key: child.key,
                                        expected: "table"))
                continue
            }
            validateObject(child.shape, table: childTable,
                           path: path + [child.key], into: &errors)
        }
        // 6. nested array-of-tables children.
        for nested in shape.nested {
            let value = table[nested.key]
            if value == nil {
                if nested.required {
                    errors.append(ValidationError(
                        path: path + [nested.key], rule: .requiredMissing(key: nested.key),
                        message: "\(joined(path)): required table '\(nested.key)' is missing"))
                }
                continue
            }
            guard let rows = value?.asArrayOfTables else {
                errors.append(typeError(path: path + [nested.key], key: nested.key,
                                        expected: "array of tables"))
                continue
            }
            if nested.nonEmpty && rows.isEmpty {
                errors.append(ValidationError(
                    path: path + [nested.key], rule: .emptyArrayOfTables(key: nested.key),
                    message: "\(joined(path + [nested.key])): must have at least one entry"))
            }
            for (i, row) in rows.enumerated() {
                validateObject(nested.item, table: row.fields,
                               path: path + [nested.key, "[\(i)]"], into: &errors)
            }
        }
        // 7. open-map dynamic keys (facet's `[desktop.<N>]`): each key that is
        //    NOT a declared key must match the value's `keyPattern` (else it is
        //    an unknown key, mirroring the emitted `additionalProperties: false`),
        //    then its value recurses into the shared value shape.
        if let dv = shape.dynamicValue {
            // Precompile the key pattern into a matcher. `nil` keyPattern = accept
            // any key name (the `additionalProperties: <schema>` open map). A
            // provided-but-uncompilable pattern is a BROKEN schema: match nothing
            // (fail-closed), mirroring the emitted never-matching `patternProperties`
            // + `additionalProperties: false` — never silently accept every key.
            let matcher: (String) -> Bool
            if let pattern = dv.keyPattern {
                let re = try? NSRegularExpression(pattern: pattern)
                matcher = { key in
                    guard let re else { return false }
                    let range = NSRange(key.startIndex..<key.endIndex, in: key)
                    return re.firstMatch(in: key, options: [], range: range) != nil
                }
            } else {
                matcher = { _ in true }
            }
            let known = shape.keySet
            for (key, value) in table where !known.contains(key) {
                guard matcher(key) else {
                    errors.append(ValidationError(
                        path: path + [key], rule: .unknownKey(key: key),
                        message: "\(joined(path + [key])): key '\(key)' does not match "
                               + "the required pattern '\(dv.keyPattern ?? "")'"))
                    continue
                }
                if let leaf = dv.leaf {
                    // Leaf-valued map (word → [String]): run the field check with
                    // the dynamic key substituted so paths/messages name the
                    // actual entry (`search.synonyms.close[1]`).
                    validateField(renamed(leaf, to: key), value: value,
                                  path: path, into: &errors)
                    continue
                }
                guard let childTable = value.asTable else {
                    errors.append(typeError(path: path + [key], key: key, expected: "table"))
                    continue
                }
                validateObject(dv.shape, table: childTable, path: path + [key], into: &errors)
            }
        }
    }

    // MARK: - field-level

    private func validateField(
        _ field: SchemaField, value: Toml.Value, path: [String],
        into errors: inout [ValidationError]
    ) {
        let here = path + [field.key]
        switch field.shape {
        case .string:
            guard let s = value.asString else {
                errors.append(typeError(path: here, key: field.key, expected: "string")); return
            }
            checkEnum(field, s, path: here, into: &errors)

        case .integer:
            guard let i = value.asInt else {
                errors.append(typeError(path: here, key: field.key, expected: "integer")); return
            }
            checkRange(field, Double(i), path: here, into: &errors)

        case .number:
            guard let d = numeric(value) else {
                errors.append(typeError(path: here, key: field.key, expected: "number")); return
            }
            checkRange(field, d, path: here, into: &errors)

        case .boolean:
            if value.asBool == nil {
                errors.append(typeError(path: here, key: field.key, expected: "boolean"))
            }

        case .constTrue:
            switch value.asBool {
            case .some(true): break
            case .some(false):
                errors.append(ValidationError(
                    path: here, rule: .notInEnum(key: field.key, value: "false", allowed: ["true"]),
                    message: "\(joined(here)): only `true` is meaningful"))
            case nil:
                errors.append(typeError(path: here, key: field.key, expected: "boolean (true)"))
            }

        case .stringArray:
            guard let arr = value.asArray else {
                errors.append(typeError(path: here, key: field.key, expected: "array of strings")); return
            }
            checkStringArray(field, arr, path: here, into: &errors)

        case .stringOrStringArray:
            if let s = value.asString {
                checkEnum(field, s, path: here, into: &errors)
            } else if let arr = value.asArray {
                checkStringArray(field, arr, path: here, into: &errors)
            } else {
                errors.append(typeError(path: here, key: field.key,
                                        expected: "string or array of strings"))
            }

        case .intMap:
            guard let table = value.asTable else {
                errors.append(typeError(path: here, key: field.key, expected: "table of integers")); return
            }
            for (k, v) in table where v.asInt == nil {
                errors.append(typeError(path: here + [k], key: k, expected: "integer"))
            }

        case .stringMap:
            guard let table = value.asTable else {
                errors.append(typeError(path: here, key: field.key, expected: "table of strings")); return
            }
            for (k, v) in table where v.asString == nil {
                errors.append(typeError(path: here + [k], key: k, expected: "string"))
            }
        }
    }

    private func checkEnum(
        _ field: SchemaField, _ value: String, path: [String],
        into errors: inout [ValidationError]
    ) {
        guard let domain = field.enumDomain, !domain.contains(value) else { return }
        errors.append(ValidationError(
            path: path, rule: .notInEnum(key: field.key, value: value, allowed: domain),
            message: "\(joined(path)): '\(value)' not in [\(domain.joined(separator: ", "))]"))
    }

    private func checkStringArray(
        _ field: SchemaField, _ arr: [Toml.Value], path: [String],
        into errors: inout [ValidationError]
    ) {
        for (i, el) in arr.enumerated() {
            guard let s = el.asString else {
                errors.append(typeError(path: path + ["[\(i)]"], key: field.key, expected: "string"))
                continue
            }
            if let item = field.arrayItemEnum, !item.contains(s) {
                errors.append(ValidationError(
                    path: path + ["[\(i)]"],
                    rule: .notInEnum(key: field.key, value: s, allowed: item),
                    message: "\(joined(path + ["[\(i)]"])): '\(s)' not in [\(item.joined(separator: ", "))]"))
            }
        }
    }

    private func checkRange(
        _ field: SchemaField, _ v: Double, path: [String],
        into errors: inout [ValidationError]
    ) {
        if let ex = field.exclusiveMinimum, !(v > Double(ex)) {
            errors.append(rangeError(field, path, "must be > \(ex) (got \(trim(v)))"))
        }
        if let lo = field.minimum, v < lo {
            errors.append(rangeError(field, path, "must be ≥ \(trim(lo)) (got \(trim(v)))"))
        }
        if let hi = field.maximum, v > hi {
            errors.append(rangeError(field, path, "must be ≤ \(trim(hi)) (got \(trim(v)))"))
        }
    }

    // MARK: - cross-field

    private func validateExclusion(
        _ rule: ExclusionRule, table: [String: Toml.Value], path: [String],
        into errors: inout [ValidationError]
    ) {
        func present(_ keys: [String]) -> [String] { keys.filter { table[$0] != nil } }
        switch rule {
        case .anyOfRequired(let keys):
            if present(keys).isEmpty {
                errors.append(ValidationError(
                    path: path, rule: .anyOfRequired(keys: keys),
                    message: "\(joined(path)): at least one of [\(keys.joined(separator: ", "))] is required"))
            }
        case .oneOfRequired(let keys):
            let n = present(keys).count
            if n != 1 {
                errors.append(ValidationError(
                    path: path, rule: .oneOfRequired(keys: keys, presentCount: n),
                    message: "\(joined(path)): exactly one of [\(keys.joined(separator: ", "))] required (found \(n))"))
            }
        case .forbidsTogether(let keys):
            if present(keys).count > 1 {
                errors.append(ValidationError(
                    path: path, rule: .forbidsTogether(keys: keys),
                    message: "\(joined(path)): [\(present(keys).joined(separator: ", "))] cannot be set together"))
            }
        case .dependency(let key, let needs):
            if table[key] != nil && table[needs] == nil {
                errors.append(ValidationError(
                    path: path, rule: .dependency(key: key, needs: needs),
                    message: "\(joined(path)): '\(key)' requires '\(needs)'"))
            }
        }
    }

    // MARK: - helpers

    /// A copy of `field` under a different key — how a leaf `DynamicValue`
    /// reuses the field checks for each dynamic entry.
    private func renamed(_ f: SchemaField, to key: String) -> SchemaField {
        SchemaField(key, f.shape, doc: f.doc,
                    enumDomain: f.enumDomain, enumDocs: f.enumDocs,
                    arrayItemEnum: f.arrayItemEnum,
                    defaultBool: f.defaultBool, defaultInt: f.defaultInt,
                    defaultString: f.defaultString, defaultNumber: f.defaultNumber,
                    defaultStringArray: f.defaultStringArray,
                    exclusiveMinimum: f.exclusiveMinimum,
                    minimum: f.minimum, maximum: f.maximum,
                    rejected: f.rejected)
    }

    private func numeric(_ v: Toml.Value) -> Double? {
        if case .int(let i) = v { return Double(i) }
        if case .double(let d) = v { return d }
        return nil
    }

    private func typeError(path: [String], key: String, expected: String) -> ValidationError {
        ValidationError(path: path, rule: .typeMismatch(key: key, expected: expected),
                        message: "\(joined(path)): expected \(expected)")
    }

    private func rangeError(_ field: SchemaField, _ path: [String], _ detail: String) -> ValidationError {
        ValidationError(path: path, rule: .outOfRange(key: field.key, detail: detail),
                        message: "\(joined(path)): \(detail)")
    }

    private func joined(_ path: [String]) -> String {
        var out = ""
        for seg in path {
            if seg.hasPrefix("[") { out += seg }
            else if out.isEmpty { out = seg }
            else { out += "." + seg }
        }
        return out
    }

    /// Trim a whole-valued Double to an integer string for messages (`20` not `20.0`).
    private func trim(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }
}
