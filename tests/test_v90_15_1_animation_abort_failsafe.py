from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()


def test_cancelled_fade_schedules_one_shot_steady_failsafe():
    block = MONITOR.split("private func cancelBrightnessTransition", 1)[1].split("private func scheduleAnimationAbortFailsafe", 1)[0]
    assert "affectedIDs" in block
    assert "task.cancel()" in block
    assert 'scheduleAnimationAbortFailsafe(for: affectedID, reason: "brightness transition cancelled")' in block


def test_cancelled_breath_participation_schedules_one_shot_steady_failsafe():
    block = MONITOR.split("private func removeFromActiveBreath", 1)[1].split("private func scheduleStartupSessionReset", 1)[0]
    assert "let wasActive = activeBreathIDs.contains(id)" in block
    assert 'scheduleAnimationAbortFailsafe(for: id, reason: "Breath participation cancelled")' in block


def test_failsafe_yields_to_newer_light_operations():
    block = MONITOR.split("private func scheduleAnimationAbortFailsafe", 1)[1].split("private func animationWriteInterval", 1)[0]
    assert "Task.sleep(for: .milliseconds(180))" in block
    assert "self.activeBreathIDs.contains(id)" in block
    assert "self.breathPrepareTasks[id] != nil" in block
    assert "self.brightnessTransitionTasks[id] != nil" in block
    assert "self.restoreTasks[id] != nil" in block
    assert "self.overspeedWarningActiveID == id" in block
    assert "confirmedHeadlightOff" not in block
    assert '"AMBIENT FAILSAFE"' in block
    assert "self.restoreDeviceState(id)" in block


def test_failsafe_does_not_reintroduce_v9013_recovery_loop_or_transport_changes():
    assert "scheduleRobustSteadyStateRecovery" not in MONITOR
    assert "rounds=3" not in MONITOR
    assert "protocolPacing=Lotus20Hz/BLEDIM10Hz" not in MONITOR
    assert "protocolPacing=20Hz/rawBLEDIM" in MONITOR
