from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
OBD = (ROOT / "ios/HUDController/Vehicle/HudOBDController.swift").read_text()


def test_engine_on_requires_stable_hud_and_obd_consensus():
    assert "private enum EnginePowerConsensusObservation" in MONITOR
    assert "if hudEnginePowerSignalPresent && obdEnginePowerSignalPresent { return .bothOn }" in MONITOR
    assert "if !hudEnginePowerSignalPresent && !obdEnginePowerSignalPresent { return .bothOff }" in MONITOR
    assert "engineSignalConsensusStabilitySeconds: TimeInterval = 0.75" in MONITOR
    assert "directOBDAcquireWindowSeconds: TimeInterval = 5.0" in MONITOR
    assert 'confirmEnginePowerOn(source: "stable HUD + OBD2 consensus")' in MONITOR
    assert "Engine consensus mixed; preserving confirmed" in MONITOR


def test_direct_obd_can_veto_off_but_cannot_start_engine_session_alone():
    witness = MONITOR.split("private func recordIndependentOBDWitness", 1)[1].split("private func isDirectOBDRecentlyPresent", 1)[0]
    assert "confirmEnginePowerOn" not in witness
    assert "engineOffConfirmationTask?.cancel()" in witness
    assert "direct OBD witness present during HUD/OBD outage" in witness
    off = MONITOR.split("private func scheduleEnginePowerOffConfirmation", 1)[1].split("private func confirmEnginePowerOff", 1)[0]
    assert "!hudEnginePowerSignalPresent, !obdEnginePowerSignalPresent" in off
    assert "!isDirectOBDRecentlyPresent()" in off


def test_hud_transport_loss_publishes_obd_connection_false_for_consensus():
    block = OBD.split("func transportDisconnected()", 1)[1].split("private func startAutoConnectLoop", 1)[0]
    assert "connected = false" in block
    assert "onConnectionChanged?(false)" in block
    assert "physical OBD power remains independently witnessable" in block


def test_courtesy_power_cannot_consume_startup_breath():
    run = MONITOR.split("private func runStartupAnimationIfNeeded", 1)[1].split("private func queuePowerUpBreath", 1)[0]
    assert "courtesy gate" in run
    assert "!enginePowerPresent || !vehicleStartupCompleted || vehicleStartupAnimationPending" in run
    assert "restoreDeviceState(id)" in run
    consensus = MONITOR.split("private func scheduleHeadlightConsensusEvaluation", 1)[1].split("private func commitConfirmedHeadlightPower", 1)[0]
    assert "guard enginePowerPresent, vehicleStartupCompleted" in consensus
    assert "Headlight consensus deferred during courtesy/startup gate" in consensus


def test_vehicle_start_breath_is_one_coherent_day_or_night_admission():
    block = MONITOR.split("private func tryStartVehicleStartupBreath", 1)[1].split("/// Record positive physical-power evidence", 1)[0]
    assert "vehicleStartupAnimationPending" in block
    assert "let doorID = deviceID(for: .door)" in block
    assert "if vehicleHeadlightsActive" in block
    assert "dashboardGATTNotReady" in block
    assert "centerGATTNotReady" in block
    assert '"Vehicle-start Breath admitted mode=' in block
    assert "queuePowerUpBreath(id)" in block


def test_startup_classifier_does_not_launch_competing_door_fade():
    block = MONITOR.split("private func finishVehicleStartupClassification()", 1)[1].split("private func applyCurrentDoorDayNightTarget", 1)[0]
    assert "tryStartVehicleStartupBreath" in block
    assert "applyCurrentDoorDayNightTarget(" not in block
    assert "Do not begin a separate Door fade here" in block
