---
title: MD Reader demo
author: Jarkko
tags: markdown, macos
---

# MD Reader

A fast, native Markdown viewer for macOS. This file exercises the rendering pipeline.

## Text

Plain paragraph with **bold**, *italic*, ~~strikethrough~~, `inline code`, and a [link](https://daringfireball.net/projects/markdown/). Autolink: https://apple.com. Press <kbd>⌘</kbd>+<kbd>F</kbd> to find.

> Blockquote with a nested list:
> - one
> - two

### Lists

1. First
2. Second
   - nested bullet
   - another
3. Third

- [x] Task done
- [ ] Task pending

## Code

```swift
import AppKit

final class Greeter {
    let name: String
    init(name: String) { self.name = name }
    func greet() -> String { "Hello, \(name)!" }
}
```

```bash
xcodegen generate && xcodebuild -scheme MDReader build
```

    indented code block

## Table

| Feature | Status | Notes |
|---|:---:|---|
| GFM tables | ✅ | via cmark-gfm |
| Task lists | ✅ | rendered as checkboxes |
| Footnotes | ✅ | see below[^1] |
| Live reload | ✅ | kqueue watcher |

## Anchor

Jump to [Text](#text) or [Code](#code).

---

Footnote reference[^1].

[^1]: This is the footnote body.
