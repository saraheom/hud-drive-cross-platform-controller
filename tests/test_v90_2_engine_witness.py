from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def test_hud_disconnect_does_not_claim_obd_power_off():
    obd = (ROOT / "ios/HUDController/Vehicle/HudOBDController.swift").read_text()
    block = obd.split("func transportDisconnected()", 1)[1].split("private func startAutoConnectLoop", 1)[0]
    assert "onConnectionChanged?(false)" not in block
    assert "physical OBD power remains unknown" in block

def test_independent_obd_witness_gates_engine_off():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "directOBDWitnessProven" in monitor
    assert "recordIndependentOBDWitness" in monitor
    assert "matchesIndependentOBDWitness" in monitor
    assert "auto-shutdown inhibited" in monitor
    assert "guard directOBDWitnessProven" in monitor
    assert "isDirectOBDRecentlyPresent" in monitor

def test_hud_disconnect_never_immediately_schedules_shutdown():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    block = monitor.split("func hudTransportPowerSignal(_ present: Bool)", 1)[1].split("func obdPowerSignal", 1)[0]
    assert "scheduleEnginePowerOffConfirmation" not in block
    assert "waiting for calibrated independent OBD witness" in block
