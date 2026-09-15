# Hostile document

Manual check for the preview sandbox. Open this file; nothing below should run, navigate or
leak. Web Inspector (right click → Inspect) should show CSP violations, not alerts.
See `SECURITY.md` for the threat model and `MDReaderTests/WebViewHardeningTests.swift`
for the automated version.

## Script execution

<script>document.title = 'pwned-inline'</script>
<img src="missing.png" onerror="document.title='pwned-onerror'">
<svg onload="document.title='pwned-svg'"></svg>
<details open ontoggle="document.title='pwned-toggle'">details</details>

[javascript: link](javascript:document.title='pwned-href')

## Navigation hijack

<meta http-equiv="refresh" content="0;url=https://example.com/">
<base href="https://example.com/">
<form action="https://example.com/post" method="post"><button>submit</button></form>

## Reading local files

<iframe src="file:///etc/hosts"></iframe>
<object data="file:///etc/hosts"></object>
<embed src="file:///etc/passwd">

## Launching things by click

Each of these must only reveal in Finder, never open/run:

- [shell](./demo.command)
- [app](/System/Applications/Calculator.app)
- [webloc](./x.webloc)
- [archive](./x.zip)

Custom schemes must be ignored: [prefs](x-apple.systempreferences:com.apple.preference.security)
[vscode](vscode://file/etc/passwd) [ssh](ssh://example.com)

## Allowed

Relative image next to this file would load: ![pixel](pixel.png)
Web link opens in browser: [example](https://example.com) · mail: [mail](mailto:test@example.com)
