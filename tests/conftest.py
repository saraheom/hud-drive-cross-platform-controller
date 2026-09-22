from pathlib import Path

# The app-only distribution intentionally omits the repository-level u2w/ tree.
# Firmware/source integration tests remain active in the combined/full repository.
# When u2w/ is absent, ignore only test modules that directly inspect bundled U2W
# sources/images so collection and assertions reflect the intended package boundary.
_U2W_INTEGRATION_TESTS = {
    "test_v90_35_3_1_u2w_relay_stability.py",
    "test_v90_35_3_2_u2w_discovery_kick.py",
    "test_v90_35_3_6_mjpeg_stability.py",
    "test_v90_35_3_9_reliability.py",
    "test_v90_35_3_10_map_mode_ui_refinement.py",
    "test_v90_35_3_12_liveedge_obd_diagnostic.py",
    "test_v90_35_3_14_fd_reselect_route_holdover_obd_reassembly.py",
    "test_v90_35_3_15_safe_mainvideo_route_obd.py",
    "test_v90_35_3_16_iphone_mainvideo_filter.py",
    "test_v90_35_3_22_live_idr_lane_ambient_preview.py",
    "test_v90_35_3_24_recent_idr_software_center_guard.py",
    "test_v90_35_3_24_6_v825_validated_gop_recovery.py",
}


def pytest_ignore_collect(collection_path, config):
    root = Path(__file__).resolve().parents[1]
    if (root / "u2w").exists():
        return False
    return collection_path.name in _U2W_INTEGRATION_TESTS
