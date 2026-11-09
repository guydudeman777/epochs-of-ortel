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
    pelvis forward, in degrees, and the thighs take it up."""

    def __init__(self, root, left, right, yaw=0.0, roll=0.0, left_turn=0.0, right_turn=0.0, lean=0.0):
        self.root = tuple(root)
        self.lean = lean
        self.left = tuple(left)
        self.right = tuple(right)
        self.yaw = yaw
        self.roll = roll
        self.left_turn = left_turn
        self.right_turn = right_turn

    def but(self, **changes):
        out = Stance(self.root, self.left, self.right, self.yaw, self.roll, self.left_turn, self.right_turn, self.lean)
        for key, value in changes.items():
            setattr(out, key, tuple(value) if isinstance(value, (tuple, list)) else value)
        return out

    def lerp(self, other, t):
        def mix(a, b):
            return tuple(x + (y - x) * t for x, y in zip(a, b))
        return Stance(mix(self.root, other.root), mix(self.left, other.left), mix(self.right, other.right),
                      self.yaw + (other.yaw - self.yaw) * t, self.roll + (other.roll - self.roll) * t,
                      self.left_turn + (other.left_turn - self.left_turn) * t, self.right_turn + (other.right_turn - self.right_turn) * t,
                      self.lean + (other.lean - self.lean) * t)


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
           land_pitch=-10.0, push_pitch=48.0, arm=30.0, elbow=84.0)
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


def track_legs(a, legs, track):
    """Keys the legs and hips on every frame between (frame, stance) stops. A foot that moves lifts."""
    for (f0, s0), (f1, s1) in zip(track, track[1:]):
        for frame in range(f0, f1 + 1):
            t = smooth((frame - f0) / (f1 - f0))
            arc = math.sin(math.pi * (frame - f0) / (f1 - f0))
            now = s0.lerp(s1, t)
            pose = {"Hips": (now.lean, now.roll, now.yaw)}
            for side, a0, a1, foot, turn in (("Left", s0.left, s1.left, now.left, now.left_turn), ("Right", s0.right, s1.right, now.right, now.right_turn)):
                lift = STEP_LIFT * arc if a0 != a1 else 0.0
                pose.update(legs.pose(side, now.root, foot[0], lift=lift, lean=now.lean, yaw=now.yaw, roll=now.roll, across=foot[1], turn=turn))
            a.key(frame, pose, {"Root": now.root}, part="lower")


def key_upper(a, stops):
    """Keys the upper body at each (frame, pose) stop. When both hands hold one weapon, it keys every other frame
    between stops as well, so the second hand can be fitted to the weapon all the way."""
    for (f0, p0), (f1, p1) in zip(stops, stops[1:]):
        a.key(f0, p0, part="upper")
        if a.two_hands:
            for frame in range(f0 + 2, f1 - 1, 2):
                t = smooth((frame - f0) / (f1 - f0))
                a.key(frame, {bone: tuple(x + (y - x) * t for x, y in zip(p0.get(bone, (0, 0, 0)), p1.get(bone, (0, 0, 0))))
                              for bone in set(p0) | set(p1)}, part="upper")
    a.key(stops[-1][0], stops[-1][1], part="upper")


def lunge(plant_left, plant_right, root, yaw):
    return GUARD_STANCE.but(root=root, left=(plant_left, GUARD_STANCE.left[1]), right=(plant_right, GUARD_STANCE.right[1]),
                            yaw=yaw, right_turn=GUARD_STANCE.right_turn * 0.6, lean=GUARD_STANCE.lean + 3.0)


def strike(a, legs, name, base, wind, blow, through, plant_left=0.27, plant_right=-0.2, drop=0.0, hips=(-16.0, 6.0)):
    """A blow of 36 frames that lands on frame 18. The front foot steps in on the wind-up, and the hips turn into
    the blow just ahead of the shoulders. hips is how far they turn at the wind-up and at the blow."""
    a.begin(name)
    legs.clip = name
    key_upper(a, [(0, dict(base)), (8, merged(base, **wind)), (13, merged(base, **wind)), (18, merged(base, **blow)),
                  (23, merged(base, **through)), (36, dict(base))])
    y = GUARD_STANCE.root[1]
    track_legs(a, legs, [
        (0, GUARD_STANCE),
        (9, lunge(plant_left, plant_right, (0.0, y + 0.01, -0.045 - drop * 0.3), hips[0])),
        (13, lunge(plant_left, plant_right, (0.0, y + 0.015, -0.047 - drop * 0.3), hips[0] * 1.1)),
        (17, lunge(plant_left, plant_right, (0.0, y - 0.1, -0.065 - drop), hips[1])),
        (23, lunge(plant_left, plant_right, (0.0, y - 0.11, -0.07 - drop), hips[1] * 1.15)),
        (36, GUARD_STANCE),
    ])
    a.end()


def guard(a, legs, name, base, pose):
    """Raised by frame 5, held through frame 20, lowered by frame 32. The view holds it for as long as it is needed."""
    a.begin(name)
    legs.clip = name
    key_upper(a, [(0, dict(base)), (5, merged(base, **pose)), (20, merged(base, **pose)), (32, dict(base))])
    y = GUARD_STANCE.root[1]
    braced = GUARD_STANCE.but(root=(-0.005, y + 0.006, -0.07), left=(0.16, 0.035), right=(-0.19, -0.05))
    track_legs(a, legs, [(0, GUARD_STANCE), (5, braced), (20, braced.but(root=(-0.005, y + 0.014, -0.073))), (32, GUARD_STANCE)])
    a.end()


def flinch(a, legs, name, base, spine, chest, neck, arms, yaw=0.0):
    """Taking a blow: thrown by frame 4, recovered by frame 20. arms are the upper arms thrown out, or None to keep
    hold of a weapon in both hands."""
    a.begin(name)
    legs.clip = name
    hurt = merged(base, Spine=spine, Chest=chest, Neck=neck, Head=(neck[0] * 0.5, neck[1] * 0.5, neck[2] * 0.5))
    if arms is not None:
        hurt.update(RightUpperArm=arms[0], LeftUpperArm=arms[1])
    key_upper(a, [(0, dict(base)), (4, hurt), (9, hurt), (20, dict(base))])
    y = GUARD_STANCE.root[1]
    thrown = GUARD_STANCE.but(root=(0.0, y + 0.04, -0.045), yaw=GUARD_STANCE.yaw + yaw, lean=2.0)
    track_legs(a, legs, [(0, GUARD_STANCE), (4, thrown), (9, thrown.but(root=(0.0, y + 0.045, -0.05))), (20, GUARD_STANCE)])
    a.end()


# Blows with one hand, each as (wind-up, blow, follow-through, how the feet and hips go). The side named is the
# attacker's own, where the blow starts.
BLADE_BLOWS = {
    "attack": (
        dict(Spine=(-5, 0, -12), Chest=(-5, 0, -14), RightUpperArm=(-155, 0, -20), RightLowerArm=(-80, 0, 0), RightHand=(25, 0, 0)),
        dict(Spine=(10, 0, 10), Chest=(12, 0, 16), RightUpperArm=(-75, 0, 10), RightLowerArm=(-8, 0, 0), RightHand=(58, 0, 0), LeftUpperArm=(-5, 0, -30)),
        dict(Spine=(12, 0, 12), Chest=(14, 0, 18), RightUpperArm=(-35, 0, 18), RightLowerArm=(-12, 0, 0), RightHand=(50, 0, 0)),
        dict(hips=(-14.0, 4.0))),
    "attack_right": (
        dict(Spine=(0, 0, -14), Chest=(0, 0, -22), RightUpperArm=(-82, 0, -72), RightLowerArm=(-62, 0, 0), RightHand=(30, 0, 0)),
        dict(Spine=(6, 0, 10), Chest=(6, 0, 16), RightUpperArm=(-84, 0, 8), RightLowerArm=(-10, 0, 0), RightHand=(66, 0, 0), LeftUpperArm=(-5, 0, -30)),
        dict(Spine=(7, 0, 14), Chest=(8, 0, 22), RightUpperArm=(-72, 0, 48), RightLowerArm=(-18, 0, 0), RightHand=(60, 0, 0)),
        dict(hips=(-18.0, 8.0))),
    "attack_left": (
        dict(Spine=(0, 0, 14), Chest=(0, 0, 22), RightUpperArm=(-72, 0, 62), RightLowerArm=(-100, 0, 0), RightHand=(10, 0, 0)),
        dict(Spine=(6, 0, -8), Chest=(6, 0, -14), RightUpperArm=(-86, 0, -4), RightLowerArm=(-8, 0, 0), RightHand=(66, 0, 0)),
        dict(Spine=(7, 0, -12), Chest=(8, 0, -20), RightUpperArm=(-78, 0, -55), RightLowerArm=(-16, 0, 0), RightHand=(58, 0, 0)),
        dict(hips=(4.0, -18.0))),
    # The hand draws back to the hip, then drives straight at the enemy. The body turns left into it, so the arm
    # angles back right to keep the point on the line.
    "attack_thrust": (
        dict(Spine=(-2, 0, -12), Chest=(-2, 0, -16), RightUpperArm=(14, 0, -6), RightLowerArm=(-100, 0, 0), RightHand=(58, 0, 0)),
        dict(Spine=(10, 0, 8), Chest=(10, 0, 10), RightUpperArm=(-84, 0, -26), RightLowerArm=(-6, 0, 0), RightHand=(78, 0, 0)),
        dict(Spine=(12, 0, 10), Chest=(12, 0, 12), RightUpperArm=(-80, 0, -24), RightLowerArm=(-10, 0, 0), RightHand=(72, 0, 0)),
        dict(plant_left=0.32, plant_right=-0.22, hips=(-18.0, 6.0))),
    "attack_low": (
        dict(Spine=(6, 0, -16), Chest=(4, 0, -22), RightUpperArm=(-55, 0, -70), RightLowerArm=(-48, 0, 0), RightHand=(25, 0, 0)),
        dict(Spine=(20, 0, 8), Chest=(18, 0, 14), RightUpperArm=(-42, 0, 6), RightLowerArm=(-6, 0, 0), RightHand=(62, 0, 0), Neck=(-22, 0, 0)),
        dict(Spine=(20, 0, 12), Chest=(18, 0, 20), RightUpperArm=(-36, 0, 42), RightLowerArm=(-12, 0, 0), RightHand=(55, 0, 0), Neck=(-22, 0, 0)),
        dict(plant_left=0.34, plant_right=-0.26, drop=0.09, hips=(-16.0, 6.0))),
}
SHIELD_GUARDS = {
    "block_up": dict(LeftUpperArm=(-105, 0, -50), LeftLowerArm=(-62, 0, -30), Spine=(1, 0, 0), Chest=(0, 0, 0), Neck=(-8, 0, 0),
                     RightUpperArm=(-118, 0, -22), RightLowerArm=(-72, 0, 0), RightHand=(55, 0, 0)),
    "block_left": dict(LeftUpperArm=(-62, 0, -45), LeftLowerArm=(-50, 0, -30), Spine=(4, 0, 14), Chest=(5, 0, 18), Neck=(-6, 0, -10),
                       RightUpperArm=(-60, 0, 38), RightLowerArm=(-92, 0, 0), RightHand=(30, 0, 0)),
    "block_right": dict(Spine=(4, 0, -12), Chest=(5, 0, -16), Neck=(-6, 0, 12), RightUpperArm=(-52, 0, -38), RightLowerArm=(-88, 0, 0), RightHand=(50, 0, 0),
                        LeftUpperArm=(-58, 0, -62), LeftLowerArm=(-52, 0, -30), LeftHand=(0, 0, 0)),
    "block_low": dict(LeftUpperArm=(-36, 0, -48), LeftLowerArm=(-30, 0, -24), Spine=(12, 0, 6), Chest=(10, 0, 8), Neck=(-16, 0, 0),
                      RightUpperArm=(-34, 0, 20), RightLowerArm=(-30, 0, 0), RightHand=(-40, 0, 0)),
}
# (spine, chest, neck, upper arms thrown out, turn of the hips)
FLINCHES = {
    "hit_front": ((-8, 0, 0), (-12, 0, 0), (-10, 0, 0), ((-20, 0, 16), (-20, 0, -30)), 0.0),
    "hit_left": ((-3, 8, 12), (-5, 10, 18), (-3, 0, 15), ((-25, 0, 10), (-14, 0, -30)), 8.0),
    "hit_right": ((-3, -8, -12), (-5, -10, -18), (-3, 0, -15), ((-14, 0, 20), (-25, 0, -22)), -8.0),
}

# A blade and nothing in the other hand: the free hand rides in front of the belly, out of the way and ready.
FREE_LEFT = {"LeftUpperArm": (-22, 0, -12), "LeftLowerArm": (-62, 0, -4), "LeftHand": (10, 0, 0)}
READY_FREE = merged(READY, **FREE_LEFT)
# Guarding with the blade alone, the free hand drawn in to the chest.
FREE_GUARD_LEFT = {"LeftUpperArm": (-26, 0, -18), "LeftLowerArm": (-92, 0, -6), "LeftHand": (10, 0, 0)}

# A spear in both hands, the right at the butt end by the hip and the left forward on the shaft, point at the
# enemy's chest. A spear pose says where the weapon lies, not how the arms bend: Spear is (x, y, z, rise, turn), the
# right hand's grip in the standing pose (x to the left, -y forward, z up, in metres) carried with the chest, and
# the shaft's rise and turn to the left in degrees, as the hips face. The hips tip forward on guard and more in a
# lunge, which tips the shaft down with them, so a level thrust asks for a little rise. The build turns the right arm to hold it there and closes the
# left hand on the shaft. The arm angles here are only where it starts looking.
READY_SPEAR = merged(READY,
                     Spear=(-0.15, -0.1, 1.0, 16.0, 12.0),
                     RightUpperArm=(14, 0, 6), RightLowerArm=(-80, 0, 0), RightHand=(0, 0, 16),
                     LeftUpperArm=(-40, 0, -20), LeftLowerArm=(-50, 0, -10), LeftHand=(0, 0, 0),
                     Spine=(6, 0, -6), Chest=(5, 0, -9), Neck=(-15, 0, 15), Head=(-3, 0, 0))
# Carried upright at ease in the right hand, butt down by the foot.
CARRY_SPEAR = merged(CARRY, Spear=(-0.21, -0.1, 1.1, 80.0, 0.0),
                     RightUpperArm=(-8, 0, 6), RightLowerArm=(-100, 0, 0), RightHand=(-22, 0, 0),
                     LeftUpperArm=(2, 0, -4), LeftLowerArm=(-14, 0, 0), LeftHand=(6, 0, 0))


def spear_jab(spine, chest, spear, neck=None):
    out = dict(Spine=spine, Chest=chest, Spear=spear)
    if neck is not None:
        out["Neck"] = neck
    return out


# Every spear blow is a thrust from the hip, at the head, the body, either side or the legs. The draw pulls the
# grip back past the hip; the blow drives it out with the body turning in behind it.
SPEAR_DRAW = spear_jab((3, 0, -12), (2, 0, -14), (-0.16, 0.14, 1.0, 14.0, 14.0), (-12, 0, 22))
SPEAR_BLOWS = {
    "attack": (spear_jab((2, 0, -12), (1, 0, -14), (-0.16, 0.12, 1.08, 22.0, 14.0), (-12, 0, 22)),
               spear_jab((8, 0, 6), (6, 0, 8), (-0.1, -0.3, 1.2, 24.0, 6.0), (-14, 0, -2)),
               spear_jab((9, 0, 7), (7, 0, 9), (-0.1, -0.31, 1.21, 24.0, 6.0), (-14, 0, -3)), dict(hips=(-18.0, 4.0))),
    "attack_thrust": (SPEAR_DRAW,
                      spear_jab((12, 0, 6), (10, 0, 8), (-0.1, -0.32, 1.05, 12.0, 6.0), (-16, 0, -2)),
                      spear_jab((13, 0, 8), (12, 0, 10), (-0.1, -0.34, 1.05, 12.0, 6.0), (-17, 0, -3)), dict(plant_left=0.32, plant_right=-0.22, hips=(-18.0, 4.0))),
    "attack_left": (SPEAR_DRAW,
                    spear_jab((10, 0, 14), (9, 0, 16), (-0.06, -0.3, 1.05, 12.0, 24.0), (-16, 0, -14)),
                    spear_jab((11, 0, 16), (10, 0, 18), (-0.05, -0.32, 1.05, 12.0, 26.0), (-16, 0, -16)), dict(hips=(-12.0, -2.0))),
    "attack_right": (SPEAR_DRAW,
                     spear_jab((10, 0, -6), (9, 0, -10), (-0.16, -0.3, 1.05, 12.0, -14.0), (-16, 0, 14)),
                     spear_jab((11, 0, -8), (10, 0, -12), (-0.16, -0.32, 1.05, 12.0, -16.0), (-16, 0, 16)), dict(hips=(-22.0, -10.0))),
    "attack_low": (SPEAR_DRAW,
                   spear_jab((20, 0, 4), (16, 0, 6), (-0.12, -0.3, 0.97, -10.0, 8.0), (-24, 0, 0)),
                   spear_jab((21, 0, 6), (17, 0, 8), (-0.12, -0.31, 0.96, -12.0, 8.0), (-24, 0, 0)), dict(plant_left=0.32, plant_right=-0.24, drop=0.09, hips=(-16.0, 4.0))),
}
# The shaft is raised across the blow: high and steep, swung to either side, or point down to sweep a low cut aside.
SPEAR_GUARDS = {
    "block_up": dict(Spine=(1, 0, -4), Chest=(0, 0, -6), Neck=(-10, 0, 12), Spear=(-0.18, -0.2, 1.22, 56.0, 18.0)),
    "block_left": dict(Spine=(4, 0, 10), Chest=(5, 0, 12), Neck=(-10, 0, -6), Spear=(-0.08, -0.22, 1.1, 48.0, 48.0)),
    "block_right": dict(Spine=(4, 0, -14), Chest=(5, 0, -18), Neck=(-10, 0, 24), Spear=(-0.24, -0.2, 1.08, 50.0, -22.0)),
    "block_low": dict(Spine=(12, 0, -4), Chest=(10, 0, -6), Neck=(-20, 0, 12), Spear=(-0.15, -0.22, 0.95, -22.0, 10.0)),
}


def fight_set(a, legs, suffix, base, blows, guards, keep_arms=False):
    """Every fighting clip for one way of being armed, named with suffix."""
    ready_idle(a, legs, "ready" + suffix, base)
    for name, (wind, blow, through, how) in blows.items():
        strike(a, legs, name + suffix, base, wind, blow, through, **how)
    for name, pose in guards.items():
        guard(a, legs, name + suffix, base, pose)
    for name, (spine, chest, neck, arms, yaw) in FLINCHES.items():
        flinch(a, legs, name + suffix, base, spine, chest, neck, None if keep_arms else arms, yaw)


def without_left(pose):
    return {bone: turn for bone, turn in pose.items() if not bone.startswith("Left")}


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
    # Blade and shield.
    fight_set(a, legs, "", READY, BLADE_BLOWS, SHIELD_GUARDS)
    # A spear in both hands.
    a.two_hands = True
    fight_set(a, legs, "_spear", READY_SPEAR, SPEAR_BLOWS, SPEAR_GUARDS, keep_arms=True)
    run_cycle(a, legs, "run_spear", JOG, spear_run_arms)
    run_cycle(a, legs, "sprint_spear", SPRINT, spear_run_arms)
    a.two_hands = False
    ease_idle(a, legs, "idle_spear", CARRY_SPEAR)
    locomotion(a, legs, "walk_spear", WALK_FRAMES, WALK_STRIDE, WALK_STANCE, -16.0, 34.0, WALK_LIFT, 0.024, 0.012, WALK_STANCE * 0.5, 0.016, 5.0, 2.5, 4.0,
               spear_carry_swing(14), peak=WALK_PEAK)

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
    """A blade and an empty left hand. The build keys these with the left fingers open."""
    a.two_hands = False
    # Blows that pulled the shield aside leave the free hand where it is.
    fight_set(a, legs, "_free", READY_FREE,
              {name: (without_left(w), without_left(b), without_left(t), how) for name, (w, b, t, how) in BLADE_BLOWS.items()},
              {name: merged(without_left(pose), **FREE_GUARD_LEFT) for name, pose in SHIELD_GUARDS.items()})
    ease_idle(a, legs, "idle_free", CARRY_FREE)
    locomotion(a, legs, "walk_free", WALK_FRAMES, WALK_STRIDE, WALK_STANCE, -16.0, 34.0, WALK_LIFT, 0.024, 0.012, WALK_STANCE * 0.5, 0.016, 5.0, 2.5, 4.0, free_hand_swing(14), peak=WALK_PEAK)
    run_cycle(a, legs, "run_free", JOG, sword_run_arms(True))
    run_cycle(a, legs, "sprint_free", SPRINT, sword_run_arms(True))


def animate_unarmed(a, legs):
    a.two_hands = False
    ease_idle(a, legs, "idle_unarmed", RELAXED)
    locomotion(a, legs, "walk_unarmed", WALK_FRAMES, WALK_STRIDE, WALK_STANCE, -16.0, 34.0, WALK_LIFT, 0.024, 0.012, WALK_STANCE * 0.5, 0.016, 5.0, 2.5, 3.0, free_swing(20, 14), peak=WALK_PEAK)
    run_cycle(a, legs, "run_unarmed", JOG, runner_arms(RELAXED))
    run_cycle(a, legs, "sprint_unarmed", SPRINT, runner_arms(RELAXED))
