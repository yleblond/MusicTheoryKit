import XCTest
@testable import AppCore

final class VoiceChannelAllocatorTests: XCTestCase {

    func testFirstAllocationGetsChannelFromThePool() {
        let allocator = VoiceChannelAllocator()
        let channel = allocator.channel(forPitch: 60)
        XCTAssertTrue((1...15).contains(channel))
    }

    func testSamePitchReturnsSameChannelWhileStillHeld() {
        let allocator = VoiceChannelAllocator()
        let first = allocator.channel(forPitch: 60)
        let second = allocator.channel(forPitch: 60)
        XCTAssertEqual(first, second)
    }

    func testDifferentPitchesGetDifferentChannels() {
        let allocator = VoiceChannelAllocator()
        let a = allocator.channel(forPitch: 60)
        let b = allocator.channel(forPitch: 64)
        let c = allocator.channel(forPitch: 67)
        XCTAssertEqual(Set([a, b, c]).count, 3)
    }

    func testReleaseReturnsChannelToThePoolForReuse() {
        let allocator = VoiceChannelAllocator()
        let first = allocator.channel(forPitch: 60)
        let released = allocator.release(pitch: 60)
        XCTAssertEqual(released, first)
        let second = allocator.channel(forPitch: 64)
        XCTAssertEqual(first, second, "the freed channel should be handed back out")
    }

    func testReleasingAnUnallocatedPitchIsSafeAndReturnsNil() {
        let allocator = VoiceChannelAllocator()
        XCTAssertNil(allocator.release(pitch: 99)) // never allocated
        XCTAssertTrue((1...15).contains(allocator.channel(forPitch: 60)))
    }

    func testOverflowBeyondFifteenVoicesFallsBackToChannelZero() {
        let allocator = VoiceChannelAllocator()
        for pitch in 0..<15 {
            _ = allocator.channel(forPitch: pitch)
        }
        XCTAssertEqual(allocator.channel(forPitch: 999), 0, "16th simultaneous voice has no channel left")
    }

    func testChannelZeroIsNeverHandedOutByThePool() {
        let allocator = VoiceChannelAllocator()
        var seen: Set<Int> = []
        for pitch in 0..<15 {
            seen.insert(allocator.channel(forPitch: pitch))
        }
        XCTAssertFalse(seen.contains(0))
        XCTAssertEqual(seen, Set(1...15))
    }
}
