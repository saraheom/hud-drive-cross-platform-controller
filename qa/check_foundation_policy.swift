import Foundation

@main struct Verify {
    static func main() {
        let testCases: [(Bool, String)] = [
          (CurrentNavSpeedSwitchPolicy.needsConfirmation(previousWayID: 1, proposedWayID: 2, previousKmh: 80, proposedKmh: 65, previousDistanceMeters: 8, proposedDistanceMeters: 7, previousHeadingErrorDegrees: 5, proposedHeadingErrorDegrees: 5), "close conflicting ways require confirmation"),
          (!CurrentNavSpeedSwitchPolicy.needsConfirmation(previousWayID: 1, proposedWayID: 2, previousKmh: 80, proposedKmh: 65, previousDistanceMeters: 34, proposedDistanceMeters: 3, previousHeadingErrorDegrees: 5, proposedHeadingErrorDegrees: 5), "real transition not suppressed"),
          (!CurrentNavSpeedSwitchPolicy.needsConfirmation(previousWayID: 1, proposedWayID: 2, previousKmh: 80, proposedKmh: 80, previousDistanceMeters: 7, proposedDistanceMeters: 6, previousHeadingErrorDegrees: 5, proposedHeadingErrorDegrees: 5), "same posted limit not delayed")
        ]
        for (result, label) in testCases {
            precondition(result, "FAIL: \(label)")
            print("PASS: \(label)")
        }
    }
}
