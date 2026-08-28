from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MONITOR=(ROOT/'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()

def test_bledim_boot_settle_precedes_one_complete_breath():
    assert 'bledimBootSettleDelaySeconds: TimeInterval = 1.50' in MONITOR
    block=MONITOR.split('private func scheduleBLEDIMBootSettleReassert',1)[1].split('private func animationWriteInterval',1)[0]
    assert 'Fresh power-on boot settle scheduled' in block
    assert 'self.queuePowerUpBreath(id)' in block
    assert 'restoreDeviceState(id)' not in block

def test_bledim_boot_settle_is_cancelled_on_disconnect():
    disconnect=MONITOR.split('didDisconnectPeripheral peripheral',1)[1].split('// MARK: - CBPeripheralDelegate',1)[0]
    assert 'bledimBootSettleTasks[id]?.cancel()' in disconnect
    assert 'bledimBootSettleTasks[id] = nil' in disconnect

def test_no_repeated_v9013_recovery_loop():
    assert 'scheduleRobustSteadyStateRecovery' not in MONITOR
    assert 'rounds=3' not in MONITOR
    assert 'BLEDIM10Hz' not in MONITOR
