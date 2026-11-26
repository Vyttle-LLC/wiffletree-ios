import Synchronization

/// A flag that is set once and stays set, shareable with escaping closures.
final class Latch: Sendable {
    private let state = Mutex(false)

    var isSet: Bool { state.withLock { $0 } }

    /// Sets the flag; true only for the call that set it.
    @discardableResult
    func set() -> Bool {
        state.withLock { wasSet in
            defer { wasSet = true }
            return !wasSet
        }
    }
}
