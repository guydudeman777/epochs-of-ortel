"""The clips, which build_mh_body.py keys onto the MakeHuman rig.

Upper bodies are posed by hand, in armature axes. For a limb hanging down: rx < 0 swings forward and rx > 0
swings back, and ry < 0 lifts a left limb out to the side (ry > 0 a right one). For an upright spine: rx > 0
leans forward. rz > 0 turns towards the character's left.

Legs are solved rather than posed: a clip says where each foot is on the ground and how it is pitched, and
the hip and knee follow, so a planted foot stays planted. Only death and riding still pose legs by hand.

There are two ways of standing. At ease (EASE) is for idling and travelling. On guard (GUARD_STANCE) is for
fighting: every blow, block, flinch and guarded step starts and ends in it, so they blend without the feet sliding.
"""
import math

FPS = 24.0
# Walking: metres each foot travels against the body while on the ground, the share of a cycle it spends there, and
# the cycle's length in frames. Ground speed follows from these. Running has its own Gait.
WALK_STRIDE, WALK_STANCE, WALK_FRAMES = 0.72, 0.62, 24
# How high a walking foot's ankle rises, earliest in the swing as the heel comes up and the knee bends.
WALK_LIFT, WALK_PEAK = 0.085, 0.75
# Stepping on guard: strides forward, back and sideways, and the cycle. Sideways is short so the feet never cross.
GUARD_STEP_FRAMES = 20
GUARD_STEP_FORWARD, GUARD_STEP_BACK, GUARD_STEP_SIDE = 0.5, 0.42, 0.42
GUARD_STEP_STANCE, GUARD_SIDE_STANCE = 0.58, 0.72
STEP_LIFT = 0.035


class Stance:
    """Where the feet stand and how the hips sit. A foot is (how far forward of its hip, how far out to the
    character's left of where it hangs), and turn is how far its toes point to the left, in degrees. lean tips the
    pelvis forward, in degrees, and the thighs take it up. A foot's heel is the degrees it rises off the ground, turning
    on the ball, as a back foot does when the weight drives forward off it."""

    def __init__(self, root, left, right, yaw=0.0, roll=0.0, left_turn=0.0, right_turn=0.0, lean=0.0, left_heel=0.0, right_heel=0.0):
        self.root = tuple(root)
        self.lean = lean
        self.left = tuple(left)
        self.right = tuple(right)
        self.yaw = yaw
        self.roll = roll
        self.left_turn = left_turn
        self.right_turn = right_turn
        self.left_heel = left_heel
        self.right_heel = right_heel

    def but(self, **changes):
        out = Stance(self.root, self.left, self.right, self.yaw, self.roll, self.left_turn, self.right_turn, self.lean,
                     self.left_heel, self.right_heel)
        for key, value in changes.items():
            setattr(out, key, tuple(value) if isinstance(value, (tuple, list)) else value)
        return out

    def lerp(self, other, t):
        def mix(a, b):
            return tuple(x + (y - x) * t for x, y in zip(a, b))

        def num(a, b):
            return a + (b - a) * t
        return Stance(mix(self.root, other.root), mix(self.left, other.left), mix(self.right, other.right),
                      num(self.yaw, other.yaw), num(self.roll, other.roll), num(self.left_turn, other.left_turn),
                      num(self.right_turn, other.right_turn), num(self.lean, other.lean),
                      num(self.left_heel, other.left_heel), num(self.right_heel, other.right_heel))


# Feet under the hips, toes turned out a little, knees all but straight.
EASE = Stance((0.0, 0.0, -0.012), (0.035, 0.0), (-0.04, 0.0), left_turn=4.0, right_turn=-6.0)
# Shield foot forward, sword foot back and out with its toes turned out, knees soft, and the hips turned a little
# to the sword side, so the shield leads. The seat sits back over the feet and the pelvis tips forward under a
# forward-leaning back, not tucked under.
GUARD_STANCE = Stance((-0.005, 0.016, -0.05), (0.13, 0.03), (-0.17, -0.045), yaw=-10.0, left_turn=-4.0, right_turn=-26.0, lean=9.0)


def bones():
    """The poses count from these directions. build_mh_body.py overrides how the arms and legs hang."""
    out = [
        ("Hips", None, (0, 0, 0.95), (0, 0, 1.05)),
        ("Spine", "Hips", (0, 0, 1.05), (0, 0, 1.20)),
        ("Chest", "Spine", (0, 0, 1.20), (0, 0, 1.42)),
        ("Neck", "Chest", (0, 0, 1.42), (0, 0, 1.52)),
        ("Head", "Neck", (0, 0, 1.52), (0, 0, 1.74)),
    ]
    for side, s in (("Left", 1), ("Right", -1)):
        out += [
            (side + "Shoulder", "Chest", (s * 0.04, 0, 1.40), (s * 0.19, 0, 1.42)),
            (side + "UpperArm", side + "Shoulder", (s * 0.19, 0, 1.42), (s * 0.24, 0, 1.13)),
            (side + "LowerArm", side + "UpperArm", (s * 0.24, 0, 1.13), (s * 0.27, -0.02, 0.87)),
            (side + "Hand", side + "LowerArm", (s * 0.27, -0.02, 0.87), (s * 0.28, -0.04, 0.78)),
            (side + "UpperLeg", "Hips", (s * 0.10, 0, 0.93), (s * 0.11, 0, 0.52)),
            (side + "LowerLeg", side + "UpperLeg", (s * 0.11, 0, 0.52), (s * 0.11, 0.01, 0.10)),
            (side + "Foot", side + "LowerLeg", (s * 0.11, 0.01, 0.10), (s * 0.11, -0.12, 0.03)),
            (side + "Toes", side + "Foot", (s * 0.11, -0.12, 0.03), (s * 0.11, -0.22, 0.03)),
        ]
    return out


class Legs:
    """Measures of the standing legs, and the solve from a foot on the ground to joint angles."""

    def __init__(self, thigh, calf, hip_z, hip_x, ankle_z, ball_forward, ball_z, heel_back):
        self.thigh = thigh
        self.calf = calf
        self.reach = (thigh + calf) * 0.998
        self.hip_z = hip_z
        self.hip_x = hip_x
        self.ankle_z = ankle_z
        self.ball_forward = ball_forward
        self.ball_z = ball_z
        self.heel_back = heel_back
        self.overreach = 0.0
        self.worst = ""
        self.clip = ""

    def ankle(self, plant, pitch, lift):
        """Where the ankle is, for a foot whose flat position is plant, turned about its heel or the ball."""
        p = math.radians(pitch)
        if p < 0.0:
            a = -p
            forward = plant - self.heel_back * (1.0 - math.cos(a)) - self.ankle_z * math.sin(a)
            up = self.ankle_z * math.cos(a) + self.heel_back * math.sin(a)
        else:
            rise = self.ankle_z - self.ball_z
            forward = plant + self.ball_forward * (1.0 - math.cos(p)) + rise * math.sin(p)
            up = self.ball_z + rise * math.cos(p) + self.ball_forward * math.sin(p)
        return forward, up + lift

    def pose(self, side, root, plant, pitch=0.0, lift=0.0, lean=0.0, yaw=0.0, roll=0.0, across=0.0, turn=0.0):
        """Angles for one leg. root is the root bone's move. lean, yaw and roll are the pelvis's, in degrees.
        across is how far the foot stands to the character's left of where it rests, and turn how far its toes
        point to the left."""
        s = 1.0 if side == "Left" else -1.0
        hip_forward = -root[1] - s * self.hip_x * math.sin(math.radians(yaw))
        hip_up = self.hip_z + root[2] - s * self.hip_x * math.sin(math.radians(roll))
        ankle_forward, ankle_up = self.ankle(plant, pitch, lift)
        along = ankle_forward - hip_forward
        down = hip_up - ankle_up
        distance = math.hypot(along, down)
        if distance - self.reach > self.overreach:
            self.overreach = distance - self.reach
            self.worst = self.clip
        distance = min(distance, self.reach)
        bend = math.pi - math.acos((self.thigh ** 2 + self.calf ** 2 - distance ** 2) / (2.0 * self.thigh * self.calf))
        spread = math.acos((self.thigh ** 2 + distance ** 2 - self.calf ** 2) / (2.0 * self.thigh * distance))
        forward = math.atan2(along, down) + spread
        thigh = -math.degrees(forward) - lean
        knee = math.degrees(bend)
        # The hip may stand off to one side of the foot, so the leg leans back in to reach it.
        tilt = math.degrees(math.asin(max(min((root[0] - across) / self.reach, 1.0), -1.0)))
        foot = pitch - lean - thigh - knee
        toes = -max(pitch, 0.0) * (1.0 if lift < 0.005 else 0.3)
        return {
            side + "UpperLeg": (thigh, tilt - roll, -yaw),
            side + "LowerLeg": (knee, 0, 0),
            side + "Foot": (foot, -tilt, turn),
            side + "Toes": (toes, 0, 0),
        }

    def stand(self, stance, root=None, yaw=None, roll=None, lean=None):
        """Both legs and the hips, for feet flat where the stance puts them."""
        root = stance.root if root is None else root
        lean = stance.lean if lean is None else lean
        yaw = stance.yaw if yaw is None else yaw
        roll = stance.roll if roll is None else roll
        out = {"Hips": (lean, roll, yaw)}
        for side, (plant, across), turn in (("Left", stance.left, stance.left_turn), ("Right", stance.right, stance.right_turn)):
            out.update(self.pose(side, root, plant, lean=lean, yaw=yaw, roll=roll, across=across, turn=turn))
        return out


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def foot_cycle(phase, stride, stance, heel, toe, clearance, peak=1.0):
    """Where a foot is at this point of its cycle. 0 is the moment its heel lands. peak < 1 lifts the foot
    earliest in its swing, as a runner's heel kicks up behind before the knee drives through."""
    if phase < stance:
        q = phase / stance
        if q < 0.14:
            pitch = heel * (1.0 - smooth(q / 0.14))
        elif q < 0.55:
            pitch = 0.0
        else:
            pitch = toe * smooth((q - 0.55) / 0.45)
        return stride * 0.5 - stride * q, pitch, 0.0
    r = (phase - stance) / (1.0 - stance)
    # The foot stays back while the knee comes through, then reaches.
    plant = -stride * 0.5 + stride * smooth(r ** 1.25)
    pitch = toe + (heel - toe) * smooth(r)
    lift = clearance * math.sin(math.pi * r ** peak) ** 1.3
    return plant, pitch, lift


# On guard: the sword held low in front with its point up at the other's face, the shield across the chest.
READY = {
    "RightUpperArm": (-26, 0, 12), "RightLowerArm": (-56, 0, 0), "RightHand": (30, 0, 0),
    "LeftUpperArm": (-30, 0, -22), "LeftLowerArm": (-64, 0, -26), "LeftHand": (0, 0, 0),
    "Spine": (4, 0, 4), "Chest": (4, 0, 5), "Neck": (-14, 0, 1), "Head": (-3, 0, 0),
}
# Armed and at ease: the sword hangs by the thigh with its point down and forward, the shield rides on the arm.
CARRY = {
    "RightUpperArm": (-2, 0, 4), "RightLowerArm": (-18, 0, 0), "RightHand": (44, 0, 0),
    "LeftUpperArm": (-6, 0, -8), "LeftLowerArm": (-38, 0, -12), "LeftHand": (0, 0, 0),
    "Chest": (1, 0, 0), "Neck": (-1, 0, 0),
}
# Arms at rest, for people carrying nothing.
RELAXED = {
    "LeftUpperArm": (2, 0, -4), "LeftLowerArm": (-12, 0, 0), "LeftHand": (6, 0, 0),
    "RightUpperArm": (2, 0, 4), "RightLowerArm": (-12, 0, 0), "RightHand": (6, 0, 0),
    "Chest": (1, 0, 0), "Neck": (-1, 0, 0),
}


def merged(base, **extra):
    out = dict(base)
    out.update(extra)
    return out


def nudged(pose, bone, rx=0.0, ry=0.0, rz=0.0):
    x, y, z = pose.get(bone, (0.0, 0.0, 0.0))
    pose[bone] = (x + rx, y + ry, z + rz)


def locomotion(a, legs, name, frames, stride, stance, heel, toe, clearance, drop, bob, high_point, sway, yaw_amount, roll_amount, lean, arms, peak=1.0):
    """One cycle, starting as the left heel lands."""
    a.begin(name)
    legs.clip = name
    # A key on every frame: between keys the joints turn evenly, and a planted foot would wobble along the ground.
    keys = frames
    for k in range(keys + 1):
        f = k / keys
        turn = math.tau * f
        twice = 2.0 * math.tau * (f - high_point)
        settle = math.tau * (f - stance * 0.5)
        root = (sway * math.cos(settle), 0.0, -drop + bob * math.cos(twice))
        yaw = -yaw_amount * math.cos(turn)
        roll = -roll_amount * math.cos(settle)
        pose = arms(turn)
        pose["Hips"] = (lean * 0.5, roll, yaw)
        # The shoulders turn against the hips, and the head holds still on top.
        pose["Spine"] = (lean * 0.3, -roll * 0.8, -yaw * 0.9)
        pose["Chest"] = (lean * 0.2 + pose.get("Chest", (1.0, 0, 0))[0], -roll * 0.3, -yaw * 0.9)
        pose["Neck"] = (-lean * 0.6, roll * 0.4, yaw * 0.7)
        pose["Head"] = (math.sin(twice) * lean * 0.08, 0.0, 0.0)
        for side, phase in (("Left", f % 1.0), ("Right", (f + 0.5) % 1.0)):
            plant, pitch, lift = foot_cycle(phase, stride, stance, heel, toe, clearance, peak)
            pose.update(legs.pose(side, root, plant, pitch, lift, lean * 0.5, yaw, roll))
        a.key(int(round(f * frames)), pose, {"Root": root})
    a.end()
    a.speeds[name] = stride / (stance * frames / FPS)


class Gait:
    """How a run goes. contact is the metres the body passes over a planted foot, stance the share of the cycle a
    foot is down (under a half, so both are off the ground between steps), reach the share of contact the foot lands
    ahead of the hip. kick is how high the heel comes up behind, knee how high the foot rides as the knee drives
    through, bounce how far the hips rise and fall with each step, lean the forward tip of the body in degrees."""

    def __init__(self, frames, contact, stance, reach, kick, knee, bounce, lean, land_pitch, push_pitch, arm, elbow):
        self.frames = frames
        self.contact = contact
        self.stance = stance
        self.reach = reach
        self.kick = kick
        self.knee = knee
        self.bounce = bounce
        self.lean = lean
        self.land_pitch = land_pitch
        self.push_pitch = push_pitch
        self.arm = arm
        self.elbow = elbow

    def speed(self):
        return self.contact / (self.stance * self.frames / FPS)


# A steady run: what a fighter sprints at, and what anyone hurrying goes at. About 2.6 m/s.
JOG = Gait(frames=18, contact=0.66, stance=0.36, reach=0.36, kick=0.26, knee=0.2, bounce=0.026, lean=16.0,
           land_pitch=-10.0, push_pitch=48.0, arm=30.0, elbow=98.0)
# Flat out: longer flights, the heel high behind and the knee higher in front. About 4.6 m/s.
SPRINT = Gait(frames=16, contact=0.8, stance=0.26, reach=0.32, kick=0.4, knee=0.3, bounce=0.034, lean=24.0,
              land_pitch=4.0, push_pitch=58.0, arm=44.0, elbow=90.0)


def hermite(points, r):
    """A smooth path through (r, values, slopes) points, r rising from 0 to 1. A slope of None is worked out from the
    neighbours."""
    for i in range(len(points) - 1):
        r0, v0, s0 = points[i]
        r1, v1, s1 = points[i + 1]
        if r <= r1 or i == len(points) - 2:
            h = r1 - r0
            t = (r - r0) / h
            out = []
            for k in range(len(v0)):
                def slope(j):
                    rj, vj, sj = points[j]
                    if sj is not None:
                        return sj[k]
                    ra, va, _ = points[max(j - 1, 0)]
                    rb, vb, _ = points[min(j + 1, len(points) - 1)]
                    return (vb[k] - va[k]) / (rb - ra)
                m0, m1 = slope(i) * h, slope(i + 1) * h
                t2, t3 = t * t, t * t * t
                out.append((2 * t3 - 3 * t2 + 1) * v0[k] + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * v1[k] + (t3 - t2) * m1)
            return out
    return list(points[-1][1])


def run_foot(phase, g):
    """Where a running foot is, as (plant, pitch, lift), at this point of its cycle. 0 is the moment it lands."""
    ahead = g.contact * g.reach
    behind = g.contact - ahead
    if phase < g.stance:
        q = phase / g.stance
        if q < 0.2:
            pitch = g.land_pitch * (1.0 - smooth(q / 0.2))
        elif q < 0.5:
            pitch = 0.0
        else:
            pitch = g.push_pitch * smooth((q - 0.5) / 0.5) ** 1.4
        return ahead - g.contact * q, pitch, 0.0
    # In the air: the heel kicks up behind, the knee drives the foot through high under the hip, the leg reaches,
    # and the foot sweeps back down so it is already going backwards when it lands.
    r = (phase - g.stance) / (1.0 - g.stance)
    ground = -g.contact / g.stance * (1.0 - g.stance)
    plant, lift = hermite([
        (0.0, (-behind, 0.0), (ground * 0.6, 1.6)),
        (0.3, (-behind * 0.95, g.kick), None),
        (0.56, (-0.02, g.knee + 0.04), None),
        (0.8, (ahead + 0.07, g.knee * 0.4), None),
        (1.0, (ahead, 0.0), (ground * 0.35, -0.5)),
    ], r)
    pitch = hermite([
        (0.0, (g.push_pitch,), (0.0,)),
        (0.3, (g.push_pitch + 30.0,), None),
        (0.6, (24.0,), None),
        (0.85, (g.land_pitch - 8.0,), None),
        (1.0, (g.land_pitch,), (0.0,)),
    ], r)[0]
    return plant, pitch, max(lift, 0.0)


def run_cycle(a, legs, name, g, arms):
    """One cycle of running, keyed on every frame, starting as the left foot lands. arms(turn, g) poses the upper
    body, where turn is 0 as the left foot lands and goes once round in the cycle."""
    a.begin(name)
    legs.clip = name
    frames = g.frames
    for k in range(frames + 1):
        f = k / frames
        turn = math.tau * f
        # Lowest as each foot is under the hips, highest in the flight after it pushes off.
        step = 2.0 * math.tau * (f - g.stance * 0.5)
        root = (0.012 * math.cos(math.tau * (f - g.stance * 0.5)), -0.006 * math.cos(step), -0.03 - g.bounce * 0.5 * (1.0 + math.cos(step)))
        yaw = -7.0 * math.cos(turn - 0.3)
        roll = -3.0 * math.cos(math.tau * (f - g.stance * 0.5))
        pose = arms(turn, g)
        hip_lean = g.lean * 0.55
        pose["Hips"] = (hip_lean, roll, yaw)
        # The shoulders turn against the hips, and the head stays level and looks ahead.
        pose["Spine"] = (g.lean * 0.3 + 1.5 * math.cos(step), -roll * 0.7, -yaw * 1.0)
        chest = pose.get("Chest", (1.0, 0.0, 0.0))
        pose["Chest"] = (g.lean * 0.2 + chest[0], -roll * 0.3, chest[2] - yaw * 0.9)
        pose["Neck"] = (-g.lean * 0.6 - 1.0 * math.cos(step), roll * 0.3, yaw * 0.8)
        pose["Head"] = (-2.0 - 1.5 * math.cos(step), 0.0, 0.0)
        for side, phase, s in (("Left", f % 1.0, 1.0), ("Right", (f + 0.5) % 1.0, -1.0)):
            plant, pitch, lift = run_foot(phase, g)
            # Runners land near the middle line, not under each hip.
            pose.update(legs.pose(side, root, plant, pitch, lift, hip_lean, yaw, roll, across=-s * 0.045, turn=s * 2.0))
        a.key(k, pose, {"Root": root})
    a.end()
    a.speeds[name] = g.speed()


def runner_arms(base, left=True, right=True):
    """A runner's arms, swung from the shoulder against the legs with the elbows bent, more bent coming forward."""
    def arms(turn, g):
        pose = dict(base)
        lag = turn - 0.35
        for side, s, wanted in (("Right", 1.0, right), ("Left", -1.0, left)):
            if not wanted:
                continue
            swing = s * math.cos(lag)
            # Forward is negative. The arm goes a little further back than forward.
            pose[side + "UpperArm"] = (12.0 - g.arm * swing, 0.0, s * (6.0 + 4.0 * max(swing, 0.0)))
            pose[side + "LowerArm"] = (-g.elbow - 22.0 * swing, 0.0, s * 12.0 * max(swing, 0.0))
            pose[side + "Hand"] = (6.0, 0.0, 0.0)
        return pose

    return arms


def sword_run_arms(left_free):
    """Running with a sword: the sword arm pumps short with the blade up and forward. The shield is carried before
    the chest, or the empty hand pumps like a runner's."""
    pump = runner_arms(dict(READY_FREE if left_free else READY), left=left_free, right=False)

    def arms(turn, g):
        pose = pump(turn, g)
        swing = math.cos(turn - 0.35)
        upper = -4.0 - g.arm * 0.5 * swing
        lower = -80.0 - 12.0 * swing
        pose["RightUpperArm"] = (upper, 0.0, 10.0)
        pose["RightLowerArm"] = (lower, 0.0, 0.0)
        # The wrist keeps the blade near upright, its point a little forward, however the arm swings.
        pose["RightHand"] = (-98.0 - upper - lower - 6.0 * swing, 0.0, 0.0)
        if not left_free:
            pose["LeftUpperArm"] = (-26.0 + g.arm * 0.25 * swing, 0.0, -18.0)
            pose["LeftLowerArm"] = (-70.0, 0.0, -24.0)
        return pose

    return arms


def spear_run_arms(turn, g):
    pose = dict(READY_SPEAR)
    swing = math.cos(turn - 0.35)
    x, y, z, rise, aim = pose["Spear"]
    pose["Spear"] = (x, y - 0.02 * swing, z + 0.01 * swing, rise + 2.0, aim)
    return pose


def carry_swing(amount):
    """Walking armed: the sword arm swings a little, the shield arm hardly at all."""
    def arms(turn):
        swing = amount * math.cos(turn)
        pose = dict(CARRY)
        nudged(pose, "RightUpperArm", rx=-swing)
        nudged(pose, "RightLowerArm", rx=-abs(swing) * 0.3)
        nudged(pose, "LeftUpperArm", rx=swing * 0.3)
        return pose

    return arms


def free_swing(amount, elbow, inward=4, back=4, give=0.3):
    def arms(turn):
        swing = amount * math.cos(turn)
        pose = dict(RELAXED)
        # Arms reach further back than forward, so the swing's middle sits a little behind the shoulder.
        pose["RightUpperArm"] = (back - swing, 0, inward)
        pose["LeftUpperArm"] = (back + swing, 0, -inward)
        # The elbow bends more as the arm comes forward.
        bend = elbow * give
        pose["RightLowerArm"] = (-elbow - bend * math.cos(turn), 0, 0)
        pose["LeftLowerArm"] = (-elbow + bend * math.cos(turn), 0, 0)
        return pose

    return arms


def wave(f, *terms):
    """A sum of (amount, cycles per clip, phase) sines, which loops with the clip."""
    return sum(amount * math.sin(math.tau * cycles * f + phase) for amount, cycles, phase in terms)


def ease_idle(a, legs, name, arms, frames=192):
    """Standing at ease. The weight rests on one leg, shifts to the other, and back, so the hips drop on the
    free side and its knee eases. Breath lifts the chest, and the head looks about."""
    a.begin(name)
    legs.clip = name
    keys = frames // 4
    for k in range(keys + 1):
        f = k / keys
        # -1 is all the weight on the right leg, 1 all on the left.
        if f < 0.36:
            w = -1.0
        elif f < 0.5:
            w = -1.0 + 2.0 * smooth((f - 0.36) / 0.14)
        elif f < 0.84:
            w = 1.0
        else:
            w = 1.0 - 2.0 * smooth((f - 0.84) / 0.14)
        breath = math.sin(math.tau * 3.0 * f)
        st = EASE
        root = (st.root[0] + 0.022 * w + wave(f, (0.002, 2, 0.4)), st.root[1] + wave(f, (0.003, 1, 1.1)),
                st.root[2] - 0.006 + breath * 0.001)
        roll = -3.2 * w
        yaw = 2.0 * w + wave(f, (1.0, 1, 2.0))
        pose = dict(arms)
        pose["Spine"] = (1.0 + breath * 0.5, -roll * 0.6, -yaw * 0.5)
        pose["Chest"] = (arms.get("Chest", (1, 0, 0))[0] + breath * 1.2, -roll * 0.35, -yaw * 0.3)
        pose["Neck"] = (arms.get("Neck", (-1, 0, 0))[0] - breath * 0.6, roll * 0.3, wave(f, (5.0, 1, 0.8), (2.0, 3, 0.3)))
        pose["Head"] = (wave(f, (2.0, 2, 1.0)), wave(f, (1.5, 1, 2.4)), wave(f, (3.0, 1, 1.4), (1.5, 4, 0.2)))
        # Arms hang free and swing a touch with the hips.
        for bone, sign in (("LeftUpperArm", 1.0), ("RightUpperArm", -1.0)):
            nudged(pose, bone, rx=wave(f, (0.8, 1, 0.5 + sign)) - breath * 0.4, ry=-roll * 0.4)
        # The free leg's foot turns out a little more.
        stance = st.but(left_turn=st.left_turn + 4.0 * max(-w, 0.0), right_turn=st.right_turn - 4.0 * max(w, 0.0))
        pose.update(legs.stand(stance, root=root, yaw=yaw, roll=roll))
        a.key(int(round(f * frames)), pose, {"Root": root})
    a.end()


def ready_idle(a, legs, name, base, frames=96):
    """On guard and waiting: the weight rocks a little between the feet, the knees give with each breath, the
    weapon's point wanders and the eyes stay on the enemy."""
    a.begin(name)
    legs.clip = name
    keys = frames // 3
    st = GUARD_STANCE
    for k in range(keys + 1):
        f = k / keys
        breath = math.sin(math.tau * 2.0 * f)
        sway = math.sin(math.tau * f)
        root = (st.root[0] + 0.012 * sway, st.root[1] + wave(f, (0.008, 1, 1.9)),
                st.root[2] - 0.005 - 0.005 * math.sin(math.tau * 2.0 * f + 0.6))
        roll = -1.2 * sway
        yaw = st.yaw + wave(f, (2.0, 1, 1.0))
        pose = dict(base)
        nudged(pose, "Spine", rx=breath * 0.6, ry=-roll * 0.6, rz=-(yaw - st.yaw) * 0.5)
        nudged(pose, "Chest", rx=breath * 1.4, ry=-roll * 0.3, rz=-(yaw - st.yaw) * 0.4)
        nudged(pose, "Neck", rx=-breath * 0.8, ry=roll * 0.3, rz=wave(f, (2.0, 1, 2.2)))
        nudged(pose, "Head", rx=wave(f, (1.5, 2, 0.4)), ry=wave(f, (1.0, 1, 0.3)), rz=wave(f, (2.0, 1, 2.6), (1.0, 3, 0.1)))
        nudged(pose, "RightUpperArm", rx=wave(f, (2.0, 2, 0.6), (1.0, 1, 2.0)), rz=wave(f, (2.0, 1, 0.2)))
        nudged(pose, "RightHand", rx=wave(f, (3.0, 1, 1.7)), rz=wave(f, (3.0, 1, 0.9)))
        nudged(pose, "LeftUpperArm", rx=wave(f, (1.5, 2, 1.2)) - breath * 0.5)
        pose.update(legs.stand(st, root=root, yaw=yaw, roll=roll))
        a.key(int(round(f * frames)), pose, {"Root": root})
    a.end()


# Stepping on guard in eight ways, as (to the character's left, forward). Back steps are slower in the game too.
_D = math.sqrt(0.5)
GUARD_STEPS = {
    "step_f": (0.0, 1.0), "step_fl": (_D, _D), "step_l": (1.0, 0.0), "step_bl": (_D, -_D),
    "step_b": (0.0, -1.0), "step_br": (-_D, -_D), "step_r": (-1.0, 0.0), "step_fr": (-_D, _D),
}


def guard_step(a, legs, name, across, forward):
    """One cycle of stepping on guard, with the upper body held in READY. Sideways, the leading foot steps out and
    the other closes up behind it, never past it. Each clip starts as the left foot lands."""
    frames = GUARD_STEP_FRAMES
    side = abs(across)
    reach = GUARD_STEP_FORWARD if forward >= 0.0 else GUARD_STEP_BACK
    stride = 1.0 / math.sqrt((across / GUARD_STEP_SIDE) ** 2 + (forward / reach) ** 2)
    stance = GUARD_STEP_STANCE + (GUARD_SIDE_STANCE - GUARD_STEP_STANCE) * side
    # How far the right foot's cycle runs behind the left's. A half for straight on, more or less to the side.
    lag = 0.5 + 0.22 * across
    # Heel first going forward, ball first going back, flat to the side.
    roll_share = forward if forward >= 0.0 else forward * 0.6
    st = GUARD_STANCE
    a.begin(name)
    legs.clip = name
    for k in range(frames + 1):
        f = k / frames
        pose = dict(READY)
        root = (st.root[0] + 0.01 * across * math.cos(math.tau * f), st.root[1],
                st.root[2] - 0.012 + 0.007 * math.cos(2.0 * math.tau * (f - stance * 0.5)))
        yaw = st.yaw - 4.0 * forward * math.cos(math.tau * f)
        roll = -1.5 * math.cos(math.tau * (f - stance * 0.5))
        pose["Hips"] = (st.lean, roll, yaw)
        nudged(pose, "Spine", rx=1.0, ry=-roll * 0.7, rz=-(yaw - st.yaw) * 0.6)
        nudged(pose, "Chest", ry=-roll * 0.3, rz=-(yaw - st.yaw) * 0.5)
        nudged(pose, "Neck", rx=-1.0, rz=-(yaw - st.yaw) * 0.2)
        nudged(pose, "RightUpperArm", rx=1.5 * math.cos(math.tau * 2.0 * f))
        nudged(pose, "LeftUpperArm", rx=1.0 * math.cos(math.tau * 2.0 * f + 0.5))
        for side_name, (rest, out), turn, phase in (("Left", st.left, st.left_turn, f % 1.0), ("Right", st.right, st.right_turn, (f + lag) % 1.0)):
            s, pitch, lift = foot_cycle(phase, 1.0, stance, -10.0, 18.0, 0.06)
            pose.update(legs.pose(side_name, root, rest + forward * stride * s, pitch * roll_share, lift, st.lean, yaw, roll,
                                  across=out + across * stride * s, turn=turn))
        a.key(k, pose, {"Root": root})
    a.end()
    a.speeds[name] = stride / (stance * frames / FPS)


def stance_at(track, frame):
    """The stance a track of (frame, stance) stops is in at this frame."""
    for (f0, s0), (f1, s1) in zip(track, track[1:]):
        if frame <= f1:
            return s0.lerp(s1, smooth((frame - f0) / (f1 - f0)))
    return track[-1][1]


def track_legs(a, legs, track):
    """Keys the legs and hips on every frame between (frame, stance) stops. A foot that moves lifts."""
    for (f0, s0), (f1, s1) in zip(track, track[1:]):
        for frame in range(f0, f1 + 1):
            arc = math.sin(math.pi * (frame - f0) / (f1 - f0))
            now = stance_at(track, frame)
            pose = {"Hips": (now.lean, now.roll, now.yaw)}
            for side, a0, a1, foot, turn, heel in (("Left", s0.left, s1.left, now.left, now.left_turn, now.left_heel),
                                                   ("Right", s0.right, s1.right, now.right, now.right_turn, now.right_heel)):
                lift = STEP_LIFT * arc if a0 != a1 else 0.0
                pose.update(legs.pose(side, now.root, foot[0], pitch=heel, lift=lift, lean=now.lean, yaw=now.yaw, roll=now.roll,
                                      across=foot[1], turn=turn))
            a.key(frame, pose, {"Root": now.root}, part="lower")


def key_upper(a, stops, track=None):
    """Keys the upper body at each (frame, pose) stop. When both hands hold one weapon, or the weapon is placed rather
    than the arm posed, it keys every other frame between stops as well, so the weapon keeps to its path and the second
    hand can be fitted to it all the way. A weapon placed on the ground (BladeAt, SpearAt) needs the legs' track, to
    know where the hips are."""
    def keyed(frame, pose):
        if track is not None and ("BladeAt" in pose or "SpearAt" in pose):
            st = stance_at(track, frame)
            pose = dict(pose, Body=(*st.root, st.lean, st.roll, st.yaw))
        a.key(frame, pose, part="upper")

    for (f0, p0), (f1, p1) in zip(stops, stops[1:]):
        keyed(f0, p0)
        # Between a weapon placed one way and the other, the joints are left to blend.
        same = [k for k in WEAPON_PLACES if k in p0] == [k for k in WEAPON_PLACES if k in p1]
        placed = same and any(k in p0 for k in WEAPON_PLACES)
        if (a.two_hands and same) or placed:
            for frame in range(f0 + 2, f1 - 1, 2):
                t = smooth((frame - f0) / (f1 - f0))
                keyed(frame, {bone: tuple(x + (y - x) * t for x, y in zip(p0.get(bone, (0, 0, 0)), p1.get(bone, (0, 0, 0))))
                              for bone in set(p0) | set(p1)})
    keyed(*stops[-1])


# The frames of a blow. It gathers, is cocked and held a beat, swings, lands on frame 18, follows through, settles,
# and is back on guard by 36. The view plays 0 to 18 over the wind-up and the rest over the recovery, so frame 18 is
# where the weapon meets what it was aimed at.
BLOW_FRAMES = (("gather", 5), ("cocked", 10), ("held", 14), ("swing", 16), ("blow", 18), ("through", 21), ("settle", 27))
BLOW_LENGTH = 36


class Footwork:
    """How the feet and hips go in a blow. step is how far the front foot steps in, reach how far the hips then drive
    forward over it, drop how far they sink (low blows), hips the turn of the hips when cocked and when the blow lands,
    and push the degrees the back heel comes up as the weight drives off it."""

    def __init__(self, step=0.13, reach=0.1, drop=0.0, hips=(-20.0, 8.0), push=16.0):
        self.step = step
        self.reach = reach
        self.drop = drop
        self.hips = hips
        self.push = push


WEAPON_PLACES = ("Blade", "BladeAt", "Spear", "SpearAt")


def over(base, extra):
    """base with extra laid over it. Where extra says where the weapon is, that replaces where base says it is."""
    out = dict(base)
    if any(k in extra for k in WEAPON_PLACES):
        for k in WEAPON_PLACES:
            out.pop(k, None)
    out.update(extra)
    return out


def strike(a, legs, name, base, phases, feet):
    """A blow of BLOW_LENGTH frames that lands on frame 18. phases holds the upper body at each of BLOW_FRAMES it
    names. The weight rocks back as it gathers, the front foot steps in while it is cocked, and it drives forward off
    the back foot with the hips turning in a beat ahead of the shoulders."""
    a.begin(name)
    legs.clip = name
    stops = [(0, dict(base))]
    for phase, frame in BLOW_FRAMES:
        if phase in phases:
            stops.append((frame, over(base, phases[phase])))
    stops.append((BLOW_LENGTH, dict(base)))
    st = GUARD_STANCE
    y = st.root[1]
    front = (st.left[0] + feet.step, st.left[1])
    wind, land = feet.hips

    def at(root, yaw, lean=0.0, heel=0.0, foot=front):
        return st.but(root=root, left=foot, yaw=yaw, lean=st.lean + lean, right_heel=heel,
                      right_turn=st.right_turn + (yaw - st.yaw) * 0.4)

    track = [
        (0, st),
        (5, at((0.0, y + 0.03, -0.053), st.yaw + (wind - st.yaw) * 0.5, foot=st.left)),
        (10, at((0.0, y + 0.012, -0.056 - feet.drop * 0.3), wind, 1.0)),
        (14, at((0.0, y + 0.018, -0.06 - feet.drop * 0.3), wind - 2.0, 1.0)),
        (18, at((0.0, y - feet.reach, -0.072 - feet.drop), land, 4.0, feet.push)),
        (21, at((0.0, y - feet.reach - 0.015, -0.076 - feet.drop), land + 3.0, 4.5, feet.push)),
        (27, at((0.0, y - feet.reach * 0.4, -0.066 - feet.drop * 0.5), (st.yaw + land) * 0.5, 2.0)),
        (BLOW_LENGTH, st),
    ]
    key_upper(a, stops, track)
    track_legs(a, legs, track)
    a.end()


def guard(a, legs, name, base, pose, turn=0.0, drop=0.0, lean=0.0):
    """Raised by frame 5, held through frame 20, lowered by frame 32. The view holds it for as long as it is needed.
    The body braces behind it: the hips turn turn degrees towards the side guarded and sink, and the weight leans in."""
    a.begin(name)
    legs.clip = name
    st = GUARD_STANCE
    y = st.root[1]
    braced = st.but(root=(-0.005, y - 0.012, -0.072 - drop), left=(0.16, 0.035), right=(-0.19, -0.05), yaw=st.yaw + turn,
                    lean=st.lean + lean, left_turn=st.left_turn + turn * 0.3, right_turn=st.right_turn + turn * 0.3)
    track = [(0, st), (5, braced), (20, braced.but(root=(-0.005, y - 0.006, -0.075 - drop))), (32, st)]
    key_upper(a, [(0, dict(base)), (5, over(base, pose)), (20, over(base, pose)), (32, dict(base))], track)
    track_legs(a, legs, track)
    a.end()


class Flinch:
    """Taking a blow. The back, chest and neck are thrown as (forward, bend to the left, turn to the left), the
    upper arms flung as arms (right, left), or arms None to keep hold of a weapon in both hands. The hips are shoved
    by shove (to the left, back) and turned yaw degrees, and the knees give."""

    def __init__(self, spine, chest, neck, arms, shove, yaw):
        self.spine = spine
        self.chest = chest
        self.neck = neck
        self.arms = arms
        self.shove = shove
        self.yaw = yaw


def flinch(a, legs, name, base, how, keep_arms=False):
    """Taking a blow: thrown by frame 3, at its worst by 6, caught by 11 and back on guard by 20."""
    a.begin(name)
    legs.clip = name

    def hurt(share):
        out = dict(base)
        for bone, turn in (("Spine", how.spine), ("Chest", how.chest), ("Neck", how.neck),
                           ("Head", tuple(v * 0.5 for v in how.neck))):
            nudged(out, bone, *(v * share for v in turn))
        if how.arms is not None and not keep_arms:
            nudged(out, "RightUpperArm", *(v * share for v in how.arms[0]))
            nudged(out, "LeftUpperArm", *(v * share for v in how.arms[1]))
        return out

    key_upper(a, [(0, dict(base)), (3, hurt(0.85)), (6, hurt(1.0)), (11, hurt(0.45)), (20, dict(base))])
    st = GUARD_STANCE
    x, back = how.shove
    thrown = st.but(root=(st.root[0] + x, st.root[1] + back, -0.06), yaw=st.yaw + how.yaw, lean=st.lean - 6.0,
                    roll=-x * 60.0)
    caught = st.but(root=(st.root[0] + x * 0.5, st.root[1] + back * 0.6, -0.075), yaw=st.yaw + how.yaw * 0.4, lean=st.lean)
    track_legs(a, legs, [(0, st), (4, thrown), (7, thrown.but(root=(thrown.root[0], thrown.root[1] + 0.006, -0.068))),
                         (12, caught), (20, st)])
    a.end()


def cut(spine, chest, neck, **extra):
    """An upper body in a blow or a guard: the back, chest and neck, and anything else, such as where the weapon is."""
    return dict(Spine=spine, Chest=chest, Neck=neck, **extra)


# Sword blows. A pose's BladeAt is where the sword is: the grip (x to the left, -y forward, z up, in metres, on the
# ground the feet stand on) and the blade's rise and turn to the left in degrees. The build turns the right arm to
# hold it there. The side a blow is named for is the attacker's own, where it starts; frame 18 is
# where it meets the enemy, a little over a metre off: the head for the overhead, the body for the thrust, the legs
# for the low cut, and either side of the body for the others.
BLADE_BLOWS = {
    # Up over the right shoulder, the point dropping behind, then down onto the head and on down past the right side.
    "attack": (dict(
        gather=cut((2, 0, -5), (1, 0, -8), (-12, 0, 8), BladeAt=(-0.22, -0.3, 1.25, 60.0, 5.0)),
        cocked=cut((-3, 0, -12), (-5, 0, -16), (-10, 0, 16), BladeAt=(-0.2, -0.02, 1.75, 135.0, 5.0)),
        held=cut((-4, 0, -13), (-6, 0, -18), (-10, 0, 18), BladeAt=(-0.2, 0.02, 1.77, 145.0, 5.0)),
        swing=cut((4, 0, 0), (4, 0, 2), (-12, 0, 2), BladeAt=(-0.16, -0.35, 1.8, 70.0, 3.0)),
        blow=cut((10, 0, 8), (12, 0, 12), (-18, 0, -10), BladeAt=(-0.08, -0.6, 1.62, -2.0, 3.0)),
        through=cut((14, 0, 10), (14, 0, 14), (-20, 0, -12), BladeAt=(-0.13, -0.38, 0.98, -18.0, 2.0)),
        settle=cut((8, 0, 6), (7, 0, 7), (-16, 0, -4), BladeAt=(-0.12, -0.42, 1.0, -4.0, 10.0)),
    ), Footwork(hips=(-20.0, 8.0))),
    # A forehand: drawn back high on the right, the blade swinging flat across onto the enemy's left side.
    "attack_right": (dict(
        gather=cut((1, 0, -8), (0, 0, -12), (-12, 0, 10), BladeAt=(-0.3, -0.25, 1.25, 45.0, -30.0)),
        cocked=cut((-1, 0, -16), (-2, 0, -24), (-10, 0, 22), BladeAt=(-0.42, 0.0, 1.5, 55.0, -150.0)),
        held=cut((-1, 0, -17), (-2, 0, -26), (-10, 0, 24), BladeAt=(-0.44, 0.04, 1.52, 58.0, -158.0)),
        swing=cut((3, 0, -6), (3, 0, -8), (-12, 0, 8), BladeAt=(-0.42, -0.35, 1.38, 15.0, -70.0)),
        blow=cut((7, 0, 8), (7, 0, 12), (-14, 0, -8), BladeAt=(-0.24, -0.58, 1.28, 0.0, 25.0)),
        through=cut((8, 0, 14), (9, 0, 22), (-14, 0, -18), BladeAt=(0.0, -0.46, 1.2, 2.0, 60.0)),
        settle=cut((6, 0, 8), (6, 0, 10), (-14, 0, -8), BladeAt=(-0.05, -0.48, 1.12, 15.0, 35.0)),
    ), Footwork(hips=(-26.0, 10.0))),
    # A backhand: drawn across to the left shoulder, then swung flat out onto the enemy's right side.
    "attack_left": (dict(
        gather=cut((1, 0, 6), (0, 0, 8), (-12, 0, -4), BladeAt=(-0.08, -0.32, 1.28, 45.0, 40.0)),
        cocked=cut((-1, 0, 12), (-2, 0, 18), (-10, 0, -12), BladeAt=(0.12, -0.14, 1.5, 50.0, 140.0)),
        held=cut((-1, 0, 13), (-2, 0, 20), (-10, 0, -14), BladeAt=(0.14, -0.12, 1.52, 52.0, 148.0)),
        swing=cut((3, 0, 4), (3, 0, 6), (-12, 0, -4), BladeAt=(0.06, -0.42, 1.4, 14.0, 70.0)),
        blow=cut((7, 0, -8), (7, 0, -12), (-14, 0, 10), BladeAt=(0.0, -0.58, 1.28, 0.0, -20.0)),
        through=cut((8, 0, -14), (9, 0, -20), (-14, 0, 18), BladeAt=(-0.42, -0.42, 1.24, 4.0, -80.0)),
        settle=cut((6, 0, -6), (6, 0, -8), (-14, 0, 8), BladeAt=(-0.26, -0.45, 1.12, 14.0, -30.0)),
    ), Footwork(hips=(-2.0, -22.0))),
    # Drawn back past the hip with the point on the enemy, then driven straight out at the body, the hips turning
    # in behind it.
    "attack_thrust": (dict(
        gather=cut((1, 0, -6), (0, 0, -10), (-12, 0, 8), BladeAt=(-0.24, -0.22, 1.08, 8.0, 4.0)),
        cocked=cut((-2, 0, -8), (-2, 0, -10), (-12, 0, 12), BladeAt=(-0.32, 0.06, 1.1, 4.0, -4.0),
                   LeftUpperArm=(-36, 0, -2), LeftLowerArm=(-62, 0, -18)),
        held=cut((-2, 0, -9), (-2, 0, -11), (-12, 0, 13), BladeAt=(-0.32, 0.09, 1.1, 4.0, -4.0),
                 LeftUpperArm=(-36, 0, -2), LeftLowerArm=(-62, 0, -18)),
        swing=cut((4, 0, -2), (4, 0, -4), (-14, 0, 6), BladeAt=(-0.22, -0.32, 1.18, 2.0, 1.0)),
        blow=cut((10, 0, 8), (10, 0, 10), (-18, 0, -8), BladeAt=(-0.1, -0.78, 1.22, 0.0, -2.0)),
        through=cut((11, 0, 9), (11, 0, 11), (-18, 0, -9), BladeAt=(-0.1, -0.8, 1.21, -1.0, -2.0)),
        settle=cut((7, 0, 5), (6, 0, 6), (-16, 0, -4), BladeAt=(-0.12, -0.55, 1.1, 12.0, 8.0)),
    ), Footwork(step=0.18, reach=0.13, hips=(-24.0, 6.0))),
    # Up high on the right, then down and across at the shins, the body stooping and the knees giving.
    "attack_low": (dict(
        gather=cut((3, 0, -8), (2, 0, -12), (-14, 0, 10), BladeAt=(-0.3, -0.25, 1.25, 45.0, -30.0)),
        cocked=cut((2, 0, -16), (0, 0, -24), (-12, 0, 22), BladeAt=(-0.44, 0.0, 1.52, 65.0, -150.0)),
        held=cut((2, 0, -17), (0, 0, -26), (-12, 0, 24), BladeAt=(-0.46, 0.04, 1.54, 68.0, -156.0)),
        swing=cut((10, 0, -8), (8, 0, -10), (-16, 0, 10), BladeAt=(-0.44, -0.3, 1.05, -30.0, -60.0)),
        blow=cut((22, 0, 6), (18, 0, 10), (-26, 0, -6), BladeAt=(-0.2, -0.52, 0.8, -28.0, 5.0)),
        through=cut((22, 0, 12), (18, 0, 18), (-26, 0, -14), BladeAt=(0.12, -0.5, 0.78, -24.0, 60.0)),
        settle=cut((12, 0, 6), (10, 0, 8), (-18, 0, -6), BladeAt=(-0.1, -0.46, 0.95, 0.0, 10.0)),
    ), Footwork(step=0.18, reach=0.12, drop=0.09, hips=(-24.0, 8.0))),
}
# The shield arm in a blow: it comes forward to cover while the sword is cocked, and draws in and to the left as the
# blow lands so the sword arm has room. Any phase not named here leaves it on guard.
SHIELD_COVER = dict(
    cocked=dict(LeftUpperArm=(-40, 0, -24), LeftLowerArm=(-60, 0, -26)),
    held=dict(LeftUpperArm=(-40, 0, -24), LeftLowerArm=(-60, 0, -26)),
    blow=dict(LeftUpperArm=(-30, 0, -10), LeftLowerArm=(-70, 0, -24)),
    through=dict(LeftUpperArm=(-28, 0, -4), LeftLowerArm=(-70, 0, -22)),
)
# The empty hand in a blow: it reaches out towards the enemy while the sword is cocked, then pulls back to the chest
# as the blow lands, which turns the shoulders in behind it.
FREE_REACH = dict(
    cocked=dict(LeftUpperArm=(-48, 0, -14), LeftLowerArm=(-40, 0, -4), LeftHand=(6, 0, 0)),
    held=dict(LeftUpperArm=(-50, 0, -14), LeftLowerArm=(-38, 0, -4), LeftHand=(6, 0, 0)),
    blow=dict(LeftUpperArm=(-14, 0, -24), LeftLowerArm=(-100, 0, -6), LeftHand=(10, 0, 0)),
    through=dict(LeftUpperArm=(-10, 0, -26), LeftLowerArm=(-102, 0, -6), LeftHand=(10, 0, 0)),
)


def without_left(pose):
    return {bone: turn for bone, turn in pose.items() if not bone.startswith("Left")}


def with_arm(blows, arm, own=True):
    """The blows, with the left arm posed by arm at each phase it names. own keeps a blow's own left arm where it has
    one; otherwise that is dropped, for a left hand that holds something else."""
    out = {}
    for name, (phases, feet) in blows.items():
        out[name] = ({phase: merged(arm.get(phase, {}), **(pose if own else without_left(pose))) for phase, pose in phases.items()}, feet)
    return out


# Guards with the shield, each as (upper body, how the hips turn and sink, lean). The shield meets the line the blow
# comes on: over the head against the overhead, out to the left against a forehand (which comes at this side), across
# to the right against a backhand, and low in front against a thrust or a cut at the legs. The sword is drawn back a
# little, ready to answer, or held up over a low shield.
SWORD_BACK = dict(RightUpperArm=(-18, 0, 16), RightLowerArm=(-72, 0, 0), RightHand=(34, 0, 0))
SHIELD_GUARDS = {
    "block_up": (cut((0, 0, 0), (-2, 0, 0), (-4, 0, 0), LeftUpperArm=(-118, 0, -40), LeftLowerArm=(-58, 0, -34),
                     **SWORD_BACK), 0.0, 0.02, -2.0),
    "block_left": (cut((4, 0, 12), (5, 0, 16), (-10, 0, -10), LeftUpperArm=(-68, 0, -34), LeftLowerArm=(-46, 0, -24),
                       **merged(SWORD_BACK, RightUpperArm=(-22, 0, -14))), 10.0, 0.01, 2.0),
    "block_right": (cut((4, 0, -14), (5, 0, -18), (-8, 0, 14), LeftUpperArm=(-62, 0, -66), LeftLowerArm=(-50, 0, -30),
                        **SWORD_BACK), -12.0, 0.01, 2.0),
    "block_low": (cut((14, 0, 4), (10, 0, 6), (-22, 0, 0), LeftUpperArm=(-34, 0, -40), LeftLowerArm=(-26, 0, -22),
                      RightUpperArm=(-48, 0, -6), RightLowerArm=(-84, 0, 0), RightHand=(40, 0, 0)), 0.0, 0.06, 4.0),
}
# Guards with the sword alone: the blade is put across the blow's line, the edge to it, the free fist drawn in.
FREE_GUARD_LEFT = {"LeftUpperArm": (-26, 0, -18), "LeftLowerArm": (-92, 0, -6), "LeftHand": (10, 0, 0)}
FREE_GUARDS = {
    # Hanging over the head, the point out to the left.
    "block_up": (cut((0, 0, -2), (-2, 0, -4), (-4, 0, 4), BladeAt=(-0.25, -0.3, 1.72, 10.0, 84.0), **FREE_GUARD_LEFT), 0.0, 0.02, -2.0),
    # Upright across the left side, point up.
    "block_left": (cut((4, 0, 12), (5, 0, 16), (-10, 0, -10), BladeAt=(0.08, -0.42, 1.2, 65.0, 20.0), **FREE_GUARD_LEFT), 8.0, 0.01, 2.0),
    # Upright on the right, point up.
    "block_right": (cut((4, 0, -12), (5, 0, -16), (-10, 0, 12), BladeAt=(-0.36, -0.4, 1.18, 65.0, -5.0), **FREE_GUARD_LEFT), -10.0, 0.01, 2.0),
    # Point down in front, to sweep a thrust or a cut at the legs aside.
    "block_low": (cut((14, 0, 2), (10, 0, 4), (-22, 0, 0), BladeAt=(-0.16, -0.36, 0.98, -40.0, 10.0), **FREE_GUARD_LEFT), 0.0, 0.06, 4.0),
}
FLINCHES = {
    # Struck in front: the head and chest snap back, the arms fly up and out, and the weight rocks onto the back foot.
    "hit_front": Flinch((-8, 0, 0), (-12, 0, 0), (-14, 0, 0), ((8, 14, 0), (-4, -12, 0)), (0.0, 0.05), 0.0),
    # Struck on the left: the body folds away to the right and the shoulders are knocked round to the left.
    "hit_left": Flinch((-3, -7, 12), (-5, -9, 16), (-4, -8, 12), ((-6, 0, 8), (-14, 0, -14)), (-0.035, 0.03), 8.0),
    # Struck on the right: the body folds away to the left and the shoulders are knocked round to the right.
    "hit_right": Flinch((-3, 7, -12), (-5, 9, -16), (-4, 8, -12), ((-14, 0, 14), (-6, 0, -8)), (0.035, 0.03), -8.0),
}

# A blade and nothing in the other hand: the free hand rides in front of the belly, out of the way and ready.
FREE_LEFT = {"LeftUpperArm": (-22, 0, -12), "LeftLowerArm": (-62, 0, -4), "LeftHand": (10, 0, 0)}
READY_FREE = merged(READY, **FREE_LEFT)

# A spear in both hands, the right at the butt end by the hip and the left forward on the shaft, point at the
# enemy's chest. A spear pose says where the weapon lies, not how the arms bend: Spear is (x, y, z, rise, turn), the
# right hand's grip in the standing pose (x to the left, -y forward, z up, in metres) carried with the chest, and
# the shaft's rise and turn to the left in degrees, as the hips face. The hips tip forward on guard and more in a
# lunge, which tips the shaft down with them, so a level thrust asks for a little rise. The build turns the right arm
# to hold it there and closes the left hand on the shaft. The arm angles here are only where it starts looking.
READY_SPEAR = merged(READY,
                     Spear=(-0.15, -0.1, 1.0, 16.0, 12.0),
                     RightUpperArm=(14, 0, 6), RightLowerArm=(-80, 0, 0), RightHand=(0, 0, 16),
                     LeftUpperArm=(-40, 0, -20), LeftLowerArm=(-50, 0, -10), LeftHand=(0, 0, 0),
                     Spine=(6, 0, -6), Chest=(5, 0, -9), Neck=(-15, 0, 15), Head=(-3, 0, 0))
# Carried upright at ease in the right hand, butt down by the foot.
CARRY_SPEAR = merged(CARRY, Spear=(-0.21, -0.1, 1.1, 80.0, 0.0),
                     RightUpperArm=(-8, 0, 6), RightLowerArm=(-100, 0, 0), RightHand=(-22, 0, 0),
                     LeftUpperArm=(2, 0, -4), LeftLowerArm=(-14, 0, 0), LeftHand=(6, 0, 0))


def jab(aim, spine, chest, neck):
    """A spear blow: drawn back beside the hip with the point still on the enemy as it is cocked, then driven out to
    aim, (x, y, z, rise, turn) as SpearAt has it, the body turning in behind it. The point meets the enemy about 1.7
    metres off, which is where a spear fighter stands."""
    x, y, z, rise, turn = aim
    sx, sy, sz = spine
    cx, cy, cz = chest
    draw = (-0.24, 0.14, 1.0, rise * 0.6 + 4.0, 8.0)
    return dict(
        gather=cut((4, 0, -6), (3, 0, -8), (-14, 0, 14), SpearAt=(-0.21, 0.02, 0.98, rise * 0.4 + 8.0, 9.0)),
        cocked=cut((2, 0, -10), (1, 0, -13), (-12, 0, 20), SpearAt=draw),
        held=cut((2, 0, -11), (1, 0, -14), (-12, 0, 21), SpearAt=(draw[0], draw[1] + 0.03) + draw[2:]),
        swing=cut((sx * 0.5 + 1, sy, sz * 0.3 - 4), (cx * 0.5 + 1, cy, cz * 0.3 - 5), (-14, 0, 10),
                  SpearAt=(-0.2 + (x + 0.2) * 0.5, y * 0.45, 1.0 + (z - 1.0) * 0.6, rise * 0.8 + 1.0, (turn + 8.0) * 0.5)),
        blow=cut(spine, chest, neck, SpearAt=aim),
        through=cut((sx + 1, sy, sz * 1.1), (cx + 1, cy, cz * 1.1), neck, SpearAt=(x, y - 0.04, z - 0.01, rise - 1.0, turn)),
        settle=cut((sx * 0.5 + 3, sy, sz * 0.4 - 2), (cx * 0.5 + 2, cy, cz * 0.4 - 3), (-15, 0, 10),
                   SpearAt=(-0.16, -0.18, 0.98 + (z - 1.0) * 0.3, rise * 0.5 + 8.0, turn * 0.5 + 5.0)),
    )


SPEAR_BLOWS = {
    # At the face.
    "attack": (jab((-0.1, -0.5, 1.2, 14.0, 3.0), (8, 0, 6), (6, 0, 8), (-14, 0, -2)), Footwork(hips=(-22.0, 4.0))),
    # Straight at the body.
    "attack_thrust": (jab((-0.1, -0.54, 1.06, 3.0, 2.0), (12, 0, 6), (10, 0, 8), (-16, 0, -2)),
                      Footwork(step=0.19, reach=0.14, hips=(-24.0, 4.0))),
    # At the enemy's right side, which is to the left.
    "attack_left": (jab((-0.04, -0.5, 1.08, 3.0, 11.0), (10, 0, 12), (9, 0, 14), (-16, 0, -12)), Footwork(hips=(-14.0, -2.0))),
    # At the enemy's left side, which is to the right.
    "attack_right": (jab((-0.2, -0.48, 1.08, 3.0, -6.0), (10, 0, -2), (9, 0, -4), (-16, 0, 8)), Footwork(hips=(-26.0, -8.0))),
    # Down at the legs, stooping.
    "attack_low": (jab((-0.12, -0.46, 0.86, -13.0, 4.0), (20, 0, 4), (16, 0, 6), (-24, 0, 0)),
                   Footwork(step=0.19, reach=0.12, drop=0.09, hips=(-20.0, 4.0))),
}
# The shaft is raised across the blow: high and steep, swung to either side, or point down to sweep a low cut aside.
SPEAR_GUARDS = {
    "block_up": (cut((1, 0, -4), (0, 0, -6), (-10, 0, 12), Spear=(-0.18, -0.2, 1.24, 58.0, 18.0)), 0.0, 0.02, -2.0),
    "block_left": (cut((4, 0, 10), (5, 0, 12), (-10, 0, -6), Spear=(-0.08, -0.22, 1.1, 48.0, 48.0)), 8.0, 0.01, 2.0),
    "block_right": (cut((4, 0, -14), (5, 0, -18), (-10, 0, 24), Spear=(-0.24, -0.2, 1.08, 50.0, -22.0)), -10.0, 0.01, 2.0),
    "block_low": (cut((12, 0, -4), (10, 0, -6), (-20, 0, 12), Spear=(-0.15, -0.22, 0.95, -22.0, 10.0)), 0.0, 0.06, 4.0),
}


def fight_set(a, legs, suffix, base, blows, guards, keep_arms=False):
    """Every fighting clip for one way of being armed, named with suffix."""
    ready_idle(a, legs, "ready" + suffix, base)
    for name, (phases, feet) in blows.items():
        strike(a, legs, name + suffix, base, phases, feet)
    for name, (pose, turn, drop, lean) in guards.items():
        guard(a, legs, name + suffix, base, pose, turn, drop, lean)
    for name, how in FLINCHES.items():
        flinch(a, legs, name + suffix, base, how, keep_arms)


def spear_carry_swing(amount):
    """Walking with the spear upright in the right hand, the left arm swinging free."""
    def arms(turn):
        swing = amount * math.cos(turn)
        pose = dict(CARRY_SPEAR)
        x, y, z, rise, aim = pose["Spear"]
        pose["Spear"] = (x, y - 0.004 * swing, z, rise, aim)
        nudged(pose, "LeftUpperArm", rx=swing)
        return pose

    return arms


def animate(a, legs):
    a.two_hands = False
    a.hands("grip", "strap")
    # Blade and shield.
    fight_set(a, legs, "", READY, with_arm(BLADE_BLOWS, SHIELD_COVER), SHIELD_GUARDS)
    # A spear in both hands.
    a.two_hands = True
    a.hands("grip", "grip")
    fight_set(a, legs, "_spear", READY_SPEAR, SPEAR_BLOWS, SPEAR_GUARDS, keep_arms=True)
    run_cycle(a, legs, "run_spear", JOG, spear_run_arms)
    run_cycle(a, legs, "sprint_spear", SPRINT, spear_run_arms)
    a.two_hands = False
    # The spear upright in the right hand, the left swinging free.
    a.hands("grip", "relaxed")
    ease_idle(a, legs, "idle_spear", CARRY_SPEAR)
    locomotion(a, legs, "walk_spear", WALK_FRAMES, WALK_STRIDE, WALK_STANCE, -16.0, 34.0, WALK_LIFT, 0.024, 0.012, WALK_STANCE * 0.5, 0.016, 5.0, 2.5, 4.0,
               spear_carry_swing(14), peak=WALK_PEAK)

    a.hands("grip", "strap")
    for name, (across, forward) in GUARD_STEPS.items():
        guard_step(a, legs, name, across, forward)
    ease_idle(a, legs, "idle", CARRY)
    locomotion(a, legs, "walk", WALK_FRAMES, WALK_STRIDE, WALK_STANCE, -16.0, 34.0, WALK_LIFT, 0.024, 0.012, WALK_STANCE * 0.5, 0.016, 5.0, 2.5, 4.0, carry_swing(12), peak=WALK_PEAK)
    run_cycle(a, legs, "run", JOG, sword_run_arms(False))
    run_cycle(a, legs, "sprint", SPRINT, sword_run_arms(False))

    # Shield up across the body, with the left foot forward.
    guard(a, legs, "block", READY, dict(LeftUpperArm=(-58, 0, -62), LeftLowerArm=(-52, 0, -30), LeftHand=(0, 0, 0),
                                        Spine=(4, 0, 6), Chest=(5, 0, 8), Neck=(-6, 0, -6),
                                        RightUpperArm=(-22, 0, -8), RightLowerArm=(-58, 0, 0), RightHand=(10, 0, 0)))

    # Beaten, down on the right knee with the shin flat behind and the head low.
    a.begin("yield")
    a.key(0, merged(READY, **legs.stand(GUARD_STANCE)), {"Root": GUARD_STANCE.root})
    kneel = dict(Hips=(6, 0, 0), Spine=(12, 0, 0), Chest=(12, 0, 0), Neck=(18, 0, 0), Head=(10, 0, 0),
                 RightUpperArm=(-8, 0, 10), RightLowerArm=(-14, 0, 0), RightHand=(0, 0, 0),
                 LeftUpperArm=(-8, 0, -14), LeftLowerArm=(-22, 0, 0), LeftHand=(0, 0, 0),
                 LeftUpperLeg=(-84, 0, 0), LeftLowerLeg=(86, 0, 0), LeftFoot=(-4, 0, 0),
                 RightUpperLeg=(-2, 0, 0), RightLowerLeg=(90, 0, 0), RightFoot=(58, 0, 0), RightToes=(-30, 0, 0))
    a.key(14, kneel, {"Root": (0.0, 0.05, -0.43)})
    a.key(24, kneel, {"Root": (0.0, 0.05, -0.44)})
    a.end()

    # Hit, stagger back, collapse onto the back.
    a.begin("death")
    a.key(0, merged(READY, **legs.stand(GUARD_STANCE)), {"Root": GUARD_STANCE.root})
    a.key(7, merged(READY, Hips=(-8, 0, 0), Spine=(-12, 0, 8), Chest=(-16, 0, 12), Neck=(-14, 0, 0),
                    RightUpperArm=(-30, 0, 30), LeftUpperArm=(-30, 0, -40),
                    LeftUpperLeg=(-10, 0, 0), LeftLowerLeg=(15, 0, 0)), {"Hips": (0, 0.1, -0.02)})
    a.key(18, merged(READY, Hips=(-30, 0, 6), Spine=(-6, 0, 6), Chest=(-6, 0, 8), Neck=(10, 0, 0),
                     RightUpperArm=(-20, 0, 40), LeftUpperArm=(-20, 0, -50),
                     LeftUpperLeg=(-25, 0, 0), LeftLowerLeg=(70, 0, 0),
                     RightUpperLeg=(-35, 0, 0), RightLowerLeg=(85, 0, 0)), {"Hips": (0, 0.28, -0.42)})
    final = dict(Hips=(-84, 0, 8), Spine=(-2, 0, 0), Chest=(-2, 0, 0), Neck=(8, 0, 20), Head=(0, 0, 15),
                 RightUpperArm=(-20, 8, 55), RightLowerArm=(-25, 0, 0), RightHand=(15, 0, 0),
                 LeftUpperArm=(-10, -8, -58), LeftLowerArm=(-20, 0, 0),
                 LeftUpperLeg=(-18, -8, 0), LeftLowerLeg=(36, 0, 0), LeftFoot=(30, 0, 0),
                 RightUpperLeg=(-6, 10, 0), RightLowerLeg=(14, 0, 0), RightFoot=(40, 0, 0))
    a.key(30, final, {"Hips": (0, 0.5, -0.78)})
    a.key(36, final, {"Hips": (0, 0.5, -0.8)})
    a.end()

    # Seated in the saddle. Hips stay at rest height so the mount offset stays simple.
    a.begin("ride")
    for k in range(5):
        f = k / 4
        b = math.sin(f * math.tau)
        pose = merged(CARRY,
                      LeftUpperLeg=(-42, -34, 0), RightUpperLeg=(-42, 34, 0),
                      LeftLowerLeg=(62, 0, 0), RightLowerLeg=(62, 0, 0),
                      LeftFoot=(-22, 0, 0), RightFoot=(-22, 0, 0),
                      Spine=(2 + b * 1.5, 0, 0), Chest=(2 + b, 0, 0))
        a.key(int(f * 24), pose)
    a.end()


# A blade alone at ease: the sword hangs as in CARRY, and the empty left arm hangs loose, not bent for a shield strap.
CARRY_FREE = merged(CARRY, LeftUpperArm=RELAXED["LeftUpperArm"], LeftLowerArm=RELAXED["LeftLowerArm"], LeftHand=RELAXED["LeftHand"])


def free_hand_swing(amount):
    """Walking with a blade and nothing in the other hand: both arms swing, the sword arm less."""
    def arms(turn):
        swing = amount * math.cos(turn)
        pose = dict(CARRY_FREE)
        nudged(pose, "RightUpperArm", rx=-swing * 0.6)
        nudged(pose, "LeftUpperArm", rx=swing)
        nudged(pose, "LeftLowerArm", rx=-abs(swing) * 0.3)
        return pose

    return arms




def animate_free_hand(a, legs):
    """A blade and an empty left hand, which makes a fist on guard, hangs loose at ease and closes loosely running.
    Anyone fighting with nothing in their hands fights with these too."""
    a.two_hands = False
    a.hands("grip", "fist")
    fight_set(a, legs, "_free", READY_FREE, with_arm(BLADE_BLOWS, FREE_REACH, own=False), FREE_GUARDS)
    a.hands("grip", "relaxed")
    ease_idle(a, legs, "idle_free", CARRY_FREE)
    locomotion(a, legs, "walk_free", WALK_FRAMES, WALK_STRIDE, WALK_STANCE, -16.0, 34.0, WALK_LIFT, 0.024, 0.012, WALK_STANCE * 0.5, 0.016, 5.0, 2.5, 4.0, free_hand_swing(14), peak=WALK_PEAK)
    a.hands("grip", "loose")
    run_cycle(a, legs, "run_free", JOG, sword_run_arms(True))
    run_cycle(a, legs, "sprint_free", SPRINT, sword_run_arms(True))


def animate_unarmed(a, legs):
    """Empty hands: a soft half-curl standing and walking, a loose fist running."""
    a.two_hands = False
    a.hands("relaxed", "relaxed")
    ease_idle(a, legs, "idle_unarmed", RELAXED)
    locomotion(a, legs, "walk_unarmed", WALK_FRAMES, WALK_STRIDE, WALK_STANCE, -16.0, 34.0, WALK_LIFT, 0.024, 0.012, WALK_STANCE * 0.5, 0.016, 5.0, 2.5, 3.0, free_swing(20, 14), peak=WALK_PEAK)
    a.hands("loose", "loose")
    run_cycle(a, legs, "run_unarmed", JOG, runner_arms(RELAXED))
    run_cycle(a, legs, "sprint_unarmed", SPRINT, runner_arms(RELAXED))
