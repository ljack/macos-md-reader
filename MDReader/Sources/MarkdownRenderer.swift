import Foundation
import cmark_gfm
import cmark_gfm_extensions

struct RenderResult {
    var html: String
}

enum MarkdownRenderer {
    private static let extensionNames = ["table", "strikethrough", "autolink", "tasklist", "tagfilter"]
    private static let options: Int32 = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_VALIDATE_UTF8

    static func warmUp() {
        cmark_gfm_core_extensions_ensure_registered()
    }

    static func render(_ markdown: String) -> RenderResult {
        cmark_gfm_core_extensions_ensure_registered()
        let (frontMatter, body) = FrontMatter.split(markdown)

        guard let parser = cmark_parser_new(options) else {
            return RenderResult(html: "<pre>\(HTMLEscape.escape(markdown))</pre>")
        }
        defer { cmark_parser_free(parser) }

        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        var bytes = Array(body.utf8)
        if !bytes.isEmpty {
            bytes.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buf.count) { ptr in
                    cmark_parser_feed(parser, ptr, buf.count)
                }
            }
        }

        guard let doc = cmark_parser_finish(parser) else {
            return RenderResult(html: "")
        }
        defer { cmark_node_free(doc) }

        guard let cstr = cmark_render_html(doc, options, cmark_parser_get_syntax_extensions(parser)) else {
            return RenderResult(html: "")
        }
        defer { free(cstr) }

        var html = String(cString: cstr)
        if let frontMatter {
            html = frontMatter.html + html
        }
        return RenderResult(html: html)
    }
}

// MARK: - Front matter

struct FrontMatter {
    var pairs: [(key: String, value: String)]
    var raw: String

    /// Splits a leading `---` YAML block from the body.
    static func split(_ text: String) -> (FrontMatter?, String) {
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else { return (nil, text) }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 2 else { return (nil, text) }
        var end: Int?
        for i in 1..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "---" || line == "..." { end = i; break }
        }
        guard let end else { return (nil, text) }
        let block = lines[1..<end].map(String.init)
        let body = lines[(end + 1)...].joined(separator: "\n")

        var pairs: [(String, String)] = []
        for line in block {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty { pairs.append((key, value)) }
        }
        return (FrontMatter(pairs: pairs, raw: block.joined(separator: "\n")), body)
    }

    var html: String {
        if pairs.isEmpty {
            return "<pre class=\"frontmatter-raw\">\(HTMLEscape.escape(raw))</pre>\n"
        }
        var out = "<table class=\"frontmatter\"><tbody>"
        for (key, value) in pairs {
            out += "<tr><th>\(HTMLEscape.escape(key))</th><td>\(HTMLEscape.escape(value))</td></tr>"
        }
        out += "</tbody></table>\n"
        return out
    }
}

enum HTMLEscape {
    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }
}
