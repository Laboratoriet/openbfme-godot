"""tools/visual/survey_flags.py on synthetic probes (no retail files, no Godot)."""
import math
import sys
from pathlib import Path

import pytest

np = pytest.importorskip("numpy", reason="SKIP: the survey's pixel checks need numpy (not in tools/requirements-test.txt)")
pytest.importorskip("PIL", reason="SKIP: the survey's pixel checks need Pillow (not in tools/requirements-test.txt)")

sys.path.insert(0, str(Path(__file__).resolve().parent))
import survey_flags as sf  # noqa: E402


def test_expected_shadow_follows_the_detail_level():
    decal, volume, or_decal = 1 << 0, 1 << 1, 1 << 14
    assert sf.expected_shadow(decal, 1) == "blob"
    assert sf.expected_shadow(decal, 4) == "map?"
    assert sf.expected_shadow(volume, 1) == ""
    assert sf.expected_shadow(volume, 2) == "map"
    assert sf.expected_shadow(volume, 4) == "map"
    assert sf.expected_shadow(or_decal, 1) == "blob"
    assert sf.expected_shadow(0, 4) == ""


def walk(stride_speed: float, body_speed: float = 40.0) -> list:
    """a body moving along x at body_speed with one planted foot that the stride moves back at stride_speed (relative to the body), 60 samples/s"""
    out = []
    foot_x = 0.0
    for i in range(120):
        t = i / 60.0
        x = body_speed * t
        foot_x += (body_speed - stride_speed) / 60.0 if i else 0.0
        out.append([t * 1000.0, i // 12, x, 0.0, 0.0, "clip", 1.0, [[foot_x, 2.0, 0.5], [x + 5.0, -2.0, 6.0]]])
    return out


def test_slide_is_one_when_the_stride_matches():
    s = sf.slide_of(walk(40.0))
    assert s["slip"] == 0.0
    assert s["stride_ratio"] == 1.0


def test_slide_reads_a_treadmill_and_a_glide():
    tread = sf.slide_of(walk(70.0))  # the feet run faster than the body: speed / stride 40 / 70
    glide = sf.slide_of(walk(20.0))  # the feet carry half the speed
    assert math.isclose(1.0 / tread["stride_ratio"], 40.0 / 70.0, rel_tol=1e-3)  # tolerance: float sums over 120 samples
    assert math.isclose(1.0 / glide["stride_ratio"], 2.0, rel_tol=1e-3)  # tolerance: float sums over 120 samples


def test_hue_share_finds_the_player_colour():
    img = np.zeros((10, 10, 3), dtype=np.int16)
    img[:5] = [200, 30, 30]  # half red
    assert sf.hue_share(img, 0xFFC81E1E) == 0.5
    assert sf.hue_share(img, 0xFF1E1EC8) == 0.0
