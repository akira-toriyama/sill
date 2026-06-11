// still — mock chrome specimens. Each is a tiny, deliberately-fake
// rendition of an app's signature surface, drawn HERE in the resolved
// palette. still imports NO app View code — these mirror the apps by
// eye, so the preview can't couple the library to any app.

import SwiftUI
import PaletteKit

// MARK: - Shared container

struct SpecimenBox<Content: View>: View {
    let title: String
    let p: ResolvedPalette
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
            content()
        }
        .padding(10)
        .frame(width: 246, alignment: .leading)
        .background(Color(nsColor: p.hover))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color(nsColor: p.border), lineWidth: 1))
    }
}

// MARK: - facet tree

struct MockTree: View {
    let p: ResolvedPalette
    let scale: CGFloat

    var body: some View {
        SpecimenBox(title: "facet · tree", p: p) {
            VStack(spacing: 2) {
                row("Safari", badge: "web", dot: p.secondary, selected: false, dim: false)
                row("Xcode", badge: "2", dot: p.primary, selected: true, dim: false)
                row("Terminal", badge: nil, dot: p.secondary, selected: false, dim: false)
                row("Notes", badge: "hidden", dot: p.muted, selected: false, dim: true)
            }
        }
    }

    @ViewBuilder private func row(_ title: String, badge: String?, dot: NSColor,
                                  selected: Bool, dim: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color(nsColor: dot)).frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: dim ? p.tertiary : p.foreground))
            Spacer(minLength: 4)
            if let b = badge {
                Text(b)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.muted))
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(selected ? Color(nsColor: p.selection) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - perch hint pills

struct MockPill: View {
    let p: ResolvedPalette
    let scale: CGFloat

    var body: some View {
        SpecimenBox(title: "perch · hints", p: p) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    pill("J", fill: nil)
                    pill("K", fill: p.primary)        // matched
                    pill("L", fill: nil)
                }
                HStack(spacing: 6) {
                    pill("⌫", fill: p.error)          // no-match / cancel
                    Text("type to filter")
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: p.muted))
                }
            }
        }
    }

    @ViewBuilder private func pill(_ key: String, fill: NSColor?) -> some View {
        let matched = fill != nil
        Text(key)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(Color(nsColor: matched ? p.onPrimary() : p.foreground))
            .frame(width: 26, height: 22)
            .background(Color(nsColor: fill ?? p.background ?? .clear).opacity(matched ? 1 : 0.9))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(nsColor: matched ? .clear : p.border), lineWidth: 1))
    }
}

// MARK: - wand tome (launcher)

struct MockTome: View {
    let p: ResolvedPalette
    let scale: CGFloat

    var body: some View {
        SpecimenBox(title: "wand · tome", p: p) {
            VStack(alignment: .leading, spacing: 6) {
                // search field
                HStack(spacing: 5) {
                    Circle().stroke(Color(nsColor: p.muted), lineWidth: 1.5)
                        .frame(width: 9, height: 9)
                    Text("open…")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: p.muted))
                    Spacer()
                }
                .padding(.horizontal, 7).padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: p.border), lineWidth: 1))

                result("Settings", sub: "⌘ ,", selected: true)
                result("Switch theme", sub: "rainbow", selected: false)
            }
        }
    }

    @ViewBuilder private func result(_ title: String, sub: String, selected: Bool) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: selected ? p.primary : p.secondary))
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(nsColor: p.foreground))
                Text(sub).font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.muted))
            }
            Spacer()
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(selected ? Color(nsColor: p.selection) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - glance markdown

struct MockMarkdown: View {
    let p: ResolvedPalette
    let scale: CGFloat

    var body: some View {
        SpecimenBox(title: "glance · markdown", p: p) {
            VStack(alignment: .leading, spacing: 5) {
                Text("# Heading")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(nsColor: p.primary))
                Text("Body text with a")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: p.foreground))
                + Text(" link")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(nsColor: p.primary))
                Text("inline_code()")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.foreground))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color(nsColor: p.selection))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Text("error: not found")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.error))
                Text("caption · least emphasis")
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: p.tertiary))
            }
        }
    }
}
