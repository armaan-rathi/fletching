"""Shape iteration v2 at the chosen 50% head ratio: eagle (iterated) and owl (shared base changes).

Run: Blender -b --python tools/blender/shape_v2.py -- <project_root>
Outputs: assets/birds/exploration/ph_shape_{eagle,owl}_v2.glb (static meshes, no rig)

v2 changes (user feedback):
- Eagle: heavy V-shaped brow ridge, swept-back feather points at the back of the head, much bigger
  forward-projecting hooked beak, scalloped white collar draping onto the shoulders.
- Both: head shading normals smoothed toward a sphere (custom normals; brow/feathers/disc partly),
  slightly bigger wings with feathered tips, fewer segments to approach the 2k-tri budget.
Head ratio 50% is the base; per-bird variation of +/-5% is allowed via HEAD_RATIO.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from shape_exploration import LEG_H, SLOTS, ellipsoid, eye_patch, reset, surface_y  # noqa: E402
from shape_exploration import tube as _tube  # noqa: E402


def tube(bm, *args, **kwargs):
    """Swept tube with its winding fixed locally. (A global recalc_face_normals flipped the tilted
    eagle head, so only tubes, whose winding depends on sweep direction, are recalculated.)"""
    faces = _tube(bm, *args, **kwargs)
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces

ROOT = sys.argv[sys.argv.index("--") + 1]
OUT = os.path.join(ROOT, "assets/birds/exploration")
HEAD_RATIO = {"eagle": 0.5, "owl": 0.5}
HEAD_TILT = 12.0  # degrees the head pitches up (face toward the camera)

# (BMVert, sphere center, weight) — normals blended toward the sphere direction after meshing.
_normal_overrides = []


def sphere_normals(verts, center, weight):
    for v in verts:
        _normal_overrides.append((v, Vector(center), weight))


def collect_verts(bm, before):
    return [v for v in bm.verts if v.index == -1 or v not in before]


def build(style):
    reset()
    _normal_overrides.clear()
    bm = bmesh.new()
    S = {n: i for i, n in enumerate(SLOTS)}

    H = HEAD_RATIO[style]
    head_cz = 1.0 - H * 0.5
    torso_top = 1.0 - H + 0.04
    torso_bot = LEG_H - 0.02
    T = torso_top - torso_bot
    W = 0.56
    hw = max(H * 1.12, W + 0.1)
    s = H / 0.5

    # Torso (pear) with belly patch.
    _, faces = ellipsoid(bm, (W * 0.5, W * 0.46, T * 0.5), (0, 0.02, torso_bot + T * 0.5), 14, 8,
                         slot=S["body"], bottom_flare=0.18)
    for f in faces:
        c = f.calc_center_median()
        if f.normal.y < -0.35 and c.z < torso_bot + T * 0.75:
            f.material_index = S["belly" if style == "owl" else "body"]
    tube(bm, [Vector((0, 0.01, torso_top - 0.06)), Vector((0, 0.01, torso_top + 0.04))], [W * 0.26, W * 0.24], 8, S["body"])

    head_c = Vector((0, 0, head_cz))
    head_start = len(bm.verts)
    if style == "eagle":
        rx, ry, rz = hw * 0.5, H * 0.5, H * 0.47
        white = S["accent"]
        hv, _ = ellipsoid(bm, (rx, ry, rz), head_c, 16, 10, slot=white, top_squash=0.85)
        sphere_normals(hv, head_c, 1.0)

        eye_r, eye_rz, eye_x, eye_dz = 0.075 * s, 0.08 * s, rx * 0.4, rz * 0.24

        # 1. Heavy brow ridge: two thick wedges, inner ends low (stern V), jutting forward over the eyes.
        for sx in (-1, 1):
            bx = sx * eye_x * 0.95
            bz = head_cz + eye_dz + eye_rz * 0.95
            by = surface_y(rx, ry, rz, bx, bz - head_cz) - 0.015
            rot = Matrix.Rotation(math.radians(-sx * 24), 3, "Y") @ Matrix.Rotation(math.radians(-18), 3, "X")
            bv, _ = ellipsoid(bm, (eye_r * 1.55, 0.065 * s, 0.042 * s), (bx, by, bz), 8, 5, rot=rot, slot=white)
            sphere_normals(bv, head_c, 0.5)

        # 1b. Swept-back feather points at the back of the head.
        for k, (dx, dz) in enumerate(((-0.1, 0.02), (0.0, 0.09), (0.1, 0.02), (-0.05, -0.08), (0.05, -0.08))):
            base = Vector((dx * s, ry * 0.72, head_cz + dz * s))
            tip = base + Vector((dx * 0.7 * s, 0.22 * s, -0.09 * s))
            fv = len(bm.verts)
            tube(bm, [base, base.lerp(tip, 0.55), tip], [0.07 * s, 0.045 * s, 0.0], 5, white, flatten=0.45)
            bm.verts.ensure_lookup_table()
            sphere_normals([bm.verts[i] for i in range(fv, len(bm.verts))], head_c, 0.5)

        # 2. Big, chunky, forward-projecting hooked beak (upper + lower halves).
        by = surface_y(rx, ry, rz, 0, -rz * 0.1) + 0.05
        bz = head_cz - rz * 0.1
        up = [Vector((0, by + 0.06, bz + 0.03)), Vector((0, by - 0.08, bz + 0.035)),
              Vector((0, by - 0.2, bz + 0.015)), Vector((0, by - 0.29, bz - 0.04)),
              Vector((0, by - 0.31, bz - 0.11)), Vector((0, by - 0.29, bz - 0.15))]
        up = [Vector((p.x, p.y, p.z)) for p in up]
        tube(bm, up, [0.13 * s, 0.12 * s, 0.095 * s, 0.06 * s, 0.03 * s, 0.0], 10, S["beak"], flatten=0.82)
        lo = [Vector((0, by + 0.04, bz - 0.07)), Vector((0, by - 0.09, bz - 0.085)), Vector((0, by - 0.19, bz - 0.09))]
        tube(bm, lo, [0.085 * s, 0.06 * s, 0.0], 8, S["beak"], flatten=0.6)

        tip_slot = S["body"]  # eagle wings are dark; white tips read as claws
        tail_slot = white
    else:
        rx, ry, rz = hw * 0.56, H * 0.44, H * 0.46
        hv, _ = ellipsoid(bm, (rx, ry, rz), head_c + Vector((0, 0.01, 0)), 16, 10, slot=S["body"], top_squash=0.8)
        sphere_normals(hv, head_c, 1.0)
        for sx in (-1, 1):
            dx = sx * rx * 0.36
            fy = surface_y(rx, ry, rz, dx, 0.0)
            dv, _ = ellipsoid(bm, (rx * 0.42, ry * 0.18, rz * 0.56), (dx, fy + ry * 0.12, head_cz - rz * 0.02), 12, 6,
                              rot=Matrix.Rotation(math.radians(-18 * sx), 3, "Z"), slot=S["belly"])
            sphere_normals(dv, head_c, 0.5)
        for sx in (-1, 1):
            base = Vector((sx * rx * 0.62, 0.0, head_cz + rz * 0.62))
            tip = base + Vector((sx * 0.07 * s, 0.02, 0.13 * s))
            tube(bm, [base, base.lerp(tip, 0.5), tip], [0.07 * s, 0.045 * s, 0.0], 6, S["accent"], flatten=0.5)
        by = surface_y(rx, ry, rz, 0, -rz * 0.15) - ry * 0.12
        bz = head_cz - rz * 0.12
        up = [Vector((0, by + 0.03 * s, bz + 0.03 * s)), Vector((0, by - 0.04 * s, bz - 0.01 * s)),
              Vector((0, by - 0.06 * s, bz - 0.08 * s)), Vector((0, by - 0.045 * s, bz - 0.12 * s))]
        tube(bm, up, [0.055 * s, 0.05 * s, 0.03 * s, 0.0], 8, S["beak"], flatten=0.8)
        lo = [Vector((0, by + 0.0, bz - 0.06 * s)), Vector((0, by - 0.03 * s, bz - 0.09 * s))]
        tube(bm, lo, [0.03 * s, 0.0], 6, S["beak"], flatten=0.7)
        eye_r, eye_rz, eye_x, eye_dz = 0.09 * s, 0.09 * s, rx * 0.38, rz * 0.16
        tip_slot = S["body"]
        tail_slot = S["body"]

    # Eye patches (planar UVs for the atlas), tilted up to follow the head surface.
    for sx in (-1, 1):
        x = sx * eye_x
        if style == "owl":
            y = surface_y(rx, ry, rz, x, eye_dz) - 0.012
        else:
            y = surface_y(rx, ry, rz, x, eye_dz) + 0.004
        tilt = -math.asin(min(eye_dz / rz, 0.9)) * 0.9
        eye_patch(bm, (x, y, head_cz + eye_dz), eye_r, eye_rz, math.radians(-22 * sx), S["eyes"], tilt)

    # Tilt the whole head (and face parts) up so the face turns toward the 50-degree game camera.
    pivot = Vector((0, 0.01, torso_top))
    tilt_m = Matrix.Rotation(math.radians(-HEAD_TILT), 3, "X")  # -X rotation lifts the face (faces -Y)
    bm.verts.ensure_lookup_table()
    head_verts = [bm.verts[i] for i in range(head_start, len(bm.verts))]
    bmesh.ops.rotate(bm, verts=head_verts, cent=pivot, matrix=tilt_m)
    new_c = pivot + tilt_m @ (head_c - pivot)
    for i, (v, c, w) in enumerate(_normal_overrides):
        if (c - head_c).length < 1e-6:
            _normal_overrides[i] = (v, new_c, w)

    if style == "eagle":
        white = S["accent"]
        # 3. Scalloped white collar draping over the shoulders (two staggered rows).
        for row, (n, r, z, size) in enumerate(((11, W * 0.47, torso_top - 0.035, 1.0), (11, W * 0.5, torso_top - 0.075, 0.85))):
            for k in range(n):
                a = 2 * math.pi * (k + 0.5 * row) / n
                d = Vector((math.cos(a), math.sin(a), 0))
                c = d * r + Vector((0, 0.01, z))
                rot = Matrix.Rotation(a + math.pi / 2, 3, "Z") @ Matrix.Rotation(math.radians(-35), 3, "X")
                ellipsoid(bm, (0.075 * size, 0.028, 0.07 * size), c, 6, 4, rot=rot, slot=white)

    # 6. Slightly bigger wings with 4 feathered tips fanning down/out.
    for sx in (-1, 1):
        wz = torso_bot + T * 0.6
        wx = sx * (W * 0.5 + 0.03)
        rot = Matrix.Rotation(math.radians(-22 * sx), 3, "Y")
        ellipsoid(bm, (0.075, 0.15, 0.2 + T * 0.1), (wx, 0.0, wz), 8, 6, rot=rot, slot=S["body"])
        for k in range(4):
            fan = math.radians(-30 + 20 * k)
            base = Vector((wx + sx * 0.045, -0.08 + 0.055 * k, wz - 0.13))
            tip = base + Vector((sx * 0.05, math.sin(fan) * 0.05, -0.12 + 0.015 * abs(k - 1.5)))
            tube(bm, [base, base.lerp(tip, 0.5), tip], [0.035, 0.03, 0.0], 5, tip_slot, flatten=0.5)

    # Tail feather plates.
    for k in (-1, 0, 1):
        rot = Matrix.Rotation(math.radians(55), 3, "X") @ Matrix.Rotation(math.radians(18 * k), 3, "Y")
        ellipsoid(bm, (0.065, 0.03, 0.14), (0.06 * k, W * 0.46 + 0.04, torso_bot + T * 0.25), 6, 4, rot=rot, slot=tail_slot)

    # Legs and big three-toed feet.
    for sx in (-1, 1):
        lx = sx * W * 0.2
        tube(bm, [Vector((lx, 0.0, 0.035)), Vector((lx, 0.0, torso_bot + 0.04))], [0.026, 0.026], 6, S["legs"])
        ellipsoid(bm, (0.05, 0.05, 0.03), (lx, 0.0, 0.03), 6, 4, slot=S["legs"])
        for ang in (-28, 0, 28):
            a = math.radians(ang)
            d = Vector((math.sin(a), -math.cos(a), 0))
            ellipsoid(bm, (0.035, 0.1, 0.03), Vector((lx, 0.0, 0.028)) + d * 0.085, 6, 4,
                      rot=Matrix.Rotation(-a, 3, "Z"), slot=S["legs"])
        ellipsoid(bm, (0.03, 0.06, 0.025), (lx, 0.06, 0.025), 5, 4, slot=S["legs"])

    bm.normal_update()
    bm.verts.index_update()
    overrides = {v.index: (c, w) for v, c, w in _normal_overrides if v.is_valid}

    name = f"ph_shape_{style}_v2"
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for n in SLOTS:
        me.materials.append(bpy.data.materials[n])
    for p in me.polygons:
        p.use_smooth = True

    # 5. Smooth head shading: blend vertex normals toward the sphere direction from the head center.
    normals = []
    for v in me.vertices:
        n = v.normal.copy()
        if v.index in overrides:
            c, w = overrides[v.index]
            d = (v.co - c).normalized()
            n = n.lerp(d, w).normalized()
        normals.append(n)
    me.normals_split_custom_set_from_vertices(normals)

    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB",
                              use_selection=True, export_animations=False)
    print(f"SHAPE {name} tris={tris} height={max(v.co.z for v in me.vertices):.2f} sphere_normals={len(overrides)}")


for style in ("eagle", "owl"):
    build(style)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "assets/birds/source/ph_shape_v2.blend"))
print("V2_OK")
