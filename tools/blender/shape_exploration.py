"""Chibi shape exploration: 3 head-to-height ratios x 2 head styles (eagle, owl).

Run: Blender -b --python tools/blender/shape_exploration.py -- <project_root>
Outputs: assets/birds/exploration/ph_shape_<style>_<ratio>.glb (static meshes, no rig)
         assets/birds/source/ph_shape_exploration.blend

Proportions follow the design doc's Bird Base Model: ~1.0 m tall, origin at the feet, legs ~15%,
big separate head on a short neck (wider than the body), pear torso, chunky split beak (upper/lower),
eye patches, stubby wing-hands with feathered tips, oversized three-toed feet.
Z-up, faces -Y. Material slots use the fixed names (body, belly, beak, legs, eyes, accent).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else ""
OUT = os.path.join(ROOT, "assets/birds/exploration")
SLOTS = ["body", "belly", "beak", "legs", "eyes", "accent"]
LEG_H = 0.15


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for n in SLOTS:
        bpy.data.materials.new(n)


# --- mesh helpers -------------------------------------------------------------------

def ellipsoid(bm, radii, center, segs=16, rings=10, rot=None, slot=0, bottom_flare=0.0, top_squash=1.0):
    geo = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0, calc_uvs=True)
    verts = geo["verts"]
    for v in verts:
        x, y, z = v.co
        k = 1.0 + bottom_flare * max(-z, 0.0)  # pear: wider low
        zz = z * (top_squash if z > 0 else 1.0)
        v.co = Vector((x * radii[0] * k, y * radii[1] * k, zz * radii[2]))
    if rot is not None:
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=rot)
    bmesh.ops.translate(bm, verts=verts, vec=Vector(center))
    faces = {f for v in verts for f in v.link_faces}
    for f in faces:
        f.material_index = slot
    return verts, faces


def tube(bm, points, radii, sides=8, slot=0, flatten=1.0):
    """Sweep along a polyline (any direction), elliptical section; caps both ends."""
    rings = []
    for i, p in enumerate(points):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, len(points) - 1)]
        t = (b - a).normalized()
        ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
        side = t.cross(ref).normalized()
        up = side.cross(t).normalized()
        ring = []
        for s in range(sides):
            ang = 2 * math.pi * s / sides
            off = side * math.cos(ang) * radii[i] + up * math.sin(ang) * radii[i] * flatten
            ring.append(bm.verts.new(p + off))
        rings.append(ring)
    faces = []
    for i in range(len(rings) - 1):
        for s in range(sides):
            faces.append(bm.faces.new((rings[i][s], rings[i][(s + 1) % sides], rings[i + 1][(s + 1) % sides], rings[i + 1][s])))
    if radii[0] > 1e-4:
        faces.append(bm.faces.new(list(reversed(rings[0]))))
    if radii[-1] > 1e-4:
        faces.append(bm.faces.new(rings[-1]))
    for f in faces:
        f.material_index = slot
    return faces


def surface_y(rx, ry, rz, x, dz):
    """Front surface (negative Y) of an axis-aligned ellipsoid at local x, dz."""
    k = 1.0 - (x / rx) ** 2 - (dz / rz) ** 2
    return -ry * math.sqrt(max(k, 0.0))


def eye_patch(bm, center, rx, rz, yaw, slot, pitch=0.0):
    """Thin curved patch with planar UVs (u across, v up), for the eye atlas shader."""
    verts, faces = ellipsoid(bm, (rx, rx * 0.35, rz), (0, 0, 0), segs=14, rings=8, slot=slot)
    uv = bm.loops.layers.uv.verify()
    for f in faces:
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (co.x / (2 * rx) + 0.5, co.z / (2 * rz) + 0.5)
    rot = Matrix.Rotation(yaw, 3, "Z") @ Matrix.Rotation(pitch, 3, "X")
    bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=rot)
    bmesh.ops.translate(bm, verts=verts, vec=Vector(center))


# --- bird ---------------------------------------------------------------------------

def build(style, ratio):
    reset()
    bm = bmesh.new()
    S = {n: i for i, n in enumerate(SLOTS)}

    H = ratio                    # head height
    head_cz = 1.0 - H * 0.5
    torso_top = 1.0 - H + 0.04   # small overlap under the head = short neck
    torso_bot = LEG_H - 0.02
    T = torso_top - torso_bot
    W = {0.4: 0.62, 0.5: 0.56, 0.6: 0.5}[ratio]  # torso width shrinks as the head grows
    hw = max(H * 1.12, W + 0.1)                   # head always wider than the body

    # Torso (pear) with a belly patch on the lower front.
    _, faces = ellipsoid(bm, (W * 0.5, W * 0.46, T * 0.5), (0, 0.02, torso_bot + T * 0.5), 16, 10,
                         slot=S["body"], bottom_flare=0.18)
    for f in faces:
        c = f.calc_center_median()
        if f.normal.y < -0.35 and c.z < torso_bot + T * 0.75:
            f.material_index = S["belly"]

    # Neck (short).
    tube(bm, [Vector((0, 0.01, torso_top - 0.06)), Vector((0, 0.01, torso_top + 0.04))], [W * 0.26, W * 0.24], 10, S["body"])

    if style == "eagle":
        rx, ry, rz = hw * 0.5, H * 0.5, H * 0.47
        head_slot = S["accent"]  # white head
        _, hf = ellipsoid(bm, (rx, ry, rz), (0, 0, head_cz), 20, 12, slot=head_slot, top_squash=0.85)
        # Brow shelf: angular, stern line over the eyes.
        ellipsoid(bm, (rx * 0.7, ry * 0.3, rz * 0.12), (0, -ry * 0.68, head_cz + rz * 0.5), 14, 6,
                  rot=Matrix.Rotation(math.radians(-25), 3, "X"), slot=head_slot)
        # Big hooked beak: upper sweeps forward then hooks down; lower is a short wedge.
        s = H / 0.5
        by = surface_y(rx, ry, rz, 0, -rz * 0.12) + 0.03
        bz = head_cz - rz * 0.12
        up = [Vector((0, by + 0.04 * s, bz + 0.01 * s)), Vector((0, by - 0.06 * s, bz + 0.015 * s)),
              Vector((0, by - 0.14 * s, bz - 0.005 * s)), Vector((0, by - 0.19 * s, bz - 0.05 * s)),
              Vector((0, by - 0.195 * s, bz - 0.09 * s))]
        tube(bm, up, [0.085 * s, 0.08 * s, 0.06 * s, 0.035 * s, 0.0], 10, S["beak"], flatten=0.75)
        lo = [Vector((0, by + 0.02 * s, bz - 0.055 * s)), Vector((0, by - 0.07 * s, bz - 0.065 * s)),
              Vector((0, by - 0.12 * s, bz - 0.07 * s))]
        tube(bm, lo, [0.06 * s, 0.04 * s, 0.0], 8, S["beak"], flatten=0.6)
        eye_r, eye_rz, eye_x, eye_dz = 0.075 * s, 0.08 * s, rx * 0.4, rz * 0.26
    else:  # owl
        rx, ry, rz = hw * 0.56, H * 0.44, H * 0.46
        _, hf = ellipsoid(bm, (rx, ry, rz), (0, 0.01, head_cz), 20, 12, slot=S["body"], top_squash=0.8)
        s = H / 0.5
        # Facial disc: two overlapping flat discs (heart-shaped face) in the belly color.
        for sx in (-1, 1):
            dx = sx * rx * 0.36
            fy = surface_y(rx, ry, rz, dx, 0.0)
            ellipsoid(bm, (rx * 0.42, ry * 0.18, rz * 0.56), (dx, fy + ry * 0.12, head_cz - rz * 0.02), 14, 8,
                      rot=Matrix.Rotation(math.radians(-18 * sx), 3, "Z"), slot=S["belly"])
        # Ear tufts.
        for sx in (-1, 1):
            base = Vector((sx * rx * 0.62, 0.0, head_cz + rz * 0.62))
            tip = base + Vector((sx * 0.07 * s, 0.02, 0.13 * s))
            tube(bm, [base, base.lerp(tip, 0.5), tip], [0.07 * s, 0.045 * s, 0.0], 6, S["accent"], flatten=0.5)
        # Small but chunky hooked beak pointing down.
        by = surface_y(rx, ry, rz, 0, -rz * 0.15) - ry * 0.12
        bz = head_cz - rz * 0.12
        up = [Vector((0, by + 0.03 * s, bz + 0.03 * s)), Vector((0, by - 0.04 * s, bz - 0.01 * s)),
              Vector((0, by - 0.06 * s, bz - 0.08 * s)), Vector((0, by - 0.045 * s, bz - 0.12 * s))]
        tube(bm, up, [0.055 * s, 0.05 * s, 0.03 * s, 0.0], 8, S["beak"], flatten=0.8)
        lo = [Vector((0, by + 0.0, bz - 0.06 * s)), Vector((0, by - 0.03 * s, bz - 0.09 * s))]
        tube(bm, lo, [0.03 * s, 0.0], 6, S["beak"], flatten=0.7)
        eye_r, eye_rz, eye_x, eye_dz = 0.09 * s, 0.09 * s, rx * 0.38, rz * 0.16

    # Eye patches on the head front.
    for sx in (-1, 1):
        x = sx * eye_x
        if style == "owl":
            y = surface_y(rx, ry, rz, x, eye_dz) - ry * 0.12 - 0.01
        else:
            y = surface_y(rx, ry, rz, x, eye_dz) + 0.004
        tilt = -math.asin(min(eye_dz / rz, 0.9)) * 0.9  # face up-forward like the head surface
        eye_patch(bm, (x, y, head_cz + eye_dz), eye_r, eye_rz, math.radians(-22 * sx), S["eyes"], tilt)

    # Wings: stubby hands with 3 feathered tip lobes.
    for sx in (-1, 1):
        wz = torso_bot + T * 0.62
        wx = sx * (W * 0.5 + 0.02)
        rot = Matrix.Rotation(math.radians(-22 * sx), 3, "Y")
        ellipsoid(bm, (0.06, 0.12, 0.15 + T * 0.1), (wx, 0.0, wz), 10, 8, rot=rot, slot=S["body"])
        for k in range(3):
            tip = Vector((wx + sx * (0.05 + 0.012 * k), -0.06 + 0.06 * k, wz - 0.15 - T * 0.08 + 0.02 * abs(k - 1)))
            ellipsoid(bm, (0.035, 0.035, 0.06), tip, 8, 5, slot=S["accent"] if style == "eagle" else S["body"])

    # Tail: fanned feather plates.
    for k in (-1, 0, 1):
        rot = Matrix.Rotation(math.radians(55), 3, "X") @ Matrix.Rotation(math.radians(18 * k), 3, "Y")
        ellipsoid(bm, (0.06, 0.03, 0.13), (0.06 * k, W * 0.46 + 0.04, torso_bot + T * 0.25), 8, 6, rot=rot,
                  slot=S["accent"] if style == "eagle" else S["body"])

    # Legs and big three-toed feet.
    for sx in (-1, 1):
        lx = sx * W * 0.2
        tube(bm, [Vector((lx, 0.0, 0.035)), Vector((lx, 0.0, torso_bot + 0.04))], [0.026, 0.026], 6, S["legs"])
        ellipsoid(bm, (0.05, 0.05, 0.03), (lx, 0.0, 0.03), 8, 6, slot=S["legs"])  # ankle pad
        for ang in (-28, 0, 28):
            a = math.radians(ang)
            d = Vector((math.sin(a), -math.cos(a), 0))
            ellipsoid(bm, (0.035, 0.1, 0.03), Vector((lx, 0.0, 0.028)) + d * 0.085, 8, 6,
                      rot=Matrix.Rotation(-a, 3, "Z"), slot=S["legs"])
        ellipsoid(bm, (0.03, 0.06, 0.025), (lx, 0.06, 0.025), 6, 5, slot=S["legs"])  # back toe

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(f"ph_shape_{style}_{int(ratio * 100)}")
    bm.to_mesh(me)
    bm.free()
    for n in SLOTS:
        me.materials.append(bpy.data.materials[n])
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(me.name, me)
    bpy.context.scene.collection.objects.link(ob)
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, me.name + ".glb"), export_format="GLB",
                              use_selection=True, export_animations=False)
    print(f"SHAPE {me.name} tris={tris} height={max(v.co.z for v in me.vertices):.2f}")


if __name__ == "__main__":
    for style in ("eagle", "owl"):
        for ratio in (0.4, 0.5, 0.6):
            build(style, ratio)
    print("EXPLORATION_OK")
