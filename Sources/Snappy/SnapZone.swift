import AppKit

enum SnapZone: CaseIterable {
    case left, right, full

    var id: String {
        switch self { case .left: return "left"; case .right: return "right"; case .full: return "full" }
    }

    var title: String {
        switch self {
        case .left: return "Left Half"
        case .right: return "Right Half"
        case .full: return "Full Screen"
        }
    }

    /// Target frame in AppKit coordinates (bottom-left origin) within `area` (a screen's visibleFrame).
    func frame(in area: NSRect) -> NSRect {
        switch self {
        case .left:
            return NSRect(x: area.minX, y: area.minY, width: (area.width / 2).rounded(.down), height: area.height)
        case .right:
            let w = (area.width / 2).rounded(.down)
            return NSRect(x: area.maxX - w, y: area.minY, width: w, height: area.height)
        case .full:
            return area
        }
    }
}
