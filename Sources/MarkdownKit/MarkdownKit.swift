import Markdown

// Smoke check that swift-markdown links on CommandLineTools. Removed in Task 3.
enum MarkdownKitBuildSmoke { static let ok = Document(parsing: "# hi").childCount >= 0 }
