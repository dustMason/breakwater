import Foundation

/// One physical multi-touch gesture creates one ordered, latched cycle.
/// Finger release never rewrites the cycle. The next fresh gesture replaces it.
struct PadGesture {
    private(set) var held: [Int: Int32] = [:]
    private(set) var order: [Int32] = []
    mutating func began(token: Int, pad: Int32) -> [Int32] {
        if held.isEmpty { order.removeAll(keepingCapacity: true) }
        held[token] = pad
        if !order.contains(pad) { order.append(pad) }
        return order
    }
    mutating func moved(token: Int, pad: Int32) -> [Int32]? {
        guard let prior = held[token], prior != pad else { return nil }
        held[token] = pad
        if !order.contains(pad) { order.append(pad) }
        return order
    }
    mutating func ended(token: Int) { held.removeValue(forKey: token) }
    mutating func cancel() { held.removeAll() }
}
