import WebKit

/// WKWebView whose pinch gesture drives `pageZoom` instead of WebKit's own magnification.
/// WebKit's built-in magnification cannot go below 1.0 and is a separate scale from `pageZoom`,
/// so pinching out did nothing and ⌘0 did not undo a pinch. Routing the gesture through `Zoom`
/// gives one scale for keyboard, menu and trackpad, shrinking included, that persists like the rest.
final class ZoomingWebView: WKWebView {
    override func magnify(with event: NSEvent) {
        switch event.phase {
        case .began:
            pageZoom = Zoom.pinched(from: Zoom.current, by: event.magnification)
        case .changed:
            pageZoom = Zoom.pinched(from: pageZoom, by: event.magnification)
        case .ended, .cancelled:
            Zoom.set(pageZoom)
        default:
            break
        }
    }
}
