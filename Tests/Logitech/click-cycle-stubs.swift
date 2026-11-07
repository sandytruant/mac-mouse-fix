// Minimal dependencies for compiling the production ClickCycle on macOS.
import Cocoa

final class Device: NSObject {
    func uniqueID() -> NSNumber { 1 }
}
func DDLogDebug(_ message: String) {}
func assertRunLoop(_ loop: CFRunLoop) { precondition(CFRunLoopGetCurrent() == loop) }
enum IOThread {
    static func runLoop() -> CFRunLoop { CFRunLoopGetMain() }
}
enum Math {
    static func intCycle(x: Int, lower: Int, upper: Int) -> Int {
        (x - lower) % (upper - lower + 1) + lower
    }
}
extension Timer {
    static func mf_scheduledTimer(withTimeInterval interval: TimeInterval,
                                  mode: RunLoop.Mode,
                                  block: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: false, block: block)
        RunLoop.main.add(timer, forMode: mode)
        return timer
    }
}
