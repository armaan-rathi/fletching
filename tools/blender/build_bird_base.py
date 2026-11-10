"""Base bird v2 (model quality pass): rigged chibi base (50% head) with a library of swappable parts on the
shared skeleton. v2 keeps v1's rig, bones, part names, head/eye placement and body shape keys, and rebuilds
the geometry: smoother heads/bodies, a clean oval belly patch, real feathered wings and tail fans, toed feet,
smoothed beaks, continuous collars/ruffs, S-curved long necks and an owl facial disc.

Run: Blender -b --python tools/blender/build_bird_base.py -- <project_root>
Outputs: assets/birds/bird_base.glb and assets/birds/source/bird_base.blend

One armature, every part a separate skinned mesh. Godot (BirdModel) shows the parts a bird uses.
Skeleton (fixed names): root body neck head beak_lower wing_L wing_R hand_L hand_R leg_L leg_R foot_L foot_R tail.
Conventions: Z-up, faces -Y, origin at the feet, ~1.0 m tall, character's left is +X.
Head parts are modelled tilted up HEAD_TILT degrees (pivot at the neck) so faces turn toward the game camera.
Eye patches are low-poly ellipses conforming to the head, with planar UVs for the eye atlas (UV top = eye top),
and the head's sphere normals so the lids shade exactly like the head around them.
Outline width: every vertex carries a width factor in its second UV map (u). The bird outline shader reads it
(UV2.x) so feather and toe tips get thin, crisp points instead of the full-width hull blob.
Budget: < 3,750 triangles per assembled bird (the 3k limit + 25%, user decision); checked at the end.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from shape_exploration import ellipsoid  # noqa: E402

ROOT = sys.argv[sys.argv.index("--") + 1]
SLOTS = ["body", "belly", "beak", "legs", "eyes", "accent"]
BUDGET = 3750
V = Vector

# Proportions (50% head).
H = 0.5
HEAD_CZ = 1.0 - H * 0.5
TORSO_TOP = 1.0 - H + 0.04
TORSO_BOT = 0.13
T = TORSO_TOP - TORSO_BOT
W = 0.56
HW = max(H * 1.12, W + 0.1)
HEAD_TILT = 12.0
PIVOT = V((0, 0.01, TORSO_TOP))
TILT = Matrix.Rotation(math.radians(-HEAD_TILT), 3, "X")
HEAD_C = V((0, 0, HEAD_CZ))
BODY_R = (W * 0.5, W * 0.46, T * 0.5)
BODY_C = V((0, 0.02, TORSO_BOT + T * 0.5))
BODY_FLARE = 0.18
HEAD_SEGS, HEAD_RINGS = 22, 14
EYE_SEGS = 20


def tilt(p):
    return PIVOT + TILT @ (V(p) - PIVOT)


# --- Parts ---------------------------------------------------------------------------

class Part:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.overrides = []  # (BMVert, center, weight): bend normals toward "radial from center"
        self.shape_keys = {}  # name -> fn(Vector co) -> Vector co (body shape keys)
        self.widths = {}  # BMVert -> outline width factor (default 1)
        self.weights = {}  # BMVert -> {bone: weight}, overrides weight_fn (e.g. per-ring neck weights)

    def sphere(self, verts, center, weight):
        for v in verts:
            self.overrides.append((v, V(center), weight))

    def mark(self):
        return len(self.bm.verts)

    def since(self, n):
        self.bm.verts.ensure_lookup_table()
        return [self.bm.verts[i] for i in range(n, len(self.bm.verts))]

    def finish(self, arm, weight_fn, head_part=False):
        bm = self.bm
        if head_part:
            bmesh.ops.rotate(bm, verts=list(bm.verts), cent=PIVOT, matrix=TILT)
            self.overrides = [(v, tilt(c), w) for v, c, w in self.overrides]
        bm.normal_update()
        bm.verts.index_update()
        ov = {v.index: (c, w) for v, c, w in self.overrides}
        wd = {v.index: w for v, w in self.widths.items()}
        wt = {v.index: w for v, w in self.weights.items()}
        me = bpy.data.meshes.new(self.name)
        bm.to_mesh(me)
        bm.free()
        for n in SLOTS:
            me.materials.append(bpy.data.materials[n])
        for p in me.polygons:
            p.use_smooth = True
        # UV0: eye atlas (eye patches) or unused; UV1 (UV2 in Godot): outline width factor in u.
        if len(me.uv_layers) == 0:
            me.uv_layers.new(name="UVMap")
        wl = me.uv_layers.new(name="OutlineWidth")
        for loop in me.loops:
            wl.data[loop.index].uv = (wd.get(loop.vertex_index, 1.0), 0.0)
        if ov:
            normals = []
            for v in me.vertices:
                n = v.normal.copy()
                if v.index in ov:
                    c, w = ov[v.index]
                    n = n.lerp((v.co - c).normalized(), w).normalized()
                normals.append(n)
            me.normals_split_custom_set_from_vertices(normals)
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        for b in BONES:
            ob.vertex_groups.new(name=b)
        for v in me.vertices:
            for b, w in (wt[v.index] if v.index in wt else weight_fn(v.co)).items():
                if w > 0:
                    ob.vertex_groups[b].add([v.index], w, "REPLACE")
        if self.shape_keys:
            ob.shape_key_add(name="Basis")
            for key, fn in self.shape_keys.items():
                sk = ob.shape_key_add(name=key)
                for i, v in enumerate(me.vertices):
                    sk.data[i].co = fn(v.co.copy())
        ob.parent = arm
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
        PART_TRIS[self.name] = sum(len(p.vertices) - 2 for p in me.polygons)
        return ob


PART_TRIS = {}
S = {n: i for i, n in enumerate(SLOTS)}


def rigid(bone):
    return lambda co: {bone: 1.0}


def by_side(left, right):
    return lambda co: {left if co.x > 0 else right: 1.0}


# --- Geometry helpers ------------------------------------------------------------------

def bezier(p0, p1, p2, p3, n):
    out = []
    for i in range(n):
        t = i / (n - 1)
        u = 1 - t
        out.append(p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t))
    return out


def catmull(points, radii, sub):
    """Catmull-Rom through `points` with `sub` segments per span (radii interpolated linearly)."""
    pts, rr = [], []
    n = len(points)
    for i in range(n - 1):
        p0, p1, p2, p3 = points[max(i - 1, 0)], points[i], points[i + 1], points[min(i + 2, n - 1)]
        for s in range(sub):
            t = s / sub
            t2, t3 = t * t, t * t * t
            pts.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
            rr.append(radii[i] + (radii[i + 1] - radii[i]) * t)
    pts.append(points[-1])
    rr.append(radii[-1])
    return pts, rr


def ramp(base, peak, tip, at=0.3):
    """Outline width profile for parts that start buried in another part: thin where buried, full once out,
    crisp at the tip."""
    return lambda f: base + (peak - base) * (f / at) if f < at else peak + (tip - peak) * ((f - at) / (1 - at)) ** 1.5


BEAK_W = None  # set below (needs ramp)


def blade(part, pts, radii, sides, slot, flatten=0.5, thin=None, tip_w=0.4, base_w=1.0, wfn=None, side=None):
    """Tapered feather / blade / limb along `pts`. Elliptical section; `flatten` is the thickness ratio along
    `thin` (its component across the path), so feathers can lie flat in any plane. A zero radius at an end makes
    a single pointed vertex; otherwise the end is capped. Outline width fades base_w -> tip_w along the path
    (or follows wfn(f), f = 0..1 along the path). `side` (instead of `thin`) fixes the WIDE axis: use it for
    paths that turn toward the thin axis (hooked beaks, nape feathers), where a thin-based frame would flip."""
    bm = part.bm
    n = len(pts)
    rings = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        if side is not None:
            s = (side - t * side.dot(t)).normalized()
            nn = s.cross(t).normalized()
        else:
            h = thin if thin is not None else (V((0, 0, 1)) if abs(t.z) < 0.9 else V((1, 0, 0)))
            nn = h - t * h.dot(t)
            if nn.length < 1e-6:
                nn = t.orthogonal()
            nn.normalize()
            s = t.cross(nn).normalized()
        f = i / (n - 1)
        w = wfn(f) if wfn else base_w + (tip_w - base_w) * f ** 1.5
        if radii[i] <= 1e-5:
            v = bm.verts.new(p)
            part.widths[v] = w
            rings.append([v])
            continue
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            v = bm.verts.new(p + s * (math.cos(a) * radii[i]) + nn * (math.sin(a) * radii[i] * flatten))
            part.widths[v] = w
            ring.append(v)
        rings.append(ring)
    faces = []
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        if len(a) == 1 and len(b) == 1:
            continue
        for k in range(sides):
            k2 = (k + 1) % sides
            if len(a) == 1:
                faces.append(bm.faces.new((a[0], b[k2], b[k])))
            elif len(b) == 1:
                faces.append(bm.faces.new((a[k], a[k2], b[0])))
            else:
                faces.append(bm.faces.new((a[k], a[k2], b[k2], b[k])))
    if len(rings[0]) > 1:
        faces.append(bm.faces.new(list(reversed(rings[0]))))
    if len(rings[-1]) > 1:
        faces.append(bm.faces.new(rings[-1]))
    for f in faces:
        f.material_index = slot
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return [v for r in rings for v in r]


def grid_faces(part, rows, slot, closed=True, outward=None):
    """Quads between consecutive rows of verts (each row a loop when closed). outward(face_center) -> Vector
    used to orient the result."""
    bm = part.bm
    faces = []
    for i in range(len(rows) - 1):
        a, b = rows[i], rows[i + 1]
        m = len(a) if closed else len(a) - 1
        for k in range(m):
            k2 = (k + 1) % len(a)
            faces.append(bm.faces.new((a[k], a[k2], b[k2], b[k])))
    for f in faces:
        f.material_index = slot
    if outward is not None:
        f = faces[0]
        f.normal_update()
        if f.normal.dot(outward(f.calc_center_median())) < 0:
            for f in faces:
                f.normal_flip()
    return faces


def ell_point(radii, center, squash, flare, d):
    """Point on a (top-squashed, bottom-flared) ellipsoid in unit direction d (same mapping as ellipsoid())."""
    k = 1.0 + flare * max(-d.z, 0.0)
    z = d.z * (squash if d.z > 0 else 1.0)
    return V((d.x * radii[0] * k, d.y * radii[1] * k, z * radii[2])) + center


def front_y(rx, ry, rz, center, x, z, top_squash):
    """Front surface y of a (top-squashed) ellipsoid at world x, z."""
    dz = z - center.z
    rzz = rz * (top_squash if dz > 0 else 1.0)
    k = 1.0 - (x / rx) ** 2 - (dz / rzz) ** 2
    return center.y - ry * math.sqrt(max(k, 0.02))


BEAK_W = ramp(0.15, 1.0, 0.25, at=0.25)  # beak bases sit inside the head: no hull poking through the face


# --- Skeleton ------------------------------------------------------------------------

HINGE = V((0, -0.2, HEAD_CZ - 0.06))
BONES = {
    "root": ((0, 0, 0), (0, 0, 0.1), None),
    "body": ((0, 0, 0.15), (0, 0, TORSO_TOP - 0.04), "root"),
    "neck": ((0, 0.01, TORSO_TOP - 0.04), tuple(PIVOT), "body"),
    "head": (tuple(PIVOT), tuple(tilt((0, 0.01, TORSO_TOP + 0.35))), "neck"),
    "beak_lower": (tuple(tilt(HINGE)), tuple(tilt(HINGE + V((0, -0.2, -0.02)))), "head"),
    "wing_L": ((0.29, 0.0, 0.46), (0.37, 0.0, 0.32), "body"),
    "hand_L": ((0.37, 0.0, 0.32), (0.41, -0.02, 0.2), "wing_L"),
    "wing_R": ((-0.29, 0.0, 0.46), (-0.37, 0.0, 0.32), "body"),
    "hand_R": ((-0.37, 0.0, 0.32), (-0.41, -0.02, 0.2), "wing_R"),
    "leg_L": ((0.11, 0.0, 0.16), (0.11, 0.0, 0.04), "root"),
    "foot_L": ((0.11, 0.0, 0.04), (0.11, -0.15, 0.03), "leg_L"),
    "leg_R": ((-0.11, 0.0, 0.16), (-0.11, 0.0, 0.04), "root"),
    "foot_R": ((-0.11, 0.0, 0.04), (-0.11, -0.15, 0.03), "leg_R"),
    "tail": ((0, 0.26, 0.26), (0, 0.42, 0.18), "body"),
}


def build_armature():
    data = bpy.data.armatures.new("bird_skeleton")
    arm = bpy.data.objects.new("bird_skeleton", data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (h, t, parent) in BONES.items():
        b = data.edit_bones.new(name)
        b.head = h
        b.tail = t
        b.roll = 0.0
        if parent:
            b.parent = data.edit_bones[parent]
            b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


# --- Body shape keys (doc: puff, hunch, slim, round) ----------------------------------

def _smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def _key_slim(co):
    return V((co.x * 0.85, 0.02 + (co.y - 0.02) * 0.88, co.z))


def _key_round(co):
    return V((co.x * 1.1, 0.02 + (co.y - 0.02) * 1.1, TORSO_BOT + (co.z - TORSO_BOT) * 0.97))


def _key_puff(co):
    w = _smooth(0.2, 0.42, co.z) * (1.0 - _smooth(0.5, 0.6, co.z))
    front = max(-(co.y - 0.02) / (W * 0.46), 0.0)
    return V((co.x * (1.0 + 0.06 * w), co.y - 0.09 * w * front, co.z + 0.02 * w * front))


def _key_hunch(co):
    t = max((co.z - TORSO_BOT) / T, 0.0)
    return V((co.x, co.y - 0.09 * t * t, co.z - 0.03 * t * t))


BODY_KEYS = {"slim": _key_slim, "round": _key_round, "puff": _key_puff, "hunch": _key_hunch}


def _wing_x(dx):
    return lambda co: V((co.x + (dx if co.x > 0 else -dx), co.y, co.z))


WING_KEYS = {"slim": _wing_x(-0.04), "round": _wing_x(0.03), "puff": _wing_x(0.025),
             "hunch": lambda co: V((co.x, co.y - 0.04 * max((co.z - 0.2) / 0.3, 0.0), co.z))}


# --- Shared parts --------------------------------------------------------------------

def belly_patch(p, slot):
    """Clean oval belly 'printed' 5 mm above the body's lower front (no outline on the belly slot)."""
    rows = []
    rings, segs = 5, 22
    cel, ha, hb = -0.22, 0.98, 0.66  # center elevation, half azimuth, half elevation (radians)
    for r in range(1, rings + 1):
        f = r / rings
        row = []
        for k in range(segs):
            th = 2 * math.pi * k / segs
            a, b = f * ha * math.cos(th), cel + f * hb * math.sin(th)
            d = V((math.sin(a) * math.cos(b), -math.cos(a) * math.cos(b), math.sin(b)))
            q = ell_point(BODY_R, BODY_C, 1.0, BODY_FLARE, d)
            row.append(p.bm.verts.new(q + (q - BODY_C).normalized() * 0.005))
        rows.append(row)
    d0 = V((0, -math.cos(cel), math.sin(cel)))
    q0 = ell_point(BODY_R, BODY_C, 1.0, BODY_FLARE, d0)
    top = p.bm.verts.new(q0 + (q0 - BODY_C).normalized() * 0.005)
    faces = [p.bm.faces.new((top, rows[0][(k + 1) % segs], rows[0][k])) for k in range(segs)]
    faces += grid_faces(p, rows, slot)
    for f in faces:
        f.material_index = slot
        f.normal_update()
        if f.normal.y > 0:
            f.normal_flip()
    return [top] + [v for r in rows for v in r]


def build_shared(arm):
    p = Part("bird_body")
    bv, _ = ellipsoid(p.bm, BODY_R, BODY_C, 20, 12, slot=S["body"], bottom_flare=BODY_FLARE)
    soft_c = BODY_C + V((0, 0, 0.03))
    p.sphere(bv, soft_c, 0.45)
    p.sphere(belly_patch(p, S["belly"]), soft_c, 0.45)
    blade(p, [V((0, 0.01, TORSO_TOP - 0.06)), V((0, 0.01, TORSO_TOP + 0.05))], [0.1, 0.095], 10, S["body"],
          flatten=1.0, tip_w=1.0)

    def body_w(co):
        t = min(max((co.z - 0.46) / 0.1, 0.0), 1.0)
        return {"body": 1.0 - t, "neck": t}

    p.shape_keys = BODY_KEYS
    p.finish(arm, body_w)

    # Wings: folded at the side, a teardrop covert from the shoulder sweeping down and back, with four pointed
    # primaries fanned along its trailing edge toward the tail.
    p = Part("wings_basic")
    for sx in (-1, 1):
        thin = V((sx, 0, 0))
        pts = bezier(V((sx * 0.24, -0.03, 0.56)), V((sx * 0.32, -0.035, 0.46)), V((sx * 0.35, 0.05, 0.33)),
                     V((sx * 0.335, 0.13, 0.26)), 6)
        blade(p, pts, [0.05, 0.092, 0.11, 0.1, 0.08, 0.05], 10, S["body"], flatten=0.42, thin=thin, tip_w=1.0)
        for k in range(4):
            f = k / 3
            base = V((sx * (0.338 - 0.004 * k), -0.01 + 0.12 * f, 0.36 - 0.09 * f))
            d = V((0, 0.5 + 0.35 * f, -0.86 + 0.42 * f)).normalized()
            ln = 0.14 + 0.03 * f
            tip = base + d * ln + V((sx * 0.012, 0, 0))
            pts = bezier(base, base + d * (ln * 0.4), tip - d * (ln * 0.3) + V((0, -0.01, 0.006)), tip, 5)
            blade(p, pts, [0.036, 0.037, 0.03, 0.017, 0.0], 6, S["body"], flatten=0.36, thin=thin,
                  wfn=ramp(0.5, 0.95, 0.3))

    def wing_w(co):
        side = "L" if co.x > 0 else "R"
        t = min(max((0.4 - co.z) / 0.2, 0.0), 1.0)
        return {f"wing_{side}": 1.0 - t, f"hand_{side}": t}

    p.shape_keys = WING_KEYS
    p.finish(arm, wing_w)

    tail_fan("tail_fan", "accent", 5, 42.0, 0.21, 0.13, 0.05)
    tail_fan("tail_fan_plain", "body", 5, 42.0, 0.21, 0.13, 0.05)
    tail_fan("tail_short", "body", 3, 30.0, 0.14, 0.12, 0.048)

    # Legs: slim shanks with a round ankle.
    p = Part("legs_basic")
    for sx in (-1, 1):
        lx = sx * W * 0.2
        blade(p, [V((lx, 0.0, 0.03)), V((lx, 0.0, 0.1)), V((lx, 0.0, TORSO_BOT + 0.06))], [0.026, 0.024, 0.028], 8,
              S["legs"], flatten=1.0, tip_w=1.0)
        ellipsoid(p.bm, (0.04, 0.04, 0.032), (lx, 0.0, 0.034), 8, 5, slot=S["legs"])
    p.finish(arm, by_side("leg_L", "leg_R"))

    # Feet: three tapered forward toes that curl down at the tips, plus a back toe.
    p = Part("feet_big")
    for sx in (-1, 1):
        b = V((sx * W * 0.2, 0.0, 0.03))
        for ang, ln in ((-30, 0.112), (0, 0.13), (30, 0.112)):
            a = math.radians(ang)
            d = V((math.sin(a), -math.cos(a), 0))
            pts = bezier(b + d * 0.02, b + d * (ln * 0.45) + V((0, 0, 0.012)), b + d * (ln * 0.82) + V((0, 0, 0.002)),
                         b + d * ln + V((0, 0, -0.01)), 4)
            blade(p, pts, [0.03, 0.031, 0.026, 0.017], 6, S["legs"], flatten=0.72, thin=V((0, 0, 1)), tip_w=0.55)
        d = V((0, 1, 0))
        blade(p, [b + d * 0.01, b + d * 0.045 + V((0, 0, 0.004)), b + d * 0.072 + V((0, 0, -0.006))],
              [0.025, 0.022, 0.014], 6, S["legs"], flatten=0.72, thin=V((0, 0, 1)), tip_w=0.55)
    p.finish(arm, by_side("foot_L", "foot_R"))


def tail_fan(name, slot, n, spread, length, rise, width):
    """Fan of tapered tail feathers from the rump (+Y is back), over a small covert lump."""
    p = Part(name)
    base = V((0, BODY_R[1] - 0.01, TORSO_BOT + T * 0.28))
    thin = V((0, -0.6, 1)).normalized()
    for k in range(n):
        a = math.radians(spread * ((k - (n - 1) / 2) / ((n - 1) / 2) if n > 1 else 0.0))
        d = V((math.sin(a), math.cos(a), 0))
        ln = length * (1.0 - 0.12 * abs(k - (n - 1) / 2) / max((n - 1) / 2, 1))
        tip = base + d * ln + V((0, 0, rise))
        pts = bezier(base - d * 0.04, base + d * (ln * 0.35) + V((0, 0, rise * 0.15)), tip - d * (ln * 0.25), tip, 5)
        blade(p, pts, [width * 0.8, width, width * 0.95, width * 0.72, 0.0], 6, S[slot], flatten=0.3,
              thin=thin, wfn=ramp(0.25, 1.0, 0.35))
    p.finish(arm, rigid("tail"))


# --- Eye patches ---------------------------------------------------------------------

def eye_patch(name, arm, head, ex, ez, erx, erz, offset, segs=EYE_SEGS, deform=None, normal_w=1.0):
    """Ellipse patch laid onto the head front; planar UVs (u right, v up). The eye fills UV radius 0.5; an outer
    margin ring (UV radius 0.56, lid color) lets the shader draw the eye's edge as a smooth circle."""
    rx, ry, rz, c, squash = head
    p = Part(name)
    bm = p.bm
    uv = bm.loops.layers.uv.verify()

    def vert(u, v):
        x, z = ex + u * erx, ez + v * erz
        return bm.verts.new((x, front_y(rx, ry, rz, c, x, z, squash) - offset, z)), (u * 0.5 + 0.5, v * 0.5 + 0.5)

    center = vert(0.0, 0.0)
    rings = []
    for r in (0.55, 1.0, 1.12):
        rings.append([vert(r * math.cos(2 * math.pi * k / segs), r * math.sin(2 * math.pi * k / segs)) for k in range(segs)])

    def face(vs):
        f = bm.faces.new([a[0] for a in vs])
        f.material_index = S["eyes"]
        for loop, a in zip(f.loops, vs):
            loop[uv].uv = a[1]
        return f

    for k in range(segs):
        k2 = (k + 1) % segs
        face([center, rings[0][k], rings[0][k2]])
        for a, b in ((rings[0], rings[1]), (rings[1], rings[2])):
            face([a[k], b[k], b[k2], a[k2]])
    for f in bm.faces:
        f.normal_update()
        if f.normal.y > 0:
            f.normal_flip()
    if deform:
        for v in bm.verts:
            v.co = deform(v.co)
    p.sphere(list(bm.verts), c, normal_w)  # shade like the head under it (no visible lid rim)
    p.finish(arm, rigid("head"), head_part=True)


def front_patch(p, head, cx, cz, radius_fn, offset, slot, rings=5, segs=28):
    """A patch laid on the head front (projected along Y like the eye patches), outline radius_fn(theta)."""
    rx, ry, rz, c, squash = head
    bm = p.bm

    def lift(x, z):
        # Offset along -Y, scaled up where the head curves away (steep), so the head never pokes through.
        y = front_y(rx, ry, rz, c, x, z, squash)
        dz = z - c.z
        rzz = rz * (squash if dz > 0 else 1.0)
        n = V((x / rx ** 2, (y - c.y) / ry ** 2, dz / rzz ** 2)).normalized()
        return y - offset / max(abs(n.y), 0.3)

    center = bm.verts.new((cx, lift(cx, cz), cz))
    rows = []
    for r in range(1, rings + 1):
        f = r / rings
        row = []
        for k in range(segs):
            th = 2 * math.pi * k / segs
            ax, az = radius_fn(th)
            x, z = cx + f * ax * math.cos(th), cz + f * az * math.sin(th)
            row.append(bm.verts.new((x, lift(x, z), z)))
        rows.append(row)
    faces = [bm.faces.new((center, rows[0][(k + 1) % segs], rows[0][k])) for k in range(segs)]
    faces += grid_faces(p, rows, slot)
    for f in faces:
        f.material_index = slot
        f.normal_update()
        if f.normal.y > 0:
            f.normal_flip()
    return [center] + [v for r in rows for v in r]


# --- Collars and ruffs -----------------------------------------------------------------

def scallop_band(p, slot, segs, lobes, z_top, r_top, z_bot, r_bot, depth, front_extra, power=0.55, thick=0.014):
    """Closed feather band around the neck whose lower edge hangs in rounded scallops (longer in front)."""
    zm, rm = (z_top + z_bot) * 0.5 + 0.01, (r_top + r_bot) * 0.5 + 0.02
    prof = [(r_top, z_top), (rm, zm), (r_bot, z_bot)]
    outer = [[] for _ in prof]
    inner_bot, inner_top = [], []
    for k in range(segs):
        th = 2 * math.pi * k / segs
        d = V((math.cos(th), math.sin(th), 0))
        front = max(-math.sin(th), 0.0)
        drop = (depth + front_extra * front) * abs(math.cos(lobes * th / 2)) ** power
        for i, (r, z) in enumerate(prof):
            dz = -drop if i == 2 else (-drop * 0.35 if i == 1 else 0.0)
            outer[i].append(p.bm.verts.new(d * r + V((0, 0.01, z + dz))))
        inner_bot.append(p.bm.verts.new(d * (r_bot - thick) + V((0, 0.01, z_bot - drop + thick * 0.6))))
        inner_top.append(p.bm.verts.new(d * (r_top - thick) + V((0, 0.01, z_top))))
    rows = outer + [inner_bot, inner_top]
    grid_faces(p, rows, slot, outward=lambda q: V((q.x, q.y - 0.01, 0)))
    return [v for r in rows for v in r]


# --- Eagle ---------------------------------------------------------------------------

def build_eagle(arm):
    rx, ry, rz = HW * 0.5, H * 0.5, H * 0.47
    head = (rx, ry, rz, HEAD_C, 0.85)
    white = S["accent"]
    eye_rx, eye_rz, eye_x, eye_dz = 0.075, 0.08, rx * 0.4, rz * 0.24

    p = Part("head_eagle")
    hv, _ = ellipsoid(p.bm, (rx, ry, rz), HEAD_C, HEAD_SEGS, HEAD_RINGS, slot=white, top_squash=0.85)
    p.sphere(hv, HEAD_C, 1.0)
    for sx in (-1, 1):  # heavy V brow
        bx = sx * eye_x * 0.95
        bz = HEAD_CZ + eye_dz + eye_rz * 0.95
        by = front_y(rx, ry, rz, HEAD_C, bx, bz, 0.85) - 0.015
        rot = Matrix.Rotation(math.radians(-sx * 24), 3, "Y") @ Matrix.Rotation(math.radians(-18), 3, "X")
        bv, _ = ellipsoid(p.bm, (eye_rx * 1.55, 0.065, 0.042), (bx, by, bz), 8, 5, rot=rot, slot=white)
        p.sphere(bv, HEAD_C, 0.5)
    # Swept-back nape feathers: three points flicking out from the back of the head (buried bases: thin outline).
    for dx, dz, ln in ((-0.1, -0.02, 0.17), (0.0, 0.04, 0.2), (0.1, -0.02, 0.17)):
        b = HEAD_C + V((dx, ry * 0.62, dz))
        out = (b - HEAD_C).normalized()
        tip = b + out * 0.1 + V((dx * 0.5, ln * 0.6, -0.12))
        n0 = p.mark()
        pts = bezier(b, b + out * 0.07, tip - V((0, 0.06, -0.05)), tip, 5)
        blade(p, pts, [0.075, 0.07, 0.05, 0.026, 0.0], 6, white, flatten=0.35, side=V((1, 0, 0)),
              wfn=ramp(0.08, 0.7, 0.3, at=0.55))
        p.sphere(p.since(n0), HEAD_C, 0.3)
    p.finish(arm, rigid("head"), head_part=True)

    by = front_y(rx, ry, rz, HEAD_C, 0, HEAD_CZ - rz * 0.1, 0.85) + 0.05
    bz = HEAD_CZ - rz * 0.1
    p = Part("beak_hooked_upper")
    up = [V((0, by + 0.06, bz + 0.03)), V((0, by - 0.08, bz + 0.035)), V((0, by - 0.2, bz + 0.015)),
          V((0, by - 0.29, bz - 0.04)), V((0, by - 0.31, bz - 0.11)), V((0, by - 0.29, bz - 0.15))]
    pts, rr = catmull(up, [0.13, 0.12, 0.095, 0.06, 0.03, 0.012], 2)
    blade(p, pts, rr, 10, S["beak"], flatten=0.82, side=V((1, 0, 0)), wfn=BEAK_W)
    p.finish(arm, rigid("head"), head_part=True)
    p = Part("beak_hooked_lower")
    lo = [V((0, by + 0.04, bz - 0.07)), V((0, by - 0.09, bz - 0.085)), V((0, by - 0.19, bz - 0.09))]
    pts, rr = catmull(lo, [0.085, 0.06, 0.012], 2)
    blade(p, pts, rr, 8, S["beak"], flatten=0.6, side=V((1, 0, 0)), wfn=BEAK_W)
    p.finish(arm, rigid("beak_lower"), head_part=True)

    for side, sx in (("L", 1), ("R", -1)):
        eye_patch(f"eyes_eagle_{side}", arm, head, sx * eye_x, HEAD_CZ + eye_dz, eye_rx, eye_rz, 0.006)

    # Scalloped white collar: one continuous feather band, longer over the chest.
    p = Part("collar_scalloped")
    scallop_band(p, white, 40, 10, TORSO_TOP + 0.02, W * 0.3, TORSO_TOP - 0.055, W * 0.52, 0.045, 0.035)
    p.finish(arm, lambda co: {"body": 0.6, "neck": 0.4})


# --- Owl -----------------------------------------------------------------------------

def build_owl(arm):
    c = HEAD_C + V((0, 0.01, 0))
    rx, ry, rz = HW * 0.56, H * 0.44, H * 0.46
    head = (rx, ry, rz, c, 0.8)
    ex, ez = rx * 0.38, HEAD_CZ + rz * 0.16
    p = Part("head_owl")
    hv, _ = ellipsoid(p.bm, (rx, ry, rz), c, HEAD_SEGS, HEAD_RINGS, slot=S["body"], top_squash=0.8)
    p.sphere(hv, c, 1.0)

    # Heart-shaped facial disc: the union of two round lobes around the eyes, pointed down to the beak.
    lobe_r = 0.135

    def inside(x, z):
        for sx in (-1, 1):
            if ((x - sx * ex) / lobe_r) ** 2 + ((z - ez) / (lobe_r * 1.05)) ** 2 <= 1.0:
                return True
        # chin wedge toward the beak
        dz = ez - z
        return 0.0 <= dz <= 0.2 and abs(x) <= (0.2 - dz) * 0.75

    def radius_fn(th):
        dx, dz = math.cos(th), math.sin(th)
        lo, hi = 0.0, 0.45
        for _ in range(24):
            mid = (lo + hi) * 0.5
            if inside(dx * mid, ez + dz * mid):
                lo = mid
            else:
                hi = mid
        return lo, lo

    n0 = p.mark()
    front_patch(p, head, 0.0, ez, radius_fn, 0.012, S["belly"], rings=5, segs=32)
    p.sphere(p.since(n0), c, 1.0)
    for sx in (-1, 1):  # ear tufts
        b = V((sx * rx * 0.58, 0.0, HEAD_CZ + rz * 0.5))
        tip = b + V((sx * 0.08, 0.03, 0.15))
        pts = bezier(b, b + V((sx * 0.01, 0.0, 0.06)), tip - V((sx * 0.03, 0.0, 0.03)), tip, 5)
        blade(p, pts, [0.075, 0.07, 0.05, 0.026, 0.0], 6, S["accent"], flatten=0.45, thin=V((0, 1, 0)),
              wfn=ramp(0.35, 1.0, 0.3))
    p.finish(arm, rigid("head"), head_part=True)

    by = front_y(rx, ry, rz, c, 0, HEAD_CZ - rz * 0.15, 0.8) - ry * 0.12
    bz = HEAD_CZ - rz * 0.12
    p = Part("beak_owl_upper")
    up = [V((0, by + 0.03, bz + 0.03)), V((0, by - 0.04, bz - 0.01)), V((0, by - 0.06, bz - 0.08)), V((0, by - 0.045, bz - 0.12))]
    pts, rr = catmull(up, [0.055, 0.05, 0.03, 0.01], 2)
    blade(p, pts, rr, 8, S["beak"], flatten=0.8, side=V((1, 0, 0)), wfn=BEAK_W)
    p.finish(arm, rigid("head"), head_part=True)
    p = Part("beak_owl_lower")
    blade(p, [V((0, by + 0.0, bz - 0.06)), V((0, by - 0.03, bz - 0.09))], [0.03, 0.0], 6, S["beak"], flatten=0.7, wfn=BEAK_W)
    p.finish(arm, rigid("beak_lower"), head_part=True)

    for side, sx in (("L", 1), ("R", -1)):
        eye_patch(f"eyes_owl_{side}", arm, head, sx * ex, ez, 0.09, 0.09, 0.022)


# --- Generic heads, beaks, extras, tails (Stage 2 flock) ------------------------------

HEADS = {
    # name: radii, center, top squash, material slot, eyes (x as fraction of rx, dz as fraction of rz, rx, rz)
    "round": ((0.31, 0.25, 0.235), HEAD_C, 0.88, "body", (0.4, 0.2, 0.08, 0.085)),
    "slim": ((0.26, 0.23, 0.215), HEAD_C, 0.88, "body", (0.42, 0.2, 0.068, 0.072)),
    "bald": ((0.29, 0.25, 0.22), HEAD_C, 0.8, "accent", (0.4, 0.18, 0.072, 0.075)),
    # Crow: wedge head (see crow_deform) - eyes set wider since the front narrows.
    "crow": ((0.29, 0.255, 0.225), HEAD_C, 0.9, "body", (0.52, 0.2, 0.072, 0.076)),
    # Pigeon: a tall oval (narrow and high) instead of the wide squat dome.
    "pigeon": ((0.245, 0.235, 0.272), HEAD_C + V((0, 0, 0.02)), 0.92, "body", (0.44, 0.22, 0.074, 0.08)),
}


def crow_deform(co):
    """Wedge: the front narrows and the crown slopes down into the bill; the back of the head stays round."""
    r, c = HEADS["crow"][0], HEADS["crow"][1]
    rel = V(co) - c
    front = min(max(-rel.y / r[1], 0.0), 1.0) ** 1.1
    low = min(max(-rel.z / r[2], 0.0), 1.0)
    # Front narrows into the bill, the lower head narrows to a chin (triangle from the front too).
    x = rel.x * (1.0 - 0.5 * front) * (1.0 - 0.32 * low)
    y = rel.y * (1.0 + 0.2 * front)
    z = rel.z * (1.0 - 0.38 * front) if rel.z > 0 else rel.z * (1.0 - 0.12 * front)
    return c + V((x, y, z))


HEAD_DEFORM = {"crow": (crow_deform, 0.45)}  # name -> (deform, sphere-normal weight)


def head_tuple(name):
    r, c, sq, _, _ = HEADS[name]
    return (r[0], r[1], r[2], c, sq)


def beak_base(head, dz=-0.1, inset=0.05):
    rx, ry, rz, c, sq = head
    bz = c.z + rz * dz
    return front_y(rx, ry, rz, c, 0, bz, sq) + inset, bz


def build_generic_heads(arm):
    for name, (r, c, sq, slot, eye) in HEADS.items():
        p = Part(f"head_{name}")
        hv, _ = ellipsoid(p.bm, r, c, HEAD_SEGS, HEAD_RINGS, slot=S[slot], top_squash=sq)
        deform, nw = HEAD_DEFORM.get(name, (None, 1.0))
        if deform:
            for v in hv:
                v.co = deform(v.co)
        p.sphere(hv, c, nw)
        if name == "bald":  # small droopy brow lumps (gloomy vulture)
            for sx in (-1, 1):
                bx = sx * r[0] * eye[0] * 0.95
                bz = c.z + r[2] * eye[1] + eye[3] * 0.9
                by = front_y(r[0], r[1], r[2], c, bx, bz, sq) - 0.008
                rot = Matrix.Rotation(math.radians(sx * 14), 3, "Y")
                bv, _ = ellipsoid(p.bm, (eye[2] * 1.3, 0.04, 0.028), (bx, by, bz), 8, 5, rot=rot, slot=S[slot])
                p.sphere(bv, c, 0.5)
        p.finish(arm, rigid("head"), head_part=True)
        head = head_tuple(name)
        for side, sx in (("L", 1), ("R", -1)):
            eye_patch(f"eyes_{name}_{side}", arm, head, sx * r[0] * eye[0], c.z + r[2] * eye[1], eye[2], eye[3], 0.006,
                      deform=deform, normal_w=nw)


def _pts(by, bz, offs):
    return [V((0, by + dy, bz + dz)) for dy, dz in offs]


arm_ref = [None]


def beak_pair(name, head, upper, upper_r, lower, lower_r, fu=0.8, fl=0.6, dz=-0.1, inset=0.05, upper_tip=None, deform=None):
    """Upper half follows `head`, lower half follows `beak_lower`. upper_tip: (offs, radii) drawn in accent."""
    by, bz = beak_base(head, dz, inset)
    if deform:
        q = deform(V((0, by - inset, bz)))
        by, bz = q.y + inset, q.z
    upper_r = [max(r, 0.01) for r in upper_r]
    lower_r = [max(r, 0.01) for r in lower_r]
    if upper_tip:
        upper_tip = (upper_tip[0], [max(r, 0.01) for r in upper_tip[1]])
    p = Part(f"beak_{name}_upper")
    pts, rr = catmull(_pts(by, bz, upper), upper_r, 2)
    blade(p, pts, rr, 10, S["beak"], flatten=fu, side=V((1, 0, 0)), wfn=BEAK_W)
    if upper_tip:
        pts, rr = catmull(_pts(by, bz, upper_tip[0]), upper_tip[1], 2)
        blade(p, pts, rr, 10, S["accent"], flatten=fu, side=V((1, 0, 0)), wfn=ramp(0.9, 1.0, 0.35))
    p.finish(arm_ref[0], rigid("head"), head_part=True)
    p = Part(f"beak_{name}_lower")
    pts, rr = catmull(_pts(by, bz, lower), lower_r, 2)
    blade(p, pts, rr, 8, S["beak"], flatten=fl, side=V((1, 0, 0)), wfn=BEAK_W)
    p.finish(arm_ref[0], rigid("beak_lower"), head_part=True)
    return by, bz


def build_generic_beaks(arm):
    arm_ref[0] = arm
    rnd, slim, bald = head_tuple("round"), head_tuple("slim"), head_tuple("bald")
    # Crow: long, sharp, straight.
    beak_pair("sharp", rnd, [(0.05, 0.02), (-0.08, 0.015), (-0.2, -0.01), (-0.3, -0.04)], [0.08, 0.07, 0.04, 0.0],
              [(0.03, -0.04), (-0.1, -0.05), (-0.21, -0.055)], [0.055, 0.035, 0.0], fu=0.75)
    # Pigeon / rooster: short little cone.
    # Crow (wedge head): the long sharp bill continues the head's taper.
    beak_pair("crow", head_tuple("crow"), [(0.05, 0.03), (-0.08, 0.02), (-0.2, -0.005), (-0.31, -0.04)], [0.085, 0.068, 0.04, 0.0],
              [(0.03, -0.035), (-0.1, -0.045), (-0.22, -0.05)], [0.055, 0.035, 0.0], fu=0.72, deform=crow_deform)
    # Pigeon (tall head): short cone with the little cere bump at the base.
    beak_pair("pigeon", head_tuple("pigeon"), [(0.04, 0.012), (-0.045, 0.004), (-0.11, -0.03)], [0.058, 0.046, 0.0],
              [(0.02, -0.03), (-0.055, -0.04), (-0.085, -0.045)], [0.04, 0.028, 0.0], fu=0.8, dz=-0.18)
    beak_pair("short", rnd, [(0.04, 0.01), (-0.05, 0.0), (-0.12, -0.035)], [0.065, 0.05, 0.0],
              [(0.02, -0.035), (-0.06, -0.045), (-0.09, -0.05)], [0.045, 0.03, 0.0], fu=0.8)
    # Flamingo: chunky banana that bends down, black tip.
    beak_pair("banana", slim, [(0.05, 0.02), (-0.06, 0.02), (-0.13, -0.02), (-0.155, -0.08)], [0.08, 0.075, 0.068, 0.058],
              [(0.03, -0.05), (-0.08, -0.06), (-0.12, -0.1)], [0.06, 0.05, 0.0], fu=0.85,
              upper_tip=([(-0.155, -0.08), (-0.155, -0.14), (-0.135, -0.2)], [0.058, 0.045, 0.0]))
    # Swan: straight orange bill (the black knob is in mask_swan).
    beak_pair("swan", slim, [(0.05, 0.0), (-0.1, -0.01), (-0.2, -0.05)], [0.075, 0.06, 0.0],
              [(0.03, -0.04), (-0.15, -0.07)], [0.05, 0.0], fu=0.6)
    # Vulture: medium hook, paler.
    beak_pair("vulture", bald, [(0.05, 0.02), (-0.06, 0.025), (-0.15, 0.01), (-0.22, -0.03), (-0.235, -0.08), (-0.22, -0.11)],
              [0.1, 0.09, 0.07, 0.045, 0.022, 0.0], [(0.03, -0.055), (-0.07, -0.065), (-0.14, -0.07)], [0.065, 0.045, 0.0], fu=0.82)


def build_extras(arm):
    rnd, slim = head_tuple("round"), head_tuple("slim")

    # Rooster comb: four plump lobes over the crown (wide enough to read from the front) and wattles.
    rx, ry, rz, c, sq = rnd
    p = Part("comb_rooster")
    for k, (dy, h) in enumerate(((-0.14, 0.062), (-0.06, 0.088), (0.03, 0.084), (0.11, 0.062))):
        top = c.z + rz * sq * math.sqrt(max(1 - (dy / ry) ** 2, 0.1))
        ellipsoid(p.bm, (0.045, 0.05, h), (0, dy, top + h * 0.45), 8, 6, slot=S["accent"])
    p.finish(arm, rigid("head"), head_part=True)
    by, bz = beak_base(rnd)
    p = Part("wattle_rooster")
    for sx in (-1, 1):
        ellipsoid(p.bm, (0.034, 0.03, 0.058), (sx * 0.029, by - 0.03, bz - 0.11), 8, 6, slot=S["accent"])
    p.finish(arm, rigid("head"), head_part=True)

    # Flamingo crest: two soft feathers sweeping back from the crown.
    rx, ry, rz, c, sq = slim
    p = Part("tuft_flamingo")
    for dx, ln in ((-0.05, 0.13), (0.05, 0.13), (0.0, 0.16)):
        b = V((dx, ry * 0.6, c.z + rz * 0.05))
        out = (b - c).normalized()
        tip = b + out * 0.06 + V((dx * 0.6, ln * 0.7, -0.1))
        pts = bezier(b, b + out * 0.06, tip - V((0, 0.05, -0.04)), tip, 5)
        blade(p, pts, [0.045, 0.045, 0.034, 0.018, 0.0], 6, S["body"], flatten=0.38, side=V((1, 0, 0)),
              wfn=ramp(0.08, 0.7, 0.3, at=0.55))
    p.finish(arm, rigid("head"), head_part=True)

    # Swan: black knob on top of the bill base and the dark lores band where the bill meets the face.
    by, bz = beak_base(slim, inset=0.0)
    p = Part("mask_swan")
    ellipsoid(p.bm, (0.075, 0.03, 0.04), (0, by + 0.016, bz + 0.004), 10, 6, slot=S["accent"])
    ellipsoid(p.bm, (0.032, 0.04, 0.034), (0, by - 0.015, bz + 0.045), 8, 6, slot=S["accent"])
    p.finish(arm, rigid("head"), head_part=True)

    # Long-necked birds (swan, flamingo): a tapered S-curved neck that stretches when the head bone is raised
    # (neck_extend), so the S opens up into a graceful curve in game.
    p = Part("neck_stretch")
    n, z0, L = 10, TORSO_TOP - 0.1, 0.22
    pts, radii, rings_t = [], [], []
    for i in range(n):
        f = i / (n - 1)
        pts.append(V((0, 0.05 * math.sin(math.pi * f) - 0.02 * f, z0 + L * f)))
        radii.append(0.158 - 0.045 * f + 0.035 * max(f - 0.75, 0.0) / 0.25)
    verts = blade(p, pts, radii, 10, S["body"], flatten=1.0, wfn=lambda f: 0.6 if f < 0.12 else 1.0)
    # Each ring moves as a unit (weights by path fraction, not height): the neck stretches evenly when the
    # head bone is raised by neck_extend instead of shearing.
    for i in range(n):
        t = _smooth(0.1, 0.9, i / (n - 1))
        for v in verts[i * 10:(i + 1) * 10]:
            p.weights[v] = {"neck": 1.0 - t, "head": t}
    p.finish(arm, lambda co: {"neck": 1.0})

    # Vulture fluffy ruff (belly slot = white): one lumpy torus of puffs around the neck.
    p = Part("ruff_fluffy")
    segs, sides, R, zc = 28, 8, W * 0.4, TORSO_TOP - 0.035
    rows = []
    for k in range(segs):
        th = 2 * math.pi * k / segs
        d = V((math.cos(th), math.sin(th), 0))
        rr = 0.072 + 0.04 * abs(math.cos(3.5 * th)) ** 0.7
        ring = []
        for j in range(sides):
            ph = 2 * math.pi * j / sides
            ring.append(p.bm.verts.new(d * (R + rr * math.cos(ph)) + V((0, 0.02, zc + rr * 0.8 * math.sin(ph)))))
        rows.append(ring)
    faces = []
    for k in range(segs):
        a, b = rows[k], rows[(k + 1) % segs]
        for j in range(sides):
            j2 = (j + 1) % sides
            faces.append(p.bm.faces.new((a[j], a[j2], b[j2], b[j])))
    for f in faces:
        f.material_index = S["belly"]
    bmesh.ops.recalc_face_normals(p.bm, faces=faces)
    p.finish(arm, lambda co: {"body": 0.5, "neck": 0.5})

    # Pigeon iridescent neck band: a smooth collar with a softly scalloped lower edge.
    p = Part("collar_ruffle")
    scallop_band(p, S["accent"], 40, 14, TORSO_TOP + 0.03, W * 0.27, TORSO_TOP - 0.03, W * 0.42, 0.022, 0.012, power=0.7)
    p.finish(arm, lambda co: {"body": 0.6, "neck": 0.4})


def build_tails(arm):
    # Rooster sickle feathers: long blades arching up, over and down behind, plus short coverts.
    p = Part("tail_sickle")
    for dx, h, reach in ((-0.09, 0.27, 0.36), (-0.045, 0.33, 0.44), (0.0, 0.36, 0.48), (0.045, 0.32, 0.43),
                         (0.09, 0.26, 0.35)):
        b = V((dx * 0.5, 0.22, 0.3))
        pts = bezier(b, b + V((dx * 0.4, 0.05, h * 0.8)), b + V((dx * 1.1, reach * 0.9, h * 1.1)),
                     b + V((dx * 1.5, reach, h * 0.3)), 8)
        blade(p, pts, [0.05, 0.066, 0.072, 0.068, 0.06, 0.05, 0.034, 0.0], 6, S["body"], flatten=0.3,
              thin=V((1, 0, 0)), wfn=ramp(0.25, 1.0, 0.3, at=0.15))
    p.finish(arm, rigid("tail"))


# --- Main ----------------------------------------------------------------------------

bpy.ops.wm.read_factory_settings(use_empty=True)
for n in SLOTS:
    bpy.data.materials.new(n)
arm = build_armature()
build_shared(arm)
build_eagle(arm)
build_owl(arm)
build_generic_heads(arm)
build_generic_beaks(arm)
build_extras(arm)
build_tails(arm)

# Assembly per bird (mirrors data/birds/*.tres) — for the tri budget report.
SHARED = ["bird_body", "wings_basic", "legs_basic", "feet_big"]


def kit(head, beak, eyes, *extras):
    return SHARED + [f"head_{head}", f"beak_{beak}_upper", f"beak_{beak}_lower", f"eyes_{eyes}_L", f"eyes_{eyes}_R", *extras]


BIRDS = {
    "eagle": kit("eagle", "hooked", "eagle", "collar_scalloped", "tail_fan"),
    "flamingo": kit("slim", "banana", "slim", "tuft_flamingo", "neck_stretch", "tail_short"),
    "owl": kit("owl", "owl", "owl", "tail_fan"),
    "crow": kit("crow", "crow", "crow", "tail_fan_plain"),
    "pigeon": kit("pigeon", "pigeon", "pigeon", "collar_ruffle", "tail_fan_plain"),
    "rooster": kit("round", "short", "round", "comb_rooster", "wattle_rooster", "tail_sickle"),
    "swan": kit("slim", "swan", "slim", "mask_swan", "neck_stretch", "tail_short"),
    "vulture": kit("bald", "vulture", "bald", "ruff_fluffy", "tail_fan_plain"),
}
for k, v in sorted(PART_TRIS.items()):
    print(f"PART {k} tris={v}")
over = []
for b, parts in BIRDS.items():
    total = sum(PART_TRIS[p] for p in parts)
    print("ASSEMBLED %s tris=%d" % (b, total))
    if total > BUDGET:
        over.append(b)
if over:
    raise SystemExit("OVER BUDGET (%d): %s" % (BUDGET, over))

os.makedirs(os.path.join(ROOT, "assets/birds/source"), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "assets/birds/source/bird_base.blend"))
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/birds/bird_base.glb"), export_format="GLB",
                          export_skins=True, export_animations=False, export_yup=True, export_texcoords=True,
                          export_vertex_color="NONE")
print("BIRD_OK")
