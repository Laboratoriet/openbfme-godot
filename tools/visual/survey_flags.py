#!/usr/bin/env python3
"""The visual survey's automatic flags (lane VIS-1), computed from the probes and raw crops godot/scripts/vissurvey_player.gd writes.

  python3 tools/visual/survey_flags.py --data <vis-data> --sheets <vis-out> --logs <run logs...> --out <flags.json>

Per object and configuration (renderer x shadow detail), each flag with its value, threshold and evidence (a sheet path, a phase and a cell, or
an evidence image written next to the sheets):
  hover        the lowest posed pivot (the feet pivots, else any pivot off the model origin) above the terrain while idle on the flat spot, beyond
               max(HOVER_MIN, HOVER_SHARE x the model's posed height); also on the slope (the same minus the flat value); the drawable's own
               height above the terrain separately (a flyer's is expected)
  slide        the move phase's feet, every render frame, while the lowest foot touches the ground (the planted one): the unit's speed over the
               foot's speed against the body (Night 4's measure: 1 = the stride matches); flagged outside STRIDE_LO .. STRIDE_HI
  tpose        a posed skinned entry that plays no clip (the bind pose); frozen: the feet keep their place relative to the body through a move
  missing      an entry whose model is not in the archives; magenta texels (the missing-texture colour) or a mostly black object in the still crop;
               the run's log lines about a missing model / texture / animation between the object's BEGIN and END
  flicker      pixels that change between three consecutive frames of the paused game (z-fighting, unstable sorting)
  ring         a unit or hero selected with no selection decal (structures have none in retail: no structure ExperienceLevel has a SelectionDecal)
  bar          a hero, monster, machine or structure selected with no health bar (retail gives infantry and cavalry none: RW 0x676346)
  shadow       the shadow's pixels (the still frame against the same frame with the shadows off) where the INI declares a shadow the detail level
               draws in retail
  house        no player colour: the object's crop against an enemy-owned twin's, the share of texels near each player's hue
Nothing retail is stored in git: the probes and the sheets live outside the repository.
"""
from __future__ import annotations

import argparse
import colorsys
import glob
import json
import math
import os
import re
import statistics
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HOVER_MIN = 4.0
HOVER_SHARE = 0.06
STRIDE_LO, STRIDE_HI = 0.7, 1.45
SLIDE_MIN_SPEED = 8.0
CONTACT = 0.8
WINDOW = 0.6
FLICKER_SHARE = 0.004
MAGENTA_SHARE = 0.003
BLACK_SHARE = 0.25
SHADOW_SHARE = 0.002
HOUSE_DELTA = 0.002

# kShadowTypeNames (W3DModelDrawNameLists.inc): bit i is the name's index
SHADOW_NAMES = ["SHADOW_DECAL", "SHADOW_VOLUME", "SHADOW_VOLUME_NEW", "SHADOW_DYNAMIC_PROJECTION", "SHADOW_DIRECTIONAL_PROJECTION",
                "SHADOW_ALPHA_DECAL", "SHADOW_ADDITIVE_DECAL", "SHADOW_VOLUME_NON_SELF_1", "SHADOW_VOLUME_NON_SELF_2", "SHADOW_VOLUME_NON_SELF_3",
                "SHADOW_ALPHA_DECAL_DYNAMIC", "SHADOW_ADDITIVE_DECAL_DYNAMIC", "SHADOW_MERGE_DECAL", "SHADOW_DECAL_TERRAIN_CLAIM",
                "SHADOW_VOLUME_OR_DECAL", "SHADOW_VOLUME_NEW_OR_DECAL", "SHADOW_SUBTRACT_DECAL_DYNAMIC"]
VOLUME_BITS = (1 << 1) | (1 << 2) | (1 << 7) | (1 << 8) | (1 << 9) | (1 << 14) | (1 << 15)
DECAL_BITS = (1 << 0) | (1 << 5) | (1 << 6) | (1 << 10) | (1 << 11) | (1 << 12) | (1 << 16)
OR_DECAL_BITS = (1 << 14) | (1 << 15)
LOG_MISSING = re.compile(r"(missing|not found|cannot (load|find|open)|no such (model|texture|anim)|unresolved|failed to load)", re.I)


def shadow_names(bits: int) -> list[str]:
    return [n for i, n in enumerate(SHADOW_NAMES) if bits & (1 << i)]


def expected_shadow(bits: int, lod: int) -> str:
    """What retail draws for these bits at this ShadowLOD (1 Low, 2 Medium, 3 High, 4 UltraHigh): "map", "blob", "map?" (a SHADOW_DECAL object at
    High / UltraHigh: RotWK's shadow map caster set, RW 0x47C276, is not read: docs/OBJECT_SHADOWS.md), or "" (none)."""
    if not bits:
        return ""
    if lod >= 3:
        if bits & VOLUME_BITS:
            return "map"
        return "map?" if bits & DECAL_BITS else ""
    if lod >= 1:
        if bits & DECAL_BITS or bits & OR_DECAL_BITS:
            return "blob"
        if bits & VOLUME_BITS and lod == 2:
            return "map"
    return ""


def load_rgb(path: str) -> np.ndarray | None:
    if not os.path.exists(path):
        return None
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)


def hue_share(img: np.ndarray, argb: int) -> float:
    """the share of saturated texels within 0.06 of the player colour's hue"""
    r, g, b = ((argb >> 16) & 255) / 255.0, ((argb >> 8) & 255) / 255.0, (argb & 255) / 255.0
    h0, s0, v0 = colorsys.rgb_to_hsv(r, g, b)
    if s0 < 0.2:
        return 0.0  # a grey / white player colour: no hue to look for
    f = img.astype(np.float32) / 255.0
    mx = f.max(axis=2)
    mn = f.min(axis=2)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0)
    rr, gg, bb = f[..., 0], f[..., 1], f[..., 2]
    h = np.zeros_like(mx)
    m = d > 1e-6
    hr = np.where(m & (mx == rr), ((gg - bb) / np.maximum(d, 1e-6)) % 6, 0)
    hg = np.where(m & (mx == gg) & (mx != rr), (bb - rr) / np.maximum(d, 1e-6) + 2, 0)
    hb = np.where(m & (mx == bb) & (mx != rr) & (mx != gg), (rr - gg) / np.maximum(d, 1e-6) + 4, 0)
    h = (hr + hg + hb) / 6.0
    dh = np.abs(h - h0)
    dh = np.minimum(dh, 1 - dh)
    sel = (dh < 0.06) & (s > 0.35) & (mx > 0.2)
    return float(sel.mean())


def lowest(member: dict) -> tuple[float | None, float, str]:
    """(the lowest foot / pivot above the terrain, the posed height, its name) of a member's posed entries"""
    best, height, name = None, 0.0, ""
    for e in member.get("entries", []):
        if "min_bone_g" not in e:
            continue
        height = max(height, float(e.get("height", 0.0)))
        cands = [(float(f[3]), f[0]) for f in e.get("feet", [])]
        if not cands:
            cands = [(float(e["min_bone_g"]), e.get("min_bone", ""))]
        for v, n in cands:
            if best is None or v < best:
                best, name = v, n
    return best, height, name


def slide_of(samples: list) -> dict:
    """the planted foot against the body over the move samples (one per render frame). The drawable's position may step with the logic frames, so
    the body's velocity is taken over a WINDOW-second window, and the feet relative to the body (the posed model, smooth every frame)."""
    rows = [(float(s[0]) / 1000.0, float(s[2]), float(s[3]), s[7]) for s in samples if len(s) >= 8 and s[7]]
    if len(rows) < 20:
        return {}
    # ground contact: the lowest foot within CONTACT of the lowest any foot reached during the move (a run's flight phase is left out)
    floor = min(f[2] for r in rows for f in r[3])

    def body_velocity(i: int) -> tuple[float, float] | None:
        t0 = rows[i][0]
        j0 = next((j for j in range(i, -1, -1) if t0 - rows[j][0] >= WINDOW / 2), None)
        j1 = next((j for j in range(i, len(rows)) if rows[j][0] - t0 >= WINDOW / 2), None)
        if j0 is None or j1 is None:
            return None
        dt = rows[j1][0] - rows[j0][0]
        return ((rows[j1][1] - rows[j0][1]) / dt, (rows[j1][2] - rows[j0][2]) / dt)

    pts = []
    for i in range(1, len(rows)):
        (t, x, y, feet), (pt, px, py, pfeet) = rows[i], rows[i - 1]
        dt = t - pt
        if not (0.004 < dt < 0.1) or len(feet) != len(pfeet):
            continue
        vb = body_velocity(i)
        if vb is None or math.hypot(*vb) < SLIDE_MIN_SPEED:
            continue
        k = min(range(len(feet)), key=lambda n: feet[n][2])  # the planted foot: the lowest
        if feet[k][2] >= floor + CONTACT or pfeet[k][2] >= floor + CONTACT:
            continue
        # the foot relative to the body (the model's own motion): world foot minus the drawable's position, in both frames
        rvx = ((feet[k][0] - x) - (pfeet[k][0] - px)) / dt
        rvy = ((feet[k][1] - y) - (pfeet[k][1] - py)) / dt
        sb = math.hypot(*vb)
        pts.append((sb, math.hypot(rvx, rvy) / sb, math.hypot(vb[0] + rvx, vb[1] + rvy) / sb))
    if not pts:
        return {}
    top = sorted(p[0] for p in pts)[max(0, int(len(pts) * 0.9) - 1)]
    pts = [p for p in pts if p[0] >= 0.75 * top]  # the steady run only (not the start, the stop or a turn)
    if len(pts) < 10:
        return {}
    return {"slip": round(statistics.median(p[2] for p in pts), 3), "stride_ratio": round(statistics.median(p[1] for p in pts), 3),
            "body_speed": round(statistics.median(p[0] for p in pts), 1), "n": len(pts)}


def frozen_of(samples: list) -> bool | None:
    """True when the feet keep their place relative to the body while it moves (a frozen pose)"""
    rels, moved = [], 0.0
    first = None
    for s in samples:
        if len(s) < 8 or not s[7]:
            continue
        x, y = float(s[2]), float(s[3])
        if first is None:
            first = (x, y)
        moved = max(moved, math.hypot(x - first[0], y - first[1]))
        rels.append([(f[0] - x, f[1] - y, f[2]) for f in s[7]])
    if moved < 20.0 or len(rels) < 10:
        return None
    spread = 0.0
    for i in range(len(rels[0])):
        for c in range(3):
            vals = [r[i][c] for r in rels if len(r) == len(rels[0])]
            spread = max(spread, statistics.pstdev(vals))
    return spread < 0.05


def object_log_lines(logs: list[str]) -> dict:
    """(config, template) -> the log lines about missing assets between its BEGIN and END"""
    out: dict = {}
    for log in logs:
        config = "-".join(Path(log).stem.replace("run-", "").split("-")[:2])  # run-<renderer>-<detail>[-<part>].log
        cur = None
        for line in open(log, errors="replace"):
            m = re.match(r"VISSURVEY BEGIN (\S+) (\S+)", line)
            if m:
                cur = m.group(2)
                continue
            if line.startswith("VISSURVEY END"):
                cur = None
                continue
            if cur and LOG_MISSING.search(line) and "VISSURVEY" not in line:
                out.setdefault((config, cur), []).append(line.strip()[:240])
    return out


BAR_KINDS = {"HERO", "MACHINE", "MONSTER", "MINE", "STRUCTURE", "HAS_HEALTH_BAR"}


def bar_expected(kinds: list[str]) -> bool:
    """RW 0x676346 (DrawableIconUI.cpp wantsHealthBar): the kinds a selected object shows a bar for with retail's settings"""
    k = set(kinds)
    if not (k & BAR_KINDS) or k & {"HORDE", "UNATTACKABLE", "ROCK_VENDOR", "WALL_UPGRADE"}:
        return False
    return not ("DEFENSIVE_WALL" in k and "HAS_HEALTH_BAR" not in k)


def analyse(path: str, sheets: str, log_lines: dict, kindof: dict | None = None) -> dict:
    p = json.load(open(path))
    base = path[:-5]
    config, faction, template, kind = p["config"], p["faction"], p["template"], p["kind"]
    kinds = (kindof or {}).get(template, [])
    lod = int(p.get("shadow_lod", 0))
    sheet = f"{sheets}/{faction}/{template}-{config}.jpg"
    flags = []
    info: dict = {"notes": p.get("notes", [])}
    phases = {ph["phase"]: ph for ph in p.get("phases", [])}

    def cells(name):
        return phases.get(name, {}).get("cells", [])

    # missing model / log lines
    models, clips, bits = set(), set(), 0
    for ph in p.get("phases", []):
        for c in ph["cells"]:
            for m in c.get("members", []):
                for e in m.get("entries", []):
                    models.add(e.get("model", ""))
                    if e.get("clip"):
                        clips.add(e["clip"])
                    bits |= int(e.get("shadow_bits", 0))
                    if e.get("missing"):
                        flags.append({"kind": "missing", "what": f"model {e.get('model')} is not in the archives", "phase": ph["phase"]})
    info["models"] = sorted(m for m in models if m)
    info["shadow"] = shadow_names(bits)
    lines = log_lines.get((config, template), []) + list(p.get("asset_errors", []))
    if lines:
        flags.append({"kind": "missing", "what": f"{len(lines)} log line(s): {lines[0]}", "lines": lines[:6]})
    if not p.get("ok", True):
        flags.append({"kind": "missing", "what": "the object could not be made or filmed: " + "; ".join(p.get("notes", []))})
        return {"config": config, "faction": faction, "template": template, "kind": kind, "sheet": sheet, "flags": flags, "info": info}

    idle = cells("idle") or cells("finished")
    # hover (units / heroes)
    if kind != "building" and idle:
        vals, heights, names, zg = [], [], [], []
        for c in idle:
            for m in c.get("members", []):
                if not m.get("ok"):
                    continue
                lo, h, n = lowest(m)
                zg.append(float(m.get("z_g", 0.0)))
                if lo is not None:
                    vals.append(lo - float(m.get("z_g", 0.0)))  # above the drawable's own base
                    heights.append(h)
                    names.append(n)
        if vals:
            v = statistics.median(vals)
            h = statistics.median(heights) if heights else 0.0
            thr = max(HOVER_MIN, HOVER_SHARE * h)
            info["hover"] = {"lowest": round(v, 2), "height": round(h, 1), "threshold": round(thr, 2), "pivot": max(set(names), key=names.count)}
            if v > thr:
                flags.append({"kind": "hover", "what": f"lowest pivot {info['hover']['pivot']} {v:.1f} above the ground (threshold {thr:.1f}, model "
                              f"height {h:.0f})", "phase": "idle"})
            if v < -thr:
                flags.append({"kind": "sunk", "what": f"lowest pivot {v:.1f} below the ground", "phase": "idle"})
        if zg:
            z = statistics.median(zg)
            info["drawable_above_ground"] = round(z, 2)
            if z > 3.0 and not {"AIRCRAFT", "FLYING"} & set(kinds):
                flags.append({"kind": "hover-drawable", "what": f"the drawable stands {z:.1f} above the terrain (a flyer's is expected)", "phase": "idle"})
        sl = cells("slope")
        if sl and vals:
            sv = []
            for c in sl:
                for m in c.get("members", []):
                    lo, _, _ = lowest(m) if m.get("ok") else (None, 0, "")
                    if lo is not None:
                        sv.append(lo - float(m.get("z_g", 0.0)))
            if sv:
                d = statistics.median(sv) - statistics.median(vals)
                info["slope_extra"] = round(d, 2)
                if d > max(HOVER_MIN, HOVER_SHARE * h):
                    flags.append({"kind": "hover-slope", "what": f"the lowest pivot is {d:.1f} higher on the slope than on the flat", "phase": "slope"})
    # slide / frozen (move samples)
    samples = p.get("samples", [])
    if kind != "building" and samples:
        s = slide_of(samples)
        if s:
            info["slide"] = s
            # Night 4's measure: the unit's speed / the planted foot's speed against the body (1 = the stride matches; < 1 the feet slip
            # backwards, a treadmill; > 1 the body glides faster than the feet carry it)
            sr = s["stride_ratio"]
            s["speed_over_stride"] = round(1.0 / sr, 2) if sr > 0.01 else 99.0
            info["slide"] = s
            if not (STRIDE_LO <= s["speed_over_stride"] <= STRIDE_HI):
                flags.append({"kind": "slide", "what": f"unit speed / stride speed {s['speed_over_stride']:.2f} ({'glides' if s['speed_over_stride'] > 1 else 'treadmill'}; "
                              f"body {s['body_speed']:.0f}/s, planted foot's world speed {s['slip']:.2f} x the body's)", "phase": "move"})
        fz = frozen_of(samples)
        if fz:
            flags.append({"kind": "frozen", "what": "the feet keep their place relative to the body through the move", "phase": "move"})
    # death: the body gone within two cells of the die strip (0.8 s of game time), or a die strip that never plays a death clip
    die = cells("die")
    if kind != "building" and die:
        shown = [c for c in die if c.get("members") and c["members"][0].get("ok")]
        dclips = {e.get("clip", "") for c in shown for e in c["members"][0].get("entries", [])}
        info["die"] = {"cells_with_body": len(shown), "of": len(die), "clips": sorted(x for x in dclips if x)}
        if len(shown) <= 2:
            flags.append({"kind": "death", "what": f"the body is gone after {len(shown)} of {len(die)} die cells (0.4 s each)", "phase": "die"})
        elif not any(("DIE" in x.upper() or "DTH" in x.upper() or "DEATH" in x.upper() or "DYING" in x.upper()) for x in dclips):
            flags.append({"kind": "death", "what": "no death clip in the die strip: " + ", ".join(sorted(dclips))[:160], "phase": "die"})
    # T-pose: a skinned posed entry without a clip
    for ph in p.get("phases", []):
        if ph["phase"] in ("die", "destroyed"):
            continue
        for c in ph["cells"]:
            for m in c.get("members", [])[:1]:
                for e in m.get("entries", []):
                    if e.get("posed") and int(e.get("bones", 0)) > 8 and not e.get("clip") and kind != "building":
                        flags.append({"kind": "tpose", "what": f"{e.get('model')} is posed with no clip (bind pose)", "phase": ph["phase"]})
                        break
    # pixels: magenta / black, flicker, shadow, house colour
    s0, s1, s2 = (load_rgb(f"{base}-still{k}.png") for k in range(3))
    if s0 is not None:
        r, g, b = s0[..., 0], s0[..., 1], s0[..., 2]
        mag = float(((r > 200) & (b > 200) & (g < 60)).mean())
        black = float(((r < 8) & (g < 8) & (b < 8)).mean())
        info["magenta"] = round(mag, 4)
        info["black"] = round(black, 4)
        if mag > MAGENTA_SHARE:
            flags.append({"kind": "missing", "what": f"{mag * 100:.1f}% magenta texels (a missing texture)", "phase": "idle", "evidence": "still0"})
        if black > BLACK_SHARE:
            flags.append({"kind": "missing", "what": f"{black * 100:.0f}% black texels", "phase": "idle", "evidence": "still0"})
    if s0 is not None and s1 is not None and s2 is not None and s0.shape == s1.shape == s2.shape:
        d1 = np.abs(s1 - s0).max(axis=2) > 24
        d2 = np.abs(s2 - s1).max(axis=2) > 24
        share = float((d1 | d2).mean())
        info["flicker"] = round(share, 4)
        if share > FLICKER_SHARE:
            ev = f"{sheets}/{faction}/{template}-{config}-flicker.jpg"
            heat = s0.astype(np.uint8).copy()
            heat[d1 | d2] = [255, 0, 255]
            Image.fromarray(np.concatenate([s0.astype(np.uint8), heat], axis=1)).save(ev, quality=82)
            flags.append({"kind": "flicker", "what": f"{share * 100:.1f}% of the crop changes between still frames", "phase": "idle", "evidence": ev})
    sh, ns = load_rgb(f"{base}-shadow.png"), load_rgb(f"{base}-noshadow.png")
    exp = expected_shadow(bits, lod)
    info["shadow_expected"] = exp
    if sh is not None and ns is not None and sh.shape == ns.shape:
        lum = lambda a: 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
        dark = float(((lum(ns) - lum(sh)) > 10).mean())
        info["shadow_pixels"] = round(dark, 4)
        if exp and dark < SHADOW_SHARE:
            flags.append({"kind": "shadow", "what": f"no shadow pixels ({dark * 100:.2f}%) where retail draws a {exp} at ShadowLOD {lod} "
                          f"({'/'.join(info['shadow']) or 'no Shadow field'})", "phase": "idle", "evidence": "shadow/noshadow"})
    tw = load_rgb(f"{base}-twin.png")
    if s0 is not None and tw is not None and idle:
        own = 0
        for c in idle:
            for m in c.get("members", []):
                if m.get("ok"):
                    own = int(m.get("house", 0))
                    break
            if own:
                break
        enemy = int(p.get("twin_house", 0))
        if own and enemy:
            so, se = hue_share(s0, own), hue_share(s0, enemy)
            to, te = hue_share(tw, own), hue_share(tw, enemy)
            info["house"] = {"own_in_own": round(so, 4), "own_in_twin": round(to, 4), "enemy_in_twin": round(te, 4), "enemy_in_own": round(se, 4)}
            if (so - to) < HOUSE_DELTA and (te - se) < HOUSE_DELTA:
                flags.append({"kind": "house", "what": "no player colour: the crop and the enemy-owned twin's show the same hues", "phase": "idle",
                              "evidence": "still0/twin"})
    # ring / bar
    if kind != "building":
        sel_cells = cells("idle") + cells("move")
        if sel_cells and not any(c.get("sel") for c in sel_cells):
            flags.append({"kind": "ring", "what": "selected, no selection decal listed", "phase": "idle"})
        if bar_expected(kinds):
            info["bar_expected"] = True
            if sel_cells and not any(c.get("bar") for c in sel_cells):
                flags.append({"kind": "bar", "what": "selected, no health bar (KindOf " + "/".join(k for k in kinds if k in BAR_KINDS) + ")",
                              "phase": "idle"})
        imgs = set()
        for c in cells("move"):
            imgs.update(c.get("images", []))
        info["icons"] = sorted(imgs)
    else:
        if bar_expected(kinds) and cells("finished") and not any(c.get("bar") for c in cells("finished")):
            flags.append({"kind": "bar", "what": "selected structure, no health bar", "phase": "finished"})
    return {"config": config, "faction": faction, "template": template, "kind": kind, "sheet": sheet, "flags": flags, "info": info}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", required=True)
    ap.add_argument("--sheets", required=True)
    ap.add_argument("--logs", nargs="*", default=[])
    ap.add_argument("--out", required=True)
    ap.add_argument("--catalog", help="the catalog (survey_catalog.py): its KindOf table decides which objects want a health bar")
    args = ap.parse_args()
    log_lines = object_log_lines(args.logs)
    kindof = json.load(open(args.catalog)).get("kindof", {}) if args.catalog else {}
    rows = []
    for path in sorted(glob.glob(f"{args.data}/*/*/*.json")):
        rows.append(analyse(path, args.sheets, log_lines, kindof))
    Path(args.out).write_text(json.dumps(rows, indent=1))
    counts: dict = {}
    for r in rows:
        for f in r["flags"]:
            counts[(r["config"], f["kind"])] = counts.get((r["config"], f["kind"]), 0) + 1
    print(f"{len(rows)} object-configurations")
    for k in sorted(counts):
        print(f"  {k[0]:8s} {k[1]:15s} {counts[k]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
