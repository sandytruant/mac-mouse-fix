// Exercises the real ClickCycle implementation, including its Foundation timers.
import Cocoa

@main struct ClickCycleTests {
    static func main() {
        let device = Device()
        let cycle = ClickCycle()
        var presses: [Int] = [], holds: [Int] = []
        var releaseCount = 0
        let callback: ClickCycleTriggerCallback = { phase, level, _, _, releases in
            if phase == .press {
                presses.append(level)
                releases.append { releaseCount += 1 }
            }
            if phase == .hold { holds.append(level) }
        }
        func input(_ down: Bool) {
            cycle.handleClick(device: device, button: 4, downNotUp: down,
                              maxClickLevel: 3, triggerCallback: callback)
        }
        func wait(_ seconds: Double) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
        func reset() { cycle.kill(); presses = []; holds = []; releaseCount = 0 }

        // Duplicate down/up must not become a double click or a ghost hold after release.
        input(true); input(true); input(false); input(false)
        wait(0.35)
        precondition(presses == [1] && holds.isEmpty && releaseCount == 1)

        // Genuine double click still increments the level.
        reset()
        input(true); input(false); input(true); input(false)
        wait(0.35)
        precondition(presses == [1, 2] && holds.isEmpty && releaseCount == 2)

        // A repeated down during a hold must not create a second press or hold timer.
        reset()
        input(true); input(true)
        wait(0.28)
        input(true)
        precondition(presses == [1] && holds == [1])
        input(false)
        wait(0.3)
        precondition(holds == [1] && releaseCount == 1)

        // A real click followed by a hold is still a double-click-and-hold.
        reset()
        input(true); input(false); input(true)
        wait(0.28)
        precondition(presses == [1, 2] && holds == [2])
        input(false)
        precondition(releaseCount == 2)
        cycle.kill()
        print("PASS ClickCycle: duplicate edges, genuine double click, hold, double-click-and-hold")
    }
}
