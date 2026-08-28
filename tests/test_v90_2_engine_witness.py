from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]


def test_hud_disconnect_publishes_obd_connection_false_for_two_signal_consensus():
    obd = (ROOT / "ios/HUDController/Vehicle/HudOBDController.swift").read_text()
    block = obd.split("func transportDisconnected()", 1)[1].split("private func startAutoConnectLoop", 1)[0]
    assert "onConnectionChanged?(false)" in block
    assert "physical OBD power remains independently witnessable" in block


def test_independent_obd_witness_is_off_veto_not_on_trigger():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "directOBDWitnessProven" in monitor
    assert "recordIndependentOBDWitness" in monitor
    assert "matchesIndependentOBDWitness" in monitor
    assert "isDirectOBDRecentlyPresent" in monitor
    witness = monitor.split("private func recordIndependentOBDWitness", 1)[1].split("private func isDirectOBDRecentlyPresent", 1)[0]
    assert "confirmEnginePowerOn" not in witness
    assert "direct OBD witness present during HUD/OBD outage" in witness


def test_hud_disconnect_uses_consensus_instead_of_immediate_shutdown():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    block = monitor.split("func hudTransportPowerSignal(_ present: Bool)", 1)[1].split("func obdPowerSignal", 1)[0]
    assert "scheduleEnginePowerOffConfirmation" not in block
    assert "scheduleEngineSignalConsensusEvaluation" in block
    assert 'present ? "HUD connected" : "HUD disconnected"' in block
