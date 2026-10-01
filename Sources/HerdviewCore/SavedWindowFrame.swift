import Foundation

/// The string AppKit's frame autosave keeps: the window's frame, the screen's
/// visible frame, and — since macOS 15, while the window is tiled — a JSON
/// `tilingState`. Restoring that string re-tiles the window, and macOS then
/// puts it back to Fill after every Mission Control.
public enum SavedWindowFrame {
    /// `saved` with the tile dropped: the size from before the tile, at most
    /// the screen's, centred on the screen the window was on. `nil` when the
    /// window was not tiled, or there is no untiled size to go back to.
    public static func untiled(_ saved: String) -> String? {
        guard let brace = saved.firstIndex(of: "{") else { return nil }
        let numbers = saved[..<brace].split(separator: " ").compactMap { Double($0) }
        guard numbers.count == 8,
              let json = (try? JSONSerialization.jsonObject(with: Data(saved[brace...].utf8))) as? [String: Any],
              let tiling = json["tilingState"] as? [String: Any],
              let untiledFrame = tiling["untiledFrame"] as? String else { return nil }
        let size = NSRectFromString(untiledFrame).size
        guard size.width > 0, size.height > 0 else { return nil }

        let screen = (x: numbers[4], y: numbers[5], width: numbers[6], height: numbers[7])
        let width = min(size.width, screen.width)
        let height = min(size.height, screen.height)
        let frame = [screen.x + (screen.width - width) / 2, screen.y + (screen.height - height) / 2, width, height]
        return (frame + numbers[4...]).map { String(Int($0.rounded())) }.joined(separator: " ")
    }
}
