import Foundation
import XCTest
@testable import HUDController

final class V90352434AdapterWiFiCredentialsTests: XCTestCase {
    func testUnstoredSSIDUsesVisibleDefaultButPasswordIsStillRequired() {
        let suite = "hud-adapter-credentials-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(HUDU2WAdapterWiFiCredentials.current(defaults: defaults).ssid, "NISSAN68")
        XCTAssertEqual(HUDU2WAdapterWiFiCredentials.missingField(defaults: defaults), "password")
        XCTAssertNil(defaults.object(forKey: HUDU2WAdapterWiFiCredentials.ssidKey))

        defaults.set("my-secret-password", forKey: HUDU2WAdapterWiFiCredentials.passwordKey)
        XCTAssertNil(HUDU2WAdapterWiFiCredentials.missingField(defaults: defaults))
    }

    func testExplicitlyClearedSSIDDoesNotSilentlyUseDefault() {
        let suite = "hud-adapter-credentials-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        HUDU2WAdapterWiFiCredentials.save(ssid: "   ", password: "test", defaults: defaults)
        XCTAssertEqual(HUDU2WAdapterWiFiCredentials.missingField(defaults: defaults), "network name")
        HUDU2WAdapterWiFiCredentials.save(ssid: "  MyAdapter  ", password: "test", defaults: defaults)
        XCTAssertEqual(HUDU2WAdapterWiFiCredentials.current(defaults: defaults).ssid, "MyAdapter")
        XCTAssertNil(HUDU2WAdapterWiFiCredentials.missingField(defaults: defaults))
    }
}
