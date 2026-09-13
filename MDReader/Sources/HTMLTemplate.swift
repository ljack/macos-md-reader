import Foundation

enum HTMLTemplate {
    private static let css = load("preview", "css")
    private static let js = load("preview", "js")
    private static let hljs = load("highlight.min", "js")
    private static let hljsLight = load("github.min", "css")
    private static let hljsDark = load("github-dark.min", "css")

    static func warmUp() {
        _ = css; _ = js; _ = hljs; _ = hljsLight; _ = hljsDark
    }

    static func page(body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        <style>
        @media (prefers-color-scheme: light) { \(hljsLight) }
        @media (prefers-color-scheme: dark) { \(hljsDark) }
        </style>
        </head>
        <body>
        <article id="content" class="markdown-body">\(body)</article>
        <script>\(hljs)</script>
        <script>\(js)</script>
        </body>
        </html>
        """
    }

    private static func load(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }
}
