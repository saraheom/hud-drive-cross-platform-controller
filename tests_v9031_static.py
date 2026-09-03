from pathlib import Path
root=Path(__file__).parent
rg=(root/'ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift').read_text()
cmd=(root/'ios/HUDController/Protocol/HudCommands.swift').read_text()
obd=(root/'ios/HUDController/Vehicle/HudOBDController.swift').read_text()
app=(root/'ios/HUDController/App/AppState.swift').read_text()
ocr=(root/'ios/HUDController/Navigation/ExternalNavigationCapture.swift').read_text()
y26=(root/'ios/project-ios26-ambient.yml').read_text()
normal=(root/'ios/project.yml').read_text()
assert 'http://192.168.50.2/cgi-bin/u2wrgd-live.cgi' in rg
assert 'case googleMaps' in rg and 'case appleMaps' in rg and 'case waze' in rg
assert 'case .googleMaps: 300' in rg and 'case .appleMaps: 200' in rg and 'case .waze: 100' in rg
assert 'case 1, 20: return .left' in rg and 'case 2, 21: return .right' in rg
assert 'case 47: return .sharpLeft' in rg and 'case 50: return .slightRight' in rg
assert 'p1: 114' in cmd and 'HudProtocol.int64(arrivalTimeMilliseconds)' in cmd
assert 'fallback: .eta' in obd
assert 'routeGuidance.start(reason: "HUD BLE transport ready")' in app
assert 'routeGuidance.stop(reason: "HUD BLE transport disconnected")' in app
assert 'sendCurrent(owner: .ocr)' in ocr and 'navigationOff(owner: .ocr)' in ocr
assert 'NSLocalNetworkUsageDescription' in y26 and 'NSAllowsArbitraryLoads: true' in y26
assert 'NSLocalNetworkUsageDescription' in normal and 'NSAllowsArbitraryLoads: true' in normal
print('v90.31 static regression PASS')
