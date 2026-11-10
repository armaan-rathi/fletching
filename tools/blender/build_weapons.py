"""Bow and arrow, chunky and flat-colored to match the birds.

Run: Blender -b --python tools/blender/build_weapons.py -- <project_root>
Outputs: assets/weapons/{bow,arrow}.glb and assets/weapons/source/weapons.blend

Bow: held flat (horizontal) so it reads from the top-down camera. Arc bulges forward (-Y),
tips at x = +/-0.38, y = +0.06. Origin at the grip's back. Materials: wood, grip, tips.
The string is drawn in Godot so it can be pulled.
Arrow: points forward (-Y), origin at the tip, length 0.9 m. Materials: shaft, head, fletching.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = sys.argv[sys.argv.index("--") + 1]

COLORS = {
    "wood": (0.55, 0.35, 0.2, 1),
    "grip": (0.25, 0.18, 0.15, 1),
    "tips": (0.9, 0.85, 0.7, 1),
    "shaft": (0.8, 0.65, 0.45, 1),
    "head": (0.6, 0.62, 0.66, 1),
    "fletching": (1.0, 0.35, 0.35, 1),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for name, col in COLORS.items():
        m = bpy.data.materials.new(name)
        m.diffuse_color = col


def to_object(name, bm, mats):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(bpy.data.materials[m])
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def sweep_tube(points, radii, sides, mat_fn):
    """Sweep a circle along a polyline lying in the XY plane (bow limbs)."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(points):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, len(points) - 1)]
        t = (b - a).normalized()
        n = Vector((0, 0, 1))
        side = t.cross(n).normalized()
        ring = []
        for s in range(sides):
            ang = 2 * math.pi * s / sides
            off = side * math.cos(ang) * radii[i] + n * math.sin(ang) * radii[i]
            ring.append(bm.verts.new(p + off))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for s in range(sides):
            f = bm.faces.new((rings[i][s], rings[i][(s + 1) % sides], rings[i + 1][(s + 1) % sides], rings[i + 1][s]))
            f.material_index = mat_fn(i / (len(rings) - 1))
    for ring in (rings[0], rings[-1]):
        f = bm.faces.new(ring if ring is rings[-1] else list(reversed(ring)))
        f.material_index = 2
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_bow():
    # Recurve-ish arc: y = -0.18 * (1 - (x/0.38)^2) with the tips flicking back.
    pts, radii = [], []
    n = 24
    for i in range(n + 1):
        u = -1 + 2 * i / n
        x = 0.38 * u
        y = -0.2 * (1 - u * u) + 0.06 * abs(u) ** 6
        pts.append(Vector((x, y + 0.06, 0)))
        radii.append(0.034 - 0.012 * abs(u) ** 2)

    def mat(t):
        if abs(t - 0.5) < 0.09:
            return 1  # grip
        if t < 0.06 or t > 0.94:
            return 2  # tips
        return 0

    bm = sweep_tube(pts, radii, 8, mat)
    return to_object("bow", bm, ["wood", "grip", "tips"])


def build_arrow():
    bm = bmesh.new()
    # Shaft from the back of the head to the nock.
    bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.022, radius2=0.022, depth=0.74, calc_uvs=True)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    bmesh.ops.translate(bm, verts=bm.verts, vec=Vector((0, 0.13 + 0.37, 0)))
    for f in bm.faces:
        f.material_index = 0
    # Head: 4-sided chunky point, tip at the origin.
    head_geo = bmesh.ops.create_cone(bm, cap_ends=True, segments=4, radius1=0.065, radius2=0.0, depth=0.16, calc_uvs=True)
    hv = head_geo["verts"]
    bmesh.ops.rotate(bm, verts=hv, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X") @ Matrix.Rotation(math.radians(45), 3, "Z"))
    bmesh.ops.translate(bm, verts=hv, vec=Vector((0, 0.08, 0)))
    for f in {f for v in hv for f in v.link_faces}:
        f.material_index = 1
    # Fletching: 3 fins near the back, slightly oversized.
    for k in range(3):
        ang = math.radians(90 + 120 * k)
        d = Vector((math.cos(ang), 0, math.sin(ang)))
        y0, y1 = 0.6, 0.86
        quad = [
            Vector((0, y0, 0)) + d * 0.02,
            Vector((0, y1 - 0.06, 0)) + d * 0.02,
            Vector((0, y1, 0)) + d * 0.1,
            Vector((0, y0 + 0.1, 0)) + d * 0.1,
        ]
        sweep = Vector((0, 0, 0)) + d.cross(Vector((0, 1, 0))).normalized() * 0.008
        front = [bm.verts.new(p + sweep) for p in quad]
        back = [bm.verts.new(p - sweep) for p in quad]
        faces = [bm.faces.new(front), bm.faces.new(list(reversed(back)))]
        for i in range(4):
            j = (i + 1) % 4
            faces.append(bm.faces.new((front[j], front[i], back[i], back[j])))
        for f in faces:
            f.material_index = 2
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = to_object("arrow", bm, ["shaft", "head", "fletching"])
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


def export(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_animations=False)


reset()
bow = build_bow()
arrow = build_arrow()
for ob in (bow, arrow):
    print(ob.name.upper() + "_TRIS", sum(len(p.vertices) - 2 for p in ob.data.polygons))
os.makedirs(os.path.join(ROOT, "assets/weapons/source"), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "assets/weapons/source/weapons.blend"))
export(bow, os.path.join(ROOT, "assets/weapons/bow.glb"))
export(arrow, os.path.join(ROOT, "assets/weapons/arrow.glb"))
print("WEAPONS_OK")
