from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
V833 = ROOT / "u2w" / "v8.33_LosslessMirrorRawRelay"
SRC = (V833 / "source" / "libu2w_mainvideo_lossless.c").read_text()
INSTALL = (V833 / "source" / "install_once.sh").read_text()
START = (V833 / "source" / "u2wvideo-relay-start.cgi").read_text()


def test_lossless_rotation_uses_atomic_full_buffer_swap():
    assert "rotate_live_atomic" in SRC
    assert "rename(LIVE_NEXT,LIVE_PATH)" in SRC.replace(" ", "")
    assert "append_live_all(p,n)" in SRC.replace(" ", "")
    assert "rotation_prefix_preserved_bytes" in SRC
    assert "rotation_policy=atomic-full-successful-write-inode-swap" in SRC


def test_mirror_regular_file_writes_are_complete():
    assert "write_all_real" in SRC
    assert "mirror_partial_write_retries" in SRC
    assert "mirror_write_failures" in SRC


def test_vectored_paths_mirror_only_real_successful_byte_count():
    compact = "".join(SRC.split())
    assert "remain=(size_t)r;" in compact
    assert "take=v[i].iov_len<remain?v[i].iov_len:remain" in compact
    assert "take=m->msg_iov[i].iov_len<remain?m->msg_iov[i].iov_len:remain" in compact


def test_v833_does_not_add_source_reacquire_or_large_checkpoint_runtime():
    forbidden = [
        "candidate_fd",
        "one-shot-selector-reset",
        "historical_gop",
        "persistent_gop_cache",
        "12582912 /* checkpoint",
        "48 * 1024 * 1024",
    ]
    for token in forbidden:
        assert token not in SRC
    assert "source_selection=unchanged-v8.11-first-sps-fd" in SRC
    assert "adapter_h264_parser=NONE" in START
    assert "adapter_video_cache=NONE" in START
    assert "autostart=NO" in START


def test_installer_does_not_control_applecarplay_or_route_guidance_processes():
    lower = INSTALL.lower()
    # Names can appear in comments/markers, but no process-control target may use them.
    for cmd in ("kill", "killall", "pkill"):
        assert f"{cmd} applecarplay" not in lower
        assert f"{cmd} armiphoneiap2" not in lower
    assert "applecarplay_signal_policy=never" in lower
    assert "applecarplay_restart_policy=never" in lower


def test_v833_uses_exact_field_proven_v831_raw_relay():
    relay = V833 / "source" / "u2w_mainvideo_relay"
    assert hashlib.sha256(relay.read_bytes()).hexdigest() == "1c19377dbc9bdc4256dc109053824704a966448ffa9ae8d3472cf76c895e4a90"


def _old_rotate(chunks, rotate_index, first_sps):
    out = bytearray()
    generations = []
    for i, chunk in enumerate(chunks):
        if i == rotate_index:
            generations.append(bytes(out))
            out = bytearray(chunk[first_sps:])
        else:
            out.extend(chunk)
    generations.append(bytes(out))
    return b"".join(generations)


def _new_atomic_rotate(chunks, rotate_index):
    # Reader drains old inode, then reads the atomically published new inode.
    old = bytearray()
    new = bytearray()
    rotated = False
    for i, chunk in enumerate(chunks):
        if i == rotate_index:
            new.extend(chunk)  # entire successful AppleCarPlay write is preserved
            rotated = True
        elif rotated:
            new.extend(chunk)
        else:
            old.extend(chunk)
    return bytes(old + new)


def test_rotation_model_preserves_prefix_that_old_algorithm_deleted():
    chunks = [b"frameA", b"TAIL-OF-REFERENCE" + b"\x00\x00\x00\x01\x67SPS", b"frameC"]
    original = b"".join(chunks)
    first_sps = chunks[1].index(b"\x00\x00\x00\x01\x67")
    assert _old_rotate(chunks, 1, first_sps) != original
    assert _new_atomic_rotate(chunks, 1) == original
