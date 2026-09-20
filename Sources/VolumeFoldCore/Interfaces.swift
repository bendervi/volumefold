import Foundation

/// Driver callbacks and all controller methods execute on the main queue.
public protocol LidSensor: AnyObject {
    var onReading: ((Double?) -> Void)? { get set }
    func start()
    func stop()
}

public struct AudioOutput: Equatable {
    public let id: UInt32
    public let name: String
    public let isBuiltInSpeaker: Bool
    public let volume: Double?
    public let isMuted: Bool

    public init(id: UInt32, name: String, isBuiltInSpeaker: Bool, volume: Double?, isMuted: Bool) {
        self.id = id
        self.name = name
        self.isBuiltInSpeaker = isBuiltInSpeaker
        self.volume = volume
        self.isMuted = isMuted
    }
    public var canControl: Bool { isBuiltInSpeaker && volume != nil }
}

public protocol AudioDevice: AnyObject {
    var onChange: (() -> Void)? { get set }
    func start()
    func stop()
    func currentOutput() -> AudioOutput?
    /// Must recheck that this is still the default built-in speaker before writing.
    func setVolume(_ volume: Double, outputID: UInt32) throws
}

public protocol Cancellation: AnyObject { func cancel() }
public protocol ControlScheduler {
    var now: TimeInterval { get }
    func repeating(every interval: TimeInterval, action: @escaping () -> Void) -> Cancellation
}

public final class MainRunLoopScheduler: ControlScheduler {
    public init() {}
    public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    public func repeating(every interval: TimeInterval, action: @escaping () -> Void) -> Cancellation {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in action() }
        timer.tolerance = interval * 0.15
        RunLoop.main.add(timer, forMode: .common)
        return TimerCancellation(timer)
    }
}

private final class TimerCancellation: Cancellation {
    private let timer: Timer
    init(_ timer: Timer) { self.timer = timer }
    func cancel() { timer.invalidate() }
    deinit { timer.invalidate() }
}
