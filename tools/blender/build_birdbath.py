"""Birdbath prop for the Birdbath map: stone plinth, tapered column, wide shallow lathed bowl (low poly).

Run: Blender -b --python tools/blender/build_birdbath.py -- <project_root>
Outputs: assets/env/birdbath.glb and assets/env/source/birdbath.blend
Material names (colored in Godot by scripts/env_prop.gd): stone, stone_dark, basin.
Z-up, origin at the base center. Bowl rim top at z = 1.14, inner radius ~0.80 (the water disc sits at ~1.11).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

ROOT = sys.argv[sys.argv.index("--") + 1]
OUT = os.path.join(ROOT, "assets/env")
MATS = ["stone", "stone_dark", "basin"]
M = {n: i for i, n in enumerate(MATS)}


def cylinder(bm, r0, r1, length, segs, slot_side, slot_cap, z):
    geo = bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r0, radius2=r1, depth=length)
    for f in {f for v in geo["verts"] for f in v.link_faces}:
        f.material_index = slot_cap if abs(f.normal.z) > 0.9 else slot_side
    bmesh.ops.translate(bm, verts=geo["verts"], vec=Vector((0, 0, z)))


def lathe(bm, profile, segs):
    """profile: [(r, z, slot)] from the outer bottom, over the rim, down to the inner center (r = 0 last)."""
    rings = []
    for r, z, _ in profile:
        if r <= 1e-4:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(2 * math.pi * k / segs), r * math.sin(2 * math.pi * k / segs), z))
                          for k in range(segs)])
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        slot = profile[i][2]
        for k in range(segs):
            k2 = (k + 1) % segs
            if len(b) == 1:
                f = bm.faces.new((a[k], a[k2], b[0]))
            else:
                f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
            f.material_index = slot
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


bpy.ops.wm.read_factory_settings(use_empty=True)
for n in MATS:
    bpy.data.materials.new(n)
os.makedirs(OUT, exist_ok=True)

bm = bmesh.new()
cylinder(bm, 0.56, 0.52, 0.14, 8, M["stone_dark"], M["stone"], 0.07)   # plinth
cylinder(bm, 0.40, 0.36, 0.10, 8, M["stone"], M["stone"], 0.19)        # step
cylinder(bm, 0.20, 0.15, 0.62, 8, M["stone"], M["stone"], 0.55)        # column
cylinder(bm, 0.27, 0.30, 0.08, 8, M["stone_dark"], M["stone"], 0.86)   # collar
lathe(bm, [
    (0.24, 0.88, M["stone"]),
    (0.58, 0.97, M["stone"]),
    (0.86, 1.07, M["stone_dark"]),
    (0.93, 1.13, M["stone"]),
    (0.88, 1.15, M["stone"]),
    (0.80, 1.12, M["basin"]),
    (0.62, 1.04, M["basin"]),
    (0.0, 1.00, M["basin"]),
], 16)
me = bpy.data.meshes.new("birdbath")
bm.to_mesh(me)
bm.free()
for n in MATS:
    me.materials.append(bpy.data.materials[n])
for p in me.polygons:
    p.use_smooth = False
ob = bpy.data.objects.new("birdbath", me)
bpy.context.scene.collection.objects.link(ob)
ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "birdbath.glb"), export_format="GLB", use_selection=True,
                          export_animations=False)
print(f"PROP birdbath tris={sum(len(p.vertices) - 2 for p in me.polygons)}")
os.makedirs(os.path.join(OUT, "source"), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "source/birdbath.blend"))
print("BIRDBATH_OK")
