"""Riding horse with tack as a separate mesh. Faces -Y like the soldier."""
import math

from common import Animator, MeshBuilder, export_glb, make_armature, reset_scene

X = 0.16


def bones():
    out = [
        ("Hips", None, (0, 0.55, 1.25), (0, 0.20, 1.28)),
        ("Spine", "Hips", (0, 0.20, 1.28), (0, -0.20, 1.30)),
        ("Chest", "Spine", (0, -0.20, 1.30), (0, -0.52, 1.35)),
        ("Neck1", "Chest", (0, -0.52, 1.35), (0, -0.75, 1.62)),
        ("Neck2", "Neck1", (0, -0.75, 1.62), (0, -0.92, 1.85)),
        ("Head", "Neck2", (0, -0.92, 1.85), (0, -1.28, 1.60)),
        ("Saddle", "Spine", (0, -0.02, 1.58), (0, -0.02, 1.70)),
        ("Tail1", "Hips", (0, 0.84, 1.33), (0, 0.97, 1.12)),
        ("Tail2", "Tail1", (0, 0.97, 1.12), (0, 1.02, 0.85)),
        ("Tail3", "Tail2", (0, 1.02, 0.85), (0, 1.02, 0.55)),
    ]
    for side, s in (("Left", 1), ("Right", -1)):
        out += [
            (side + "FrontUpper", "Chest", (s * X, -0.42, 1.20), (s * X, -0.38, 0.85)),
            (side + "FrontFore", side + "FrontUpper", (s * X, -0.38, 0.85), (s * X, -0.42, 0.50)),
            (side + "FrontCannon", side + "FrontFore", (s * X, -0.42, 0.50), (s * X, -0.42, 0.18)),
            (side + "FrontHoof", side + "FrontCannon", (s * X, -0.42, 0.18), (s * X, -0.46, 0.02)),
            (side + "HindThigh", "Hips", (s * X, 0.50, 1.15), (s * X, 0.38, 0.82)),
            (side + "HindGaskin", side + "HindThigh", (s * X, 0.38, 0.82), (s * X, 0.64, 0.52)),
            (side + "HindCannon", side + "HindGaskin", (s * X, 0.64, 0.52), (s * X, 0.60, 0.18)),
            (side + "HindHoof", side + "HindCannon", (s * X, 0.60, 0.18), (s * X, 0.56, 0.02)),
        ]
    return out


def build_body(arm):
    m = MeshBuilder("horse", seed=51, jitter=1, grad=1.5)
    coat = "horse_bay"
    barrel = [
        ((0, 0.86, 1.22), 0.08, 0.10, {"Hips": 1}),
        ((0, 0.76, 1.22), 0.21, 0.23, {"Hips": 1}),
        ((0, 0.52, 1.20), 0.28, 0.31, {"Hips": 1}),
        ((0, 0.22, 1.17), 0.29, 0.33, {"Hips": 0.5, "Spine": 0.5}),
        ((0, -0.08, 1.16), 0.285, 0.36, {"Spine": 1}),
        ((0, -0.36, 1.19), 0.25, 0.38, {"Spine": 0.3, "Chest": 0.7}),
        ((0, -0.54, 1.23), 0.18, 0.31, {"Chest": 1}),
        ((0, -0.63, 1.30), 0.09, 0.19, {"Chest": 1}),
    ]
    m.tube(barrel, coat, sides=12)
    m.tube([
        ((0, -0.45, 1.34), 0.135, 0.28, {"Chest": 1}),
        ((0, -0.66, 1.58), 0.10, 0.20, {"Chest": 0.3, "Neck1": 0.7}),
        ((0, -0.82, 1.78), 0.082, 0.15, {"Neck1": 0.4, "Neck2": 0.6}),
        ((0, -0.93, 1.90), 0.066, 0.115, {"Neck2": 0.6, "Head": 0.4}),
    ], coat, sides=10)
    h = {"Head": 1}
    m.tube([
        ((0, -0.91, 1.94), 0.065, 0.09, h),
        ((0, -1.01, 1.87), 0.08, 0.125, h),
        ((0, -1.18, 1.72), 0.058, 0.082, h),
        ((0, -1.32, 1.58), 0.052, 0.07, h),
        ((0, -1.385, 1.51), 0.032, 0.04, h),
    ], coat, sides=8)
    for s in (1, -1):
        m.cone((s * 0.05, -0.92, 1.98), 0.028, 0.13, coat, sides=5, w=h, ry=0.018)
        m.box((s * 0.078, -1.02, 1.90), (0.012, 0.04, 0.025), "black", h)
        m.box((s * 0.04, -1.375, 1.525), (0.012, 0.018, 0.018), "black", h)
    # Mane: a tall thin ridge along the top of the neck.
    mane = [
        ((0, -0.40, 1.60), 0.018, 0.04, {"Chest": 1}),
        ((0, -0.58, 1.76), 0.025, 0.075, {"Neck1": 1}),
        ((0, -0.76, 1.92), 0.025, 0.08, {"Neck1": 0.4, "Neck2": 0.6}),
        ((0, -0.90, 2.04), 0.022, 0.06, {"Head": 1}),
        ((0, -1.02, 2.0), 0.02, 0.03, {"Head": 1}),
    ]
    m.tube(mane, "horse_dark", sides=4, xhint=(1, 0, 0))
    # Tail.
    m.tube([
        ((0, 0.84, 1.33), 0.03, 0.03, {"Hips": 1}),
        ((0, 0.95, 1.16), 0.06, 0.05, {"Tail1": 1}),
        ((0, 1.01, 0.86), 0.075, 0.06, {"Tail1": 0.3, "Tail2": 0.7}),
        ((0, 1.03, 0.58), 0.05, 0.05, {"Tail2": 0.3, "Tail3": 0.7}),
        ((0, 1.02, 0.42), 0.012, 0.012, {"Tail3": 1}),
    ], "horse_dark", sides=6, xhint=(1, 0, 0))

    for side, s in (("Left", 1), ("Right", -1)):
        u, f, c, k = (side + n for n in ("FrontUpper", "FrontFore", "FrontCannon", "FrontHoof"))
        x = s * X
        m.tube([
            ((x, -0.44, 1.26), 0.095, 0.15, {"Chest": 0.6, u: 0.4}, coat),
            ((x, -0.39, 1.02), 0.085, 0.115, {u: 1}, coat),
            ((x, -0.385, 0.87), 0.066, 0.08, {u: 0.6, f: 0.4}, coat),
            ((x, -0.40, 0.69), 0.05, 0.06, {f: 1}, coat),
            ((x, -0.42, 0.52), 0.04, 0.052, {f: 0.7, c: 0.3}, "horse_dark"),
            ((x, -0.42, 0.45), 0.034, 0.042, {f: 0.3, c: 0.7}, "horse_dark"),
            ((x, -0.42, 0.28), 0.028, 0.034, {c: 1}, "horse_dark"),
            ((x, -0.42, 0.18), 0.036, 0.04, {c: 0.5, k: 0.5}, "horse_dark"),
            ((x, -0.445, 0.10), 0.032, 0.036, {k: 1}, "hoof"),
            ((x, -0.46, 0.055), 0.05, 0.062, {k: 1}, "hoof"),
            ((x, -0.465, 0.0), 0.056, 0.07, {k: 1}, "hoof"),
        ], coat, sides=8)
        t, g, c, k = (side + n for n in ("HindThigh", "HindGaskin", "HindCannon", "HindHoof"))
        m.tube([
            ((x, 0.52, 1.28), 0.10, 0.20, {"Hips": 0.7, t: 0.3}, coat),
            ((x, 0.44, 1.02), 0.09, 0.15, {t: 1}, coat),
            ((x, 0.40, 0.84), 0.066, 0.09, {t: 0.5, g: 0.5}, coat),
            ((x, 0.53, 0.66), 0.044, 0.06, {g: 1}, coat),
            ((x, 0.64, 0.53), 0.036, 0.055, {g: 0.5, c: 0.5}, "horse_dark"),
            ((x, 0.63, 0.40), 0.03, 0.04, {c: 1}, "horse_dark"),
            ((x, 0.60, 0.20), 0.034, 0.04, {c: 0.6, k: 0.4}, "horse_dark"),
            ((x, 0.575, 0.10), 0.032, 0.036, {k: 1}, "hoof"),
            ((x, 0.56, 0.055), 0.05, 0.062, {k: 1}, "hoof"),
            ((x, 0.555, 0.0), 0.056, 0.07, {k: 1}, "hoof"),
        ], coat, sides=8)
    m.finish(arm, smooth_angle=55)


def arc(y, zc, rx, rz, a0, a1, steps, grow):
    pts = []
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        pts.append((math.sin(a) * (rx + grow), y, zc + math.cos(a) * (rz + grow)))
    return pts


def wrap(y, zc, rx, rz, a0, a1, steps, inner, outer):
    return arc(y, zc, rx, rz, a0, a1, steps, outer) + list(reversed(arc(y, zc, rx, rz, a0, a1, steps, inner)))


def build_tack(arm):
    m = MeshBuilder("tack", seed=52, jitter=2)
    w = {"Spine": 1}
    # Saddle blanket over the barrel, with a pale border band.
    m.sheet([
        (wrap(0.27, 1.17, 0.29, 0.335, -68, 68, 10, 0.006, 0.018), w),
        (wrap(-0.30, 1.18, 0.27, 0.375, -68, 68, 10, 0.006, 0.018), {"Spine": 0.5, "Chest": 0.5}),
    ], "cloth_red")
    for a0, a1 in ((-68, -60), (60, 68)):
        m.sheet([
            (wrap(0.275, 1.17, 0.29, 0.335, a0, a1, 1, 0.014, 0.024), w),
            (wrap(-0.305, 1.18, 0.27, 0.375, a0, a1, 1, 0.014, 0.024), {"Spine": 0.5, "Chest": 0.5}),
        ], "cloth_bone")
    # Saddle: raised cantle and pommel with a seat between.
    m.tube([
        ((0, 0.17, 1.53), 0.14, 0.03, w),
        ((0, 0.12, 1.56), 0.15, 0.06, w),
        ((0, 0.02, 1.53), 0.14, 0.035, w),
        ((0, -0.14, 1.555), 0.14, 0.04, w),
        ((0, -0.21, 1.60), 0.12, 0.065, w),
        ((0, -0.27, 1.58), 0.07, 0.03, w),
    ], "leather", sides=8)
    # Girth strap, breast strap, stirrup straps and stirrups.
    m.sheet([
        (wrap(-0.13, 1.17, 0.285, 0.36, 60, 300, 12, 0.004, 0.014), w),
        (wrap(-0.20, 1.17, 0.28, 0.365, 60, 300, 12, 0.004, 0.014), w),
    ], "leather_dark")
    for s in (1, -1):
        m.beam((s * 0.27, -0.05, 1.42), (s * 0.34, -0.06, 0.92), 0.025, "leather_dark", w)
        m.tube([
            ((s * 0.34, -0.06, 0.93), 0.035, 0.012, w),
            ((s * 0.34, -0.06, 0.86), 0.05, 0.03, w),
            ((s * 0.34, -0.06, 0.84), 0.05, 0.03, w),
        ], "iron", sides=6, xhint=(0, 1, 0))
        m.beam((s * 0.20, -0.42, 1.40), (s * 0.13, -0.66, 1.16), 0.03, "leather_dark", {"Chest": 1})
    m.beam((-0.13, -0.66, 1.16), (0.13, -0.66, 1.16), 0.03, "leather_dark", {"Chest": 1})
    # Bridle.
    h = {"Head": 1}
    m.tube([((0, -1.27, 1.65), 0.066, 0.015, h), ((0, -1.285, 1.635), 0.066, 0.015, h)], "leather_dark", sides=8)
    m.sheet([
        (wrap(-0.97, 1.87, 0.075, 0.12, -100, 100, 6, 0.003, 0.012), h),
        (wrap(-1.0, 1.85, 0.075, 0.12, -100, 100, 6, 0.003, 0.012), h),
    ], "leather_dark")
    m.finish(arm, smooth_angle=40)


def leg_curve(p, duty, amp):
    """Returns (angle, lift). Stance runs front to back, swing returns with the leg folded."""
    p = p % 1.0
    if p < duty:
        t = p / duty
        return -amp + 2 * amp * t, 0.0
    t = (p - duty) / (1 - duty)
    return amp - 2 * amp * (0.5 - 0.5 * math.cos(t * math.pi)), math.sin(t * math.pi) ** 2


def gait_pose(f, duty, amp, phases, fold):
    pose = {}
    for side, front, hind in phases:
        a, l = leg_curve(f + front, duty, amp)
        pose[side + "FrontUpper"] = (a - 18 * l * fold, 0, 0)
        pose[side + "FrontFore"] = (-28 * l * fold, 0, 0)
        pose[side + "FrontCannon"] = (105 * l * fold, 0, 0)
        pose[side + "FrontHoof"] = (-a * 0.8 + 25 * l * fold, 0, 0)
        a, l = leg_curve(f + hind, duty, amp * 0.85)
        pose[side + "HindThigh"] = (a - 14 * l * fold, 0, 0)
        pose[side + "HindGaskin"] = (32 * l * fold, 0, 0)
        pose[side + "HindCannon"] = (-58 * l * fold, 0, 0)
        pose[side + "HindHoof"] = (-a * 0.8 + 42 * l * fold, 0, 0)
    return pose


def animate(arm):
    a = Animator(arm)

    a.begin("idle")
    for k in range(9):
        f = k / 8
        b = math.sin(f * math.tau)
        flick = math.sin(f * math.tau * 2)
        a.key(int(f * 144), {
            "Spine": (b * 0.5, 0, 0),
            "Neck1": (3 + b * 2, 0, 0), "Neck2": (2 + b * 2, b * 2, 0), "Head": (2 - b * 2, 0, b * 3),
            "Tail1": (0, flick * 4, flick * 8), "Tail2": (0, 0, flick * 12), "Tail3": (0, 0, flick * 16),
        })
    a.end()

    # Four-beat walk.
    a.begin("walk")
    keys = 16
    phases = (("Left", 0.25, 0.5), ("Right", 0.75, 0.0))
    for k in range(keys + 1):
        f = k / keys
        p = f * math.tau
        pose = gait_pose(f, 0.62, 15, phases, 0.75)
        pose["Hips"] = (math.sin(2 * p) * 1.0, 0, math.sin(p) * 1.5)
        pose["Spine"] = (0, math.sin(p) * 1.0, -math.sin(p) * 1.0)
        pose["Neck1"] = (4 + math.sin(2 * p + 0.5) * 3, 0, 0)
        pose["Neck2"] = (3 + math.sin(2 * p + 0.8) * 2, 0, 0)
        pose["Head"] = (2 + math.sin(2 * p + 1.2) * 2, 0, 0)
        pose["Tail1"] = (0, 0, math.sin(p) * 8)
        pose["Tail2"] = (0, 0, math.sin(p - 0.6) * 10)
        pose["Tail3"] = (0, 0, math.sin(p - 1.2) * 12)
        a.key(int(round(f * 32)), pose, {"Hips": (0, 0, -0.012 + math.cos(2 * p) * 0.012)})
    a.end()

    # Gallop with a moment of suspension.
    a.begin("gallop")
    keys = 12
    phases = (("Left", 0.60, 0.12), ("Right", 0.44, 0.0))
    for k in range(keys + 1):
        f = k / keys
        p = f * math.tau
        pose = gait_pose(f, 0.34, 36, phases, 1.0)
        rock = math.sin(p)
        pose["Hips"] = (rock * 5, 0, 0)
        pose["Spine"] = (-rock * 1.5, 0, 0)
        pose["Chest"] = (-rock * 2, 0, 0)
        pose["Neck1"] = (8 - rock * 7, 0, 0)
        pose["Neck2"] = (5 - rock * 5, 0, 0)
        pose["Head"] = (3 - rock * 4, 0, 0)
        pose["Tail1"] = (34 + rock * 8, 0, 0)
        pose["Tail2"] = (10 + rock * 10, 0, 0)
        pose["Tail3"] = (6 + rock * 14, 0, 0)
        a.key(int(round(f * 18)), pose, {"Hips": (0, 0, 0.03 + math.sin(p + 1.0) * 0.05)})
    a.end()

    # Rear up, paw the air, come down.
    a.begin("rear")
    a.key(0)
    hind_brace = dict(LeftHindThigh=(26, 0, 0), RightHindThigh=(26, 0, 0), LeftHindGaskin=(10, 0, 0), RightHindGaskin=(10, 0, 0),
                      LeftHindCannon=(-8, 0, 0), RightHindCannon=(-8, 0, 0))
    front_fold = dict(LeftFrontUpper=(-58, 0, 0), RightFrontUpper=(-38, 0, 0),
                      LeftFrontFore=(-16, 0, 0), RightFrontFore=(-22, 0, 0),
                      LeftFrontCannon=(95, 0, 0), RightFrontCannon=(110, 0, 0))
    a.key(14, dict(Hips=(-42, 0, 0), Neck1=(14, 0, 0), Neck2=(14, 0, 0), Head=(14, 0, 0),
                   Tail1=(38, 0, 0), Tail2=(12, 0, 0), **hind_brace, **front_fold), {"Hips": (0, -0.1, -0.13)})
    swap = dict(front_fold)
    swap.update(LeftFrontUpper=(-34, 0, 0), RightFrontUpper=(-62, 0, 0))
    a.key(24, dict(Hips=(-46, 0, 0), Neck1=(18, 0, 0), Neck2=(10, 0, 0), Head=(18, 0, 0),
                   Tail1=(42, 0, 0), Tail2=(12, 0, 0), **hind_brace, **swap), {"Hips": (0, -0.1, -0.14)})
    a.key(34, dict(Hips=(-42, 0, 0), Neck1=(14, 0, 0), Neck2=(14, 0, 0), Head=(14, 0, 0),
                   Tail1=(38, 0, 0), Tail2=(12, 0, 0), **hind_brace, **front_fold), {"Hips": (0, -0.1, -0.13)})
    a.key(48)
    a.end()


def build():
    reset_scene()
    arm = make_armature("horse_rig", bones())
    build_body(arm)
    build_tack(arm)
    animate(arm)
    export_glb("horse", animated=True)
