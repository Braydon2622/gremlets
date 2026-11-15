import Foundation

extension World {
    /// An urgent Back Office event: a Gremlet walks to the nearer edge of the screen (along whatever it's standing on)
    /// to hold up the sign there, out of the way of your work. Returns who went, or nil if nobody's out.
    public func officeMessenger() -> Int? {
        let free = creatures.filter { isFree($0) && $0.isGrounded && !$0.isAsleep && $0.mossTask == nil && $0.job == nil }
        guard let c = free.first(where: { supportingSurface(for: $0)?.kind == .floor }) ?? free.first,
              let s = supportingSurface(for: c), let scr = screens.first(where: { c.pos.x >= $0.minX && c.pos.x < $0.maxX }) else { return say() }
        endSocial(c)
        let left = c.pos.x - scr.minX < scr.maxX - c.pos.x
        let x = left ? max(s.minX, scr.minX) + 28 : min(s.maxX, scr.maxX) - 28
        c.targetX = x
        c.facing = x > c.pos.x ? 1 : -1
        c.set(.walk, duration: 20)
        emit(.alert(c.id))
        return c.id
    }
}
