import XCTest
@testable import HUDController

// v66 compatibility overwrite.
// The experimental persistent-music UI was removed after field testing showed
// that PushMessage text did not render on the physical HUD.
final class V58ExperimentalMusicBindingTests: XCTestCase {}
