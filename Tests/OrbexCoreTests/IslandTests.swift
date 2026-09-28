import XCTest
@testable import OrbexCore

final class IslandStateMachineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testHoverPeeksAndLingerReturnsToHidden() {
        let m = IslandStateMachine()
        m.handle(.mouseEntered, now: t0)
        XCTAssertEqual(m.state, .peek)
        m.handle(.mouseExited, now: t0)
        m.tick(now: t0.addingTimeInterval(0.5))
        XCTAssertEqual(m.state, .peek)
        m.tick(now: t0.addingTimeInterval(1))
        XCTAssertEqual(m.state, .hidden)
    }

    func testClickOpensAndAutoClosesAfterTimeout() {
        let m = IslandStateMachine()
        m.handle(.mouseEntered, now: t0)
        m.handle(.click, now: t0)
        XCTAssertEqual(m.state, .open)
        m.handle(.mouseExited, now: t0)
        m.tick(now: t0.addingTimeInterval(14))
        XCTAssertEqual(m.state, .open)
        m.tick(now: t0.addingTimeInterval(15.1))
        XCTAssertEqual(m.state, .hidden)
    }

    func testHoverCancelsAutoClose() {
        let m = IslandStateMachine()
        m.handle(.click, now: t0)
        m.handle(.mouseExited, now: t0)
        m.handle(.mouseEntered, now: t0.addingTimeInterval(5))
        m.tick(now: t0.addingTimeInterval(30))
        XCTAssertEqual(m.state, .open)
    }

    func testContextDefinesRestingState() {
        let m = IslandStateMachine()
        m.handle(.contextChanged(IslandContext(isWorking: true)))
        XCTAssertEqual(m.state, .active)
        m.handle(.contextChanged(IslandContext(isWorking: true, needsAttention: true)))
        XCTAssertEqual(m.state, .needsYou)
        m.handle(.contextChanged(IslandContext(isSleepy: true)))
        XCTAssertEqual(m.state, .sleeping)
        m.handle(.contextChanged(IslandContext()))
        XCTAssertEqual(m.state, .hidden)
    }

    func testOpenStaysOpenWhenContextChanges() {
        let m = IslandStateMachine()
        m.handle(.click, now: t0)
        m.handle(.contextChanged(IslandContext(isWorking: true)))
        XCTAssertEqual(m.state, .open)
        m.handle(.escape)
        XCTAssertEqual(m.state, .active)
    }

    func testAttentionWhilePeekingShowsNeedsYou() {
        let m = IslandStateMachine()
        m.handle(.mouseEntered, now: t0)
        m.handle(.contextChanged(IslandContext(needsAttention: true)))
        XCTAssertEqual(m.state, .needsYou)
    }

    func testAssistantIgnoresClickOutsideButClosesWithEscape() {
        let m = IslandStateMachine()
        m.handle(.toggleAssistant)
        XCTAssertEqual(m.state, .assistant)
        m.handle(.clickOutside)
        XCTAssertEqual(m.state, .assistant)
        m.handle(.escape)
        XCTAssertEqual(m.state, .hidden)
    }

    func testClockToggle() {
        let m = IslandStateMachine()
        m.handle(.toggleClock)
        XCTAssertEqual(m.state, .clock)
        m.handle(.contextChanged(IslandContext(isWorking: true)))
        XCTAssertEqual(m.state, .clock)
        m.handle(.toggleClock)
        XCTAssertEqual(m.state, .active)
    }

    func testOnChangeCallback() {
        let m = IslandStateMachine()
        var changes: [(IslandState, IslandState)] = []
        m.onChange = { changes.append(($0, $1)) }
        m.handle(.click)
        m.handle(.escape)
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes.first?.1, .open)
    }

    func testFlashPeeksThenHides() {
        let m = IslandStateMachine()
        m.handle(.flash(duration: 2), now: t0)
        XCTAssertEqual(m.state, .peek)
        m.tick(now: t0.addingTimeInterval(1))
        XCTAssertEqual(m.state, .peek)
        m.tick(now: t0.addingTimeInterval(2.1))
        XCTAssertEqual(m.state, .hidden)
        m.handle(.contextChanged(IslandContext(isWorking: true)))
        m.handle(.flash(duration: 2), now: t0)
        XCTAssertEqual(m.state, .active)
    }

    func testHoverPeekCanBeDisabled() {
        let m = IslandStateMachine(config: .init(hoverPeeks: false))
        m.handle(.mouseEntered)
        XCTAssertEqual(m.state, .hidden)
    }
}

final class IslandGeometryTests: XCTestCase {
    // MacBook Air M4 13" a 1470×956: notch 179 × 32 pt (informe §3.2).
    let air13 = NotchMetrics(width: 179, height: 32, isHardware: true)

    func testMeasureFromScreenValues() {
        let aux = (1470.0 - 179) / 2
        let m = NotchMetrics.measure(screenWidth: 1470, safeAreaTop: 32, auxLeftWidth: aux, auxRightWidth: aux)
        XCTAssertEqual(m?.width ?? 0, 179, accuracy: 0.001)
        XCTAssertEqual(m?.height, 32)
        XCTAssertNil(NotchMetrics.measure(screenWidth: 1920, safeAreaTop: 0, auxLeftWidth: nil, auxRightWidth: nil))
    }

    func testFineAdjustIsClamped() {
        let a = air13.adjusted(dw: 50, dh: -50)
        XCTAssertEqual(a.width, 189)
        XCTAssertEqual(a.height, 26)
    }

    func testHiddenMatchesNotch() {
        let s = IslandGeometry.size(for: .hidden, notch: air13, screenWidth: 1470, screenHeight: 956)
        XCTAssertEqual(s.width, 179)
        XCTAssertEqual(s.height, 32)
    }

    func testNormalStatesNeverExceedNotchPlusWings() {
        for state in IslandState.allCases where state != .assistant {
            let s = IslandGeometry.size(for: state, notch: air13, screenWidth: 1470, screenHeight: 956)
            XCTAssertLessThanOrEqual(s.width, 179 + 2 * 40 * 1.0 + 0.001, "\(state)")
            XCTAssertGreaterThanOrEqual(s.width, 179, "\(state)")
        }
    }

    func testAssistantIsWiderAndBounded() {
        let s = IslandGeometry.size(for: .assistant, notch: air13, screenWidth: 1470, screenHeight: 956)
        XCTAssertGreaterThan(s.width, 400)
        XCTAssertLessThanOrEqual(s.width, 1470 * 0.4 + 0.001)
        XCTAssertLessThanOrEqual(s.height, 956 * 0.6)
    }

    func testSimulatedNotch() {
        let n = NotchMetrics.simulated(screenWidth: 1920, menuBarHeight: 24)
        XCTAssertFalse(n.isHardware)
        XCTAssertEqual(n.width, 1920 * 0.122, accuracy: 0.01)
    }

    func testMaxSizeContainsEverything() {
        let max = IslandGeometry.maxSize(notch: air13, screenWidth: 1470, screenHeight: 956)
        for state in IslandState.allCases {
            let s = IslandGeometry.size(for: state, notch: air13, screenWidth: 1470, screenHeight: 956)
            XCTAssertLessThanOrEqual(s.width, max.width)
            XCTAssertLessThanOrEqual(s.height, max.height)
        }
    }
}
