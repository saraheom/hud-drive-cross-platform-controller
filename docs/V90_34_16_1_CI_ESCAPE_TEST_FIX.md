# v90.34.16.1 — CI UART escaping test correction

## GitHub Actions failure

Run 93442492103 successfully compiled the iOS app target. The unit-test phase executed 266 tests and reported exactly one failure:

`V903416TimeWeatherColdOffSpeedGaugeProbeTests.testRecoveredSpeedGaugePacketsEncodeAsKivicSDKDefines`

The expected frame for `DisplaySpeedCommandPacket(command=2,p1=9,p2=3,payload=true)` omitted protocol byte-stuffing for the `p2` byte. In the HUD UART protocol, `0x02`, `0x03`, and `0x7D` inside the body are escaped as `0x7D` followed by `byte ^ 0x7D`. Therefore body byte `0x03` is encoded as `0x7D 0x7E`.

Correct wire frame:

`02 7D 7F 09 7D 7E 01 03`

Correct logical body after unescaping:

`02 09 03 01`

## Scope

Only the XCTest expectation and a static regression test are changed. No file under `ios/HUDController/` is modified relative to v90.34.16. This means the time/weather cold-session ON→OFF synchronization and all A/B/C/D0–D3 red-arc probes are unchanged.
