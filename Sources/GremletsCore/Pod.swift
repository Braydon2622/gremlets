import Foundation

/// The hut beside Claude's terminal: a mossy branch grows out from the terminal window's top corner (the end away
/// from the project's tree), and a little woven acorn hut hangs from it on a vine, swinging gently, its window
/// glowing while Claude works. It hangs outside the window, never over what you're reading. The branch is a perch.
public struct PodPlacement: Sendable {
    public var project: String
    public var windowID: Int
    /// +1: out past the window's right edge; -1: past its left edge.
    public var side: Double
    /// Where the vine is tied on the branch (global points).
    public var tie: Vec2
    public var branch: Surface
    public static let ropeLength = 14.0
    public static let podSize = Vec2(36, 45)
}

extension World {
    static let podOwnerBase = -440_000
    static func isPodOwner(_ o: Int?) -> Bool { guard let o else { return false }; return o <= podOwnerBase && o > podOwnerBase - 100 }

    /// Where a live project's hut goes: at the window corner away from its tree, if there's room beside the window
    /// for it to hang (otherwise the other corner, otherwise nowhere).
    func podLayout(for tree: BonsaiPlacement, k: Int) -> (PodPlacement, Surface)? {
        guard let wid = tree.windowID, let w = windows[wid],
              let scr = screens.first(where: { w.midX >= $0.minX && w.midX < $0.maxX }) ?? screens.first,
              scr.maxY - w.maxY > 24 else { return nil }
        func fits(_ side: Double) -> Bool {
            let room = side > 0 ? scr.maxX - w.maxX : w.minX - scr.minX
            let corner = side > 0 ? w.maxX - 12 : w.minX + 12
            return room >= 72 && builtSurfaces.contains { $0.ownerID == wid && $0.kind == .windowTop && $0.supports(x: corner) }
        }
        let preferred: Double = tree.base.x < w.midX ? 1 : -1
        guard let side = [preferred, -preferred].first(where: fits) else { return nil }
        let y = w.maxY + 3
        let edge = side > 0 ? w.maxX : w.minX
        let branch = Surface(ownerID: World.podOwnerBase - k, kind: .shelf, y: y,
                             minX: side > 0 ? edge - 16 : edge - 56, maxX: side > 0 ? edge + 56 : edge + 16)
        return (PodPlacement(project: tree.project, windowID: wid, side: side, tie: Vec2(edge + side * 40, y - 2), branch: branch), branch)
    }
}
