"""Project-made environment props for the Aviary: log, stump, nest, egg (chunky, flat-colored, low poly).

Run: Blender -b --python tools/blender/build_env_props.py -- <project_root>
Outputs: assets/env/{log,stump,nest,egg}.glb and assets/env/source/env_props.blend
Material names (colored in Godot by scripts/env_prop.gd): bark, wood, twig, nest_in, shell.
Z-up, origin at the base center.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from shape_exploration import ellipsoid  # noqa: E402
from shape_exploration import tube as _tube  # noqa: E402

ROOT = sys.argv[sys.argv.index("--") + 1]
OUT = os.path.join(ROOT, "assets/env")
MATS = ["bark", "wood", "twig", "nest_in", "shell"]
M = {n: i for i, n in enumerate(MATS)}


def tube(bm, *a, **k):
    f = _tube(bm, *a, **k)
    bmesh.ops.recalc_face_normals(bm, faces=f)
    return f


def export(name, bm, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for n in MATS:
        me.materials.append(bpy.data.materials[n])
    for p in me.polygons:
        p.use_smooth = smooth
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=True,
                              export_animations=False)
    print(f"PROP {name} tris={sum(len(p.vertices) - 2 for p in me.polygons)}")


def cylinder(bm, r0, r1, length, segs, slot_side, slot_cap, rot=None, center=(0, 0, 0)):
    geo = bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r0, radius2=r1, depth=length)
    verts = geo["verts"]
    faces = {f for v in verts for f in v.link_faces}
    for f in faces:
        f.material_index = slot_cap if abs(f.normal.z) > 0.9 else slot_side
    if rot is not None:
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=rot)
    bmesh.ops.translate(bm, verts=verts, vec=Vector(center))
    return verts


bpy.ops.wm.read_factory_settings(use_empty=True)
for n in MATS:
    bpy.data.materials.new(n)
os.makedirs(OUT, exist_ok=True)

# Log: chunky lying cylinder, cut ends showing wood, a stubby branch.
bm = bmesh.new()
cylinder(bm, 0.34, 0.31, 2.2, 10, M["bark"], M["wood"], rot=Matrix.Rotation(math.radians(90), 3, "Y"), center=(0, 0, 0.32))
tube(bm, [Vector((0.3, -0.2, 0.45)), Vector((0.45, -0.42, 0.62)), Vector((0.52, -0.5, 0.7))], [0.09, 0.06, 0.0], 6, M["bark"])
export("log", bm)

# Stump: short cylinder with wood top and a few root bumps.
bm = bmesh.new()
cylinder(bm, 0.52, 0.44, 0.55, 12, M["bark"], M["wood"], center=(0, 0, 0.275))
for k in range(5):
    a = 2 * math.pi * k / 5 + 0.3
    d = Vector((math.cos(a), math.sin(a), 0))
    ellipsoid(bm, (0.22, 0.12, 0.1), d * 0.48 + Vector((0, 0, 0.05)), 6, 4,
              rot=Matrix.Rotation(a, 3, "Z"), slot=M["bark"])
export("stump", bm)

# Nest: woven ring of twig tubes around a darker bowl.
bm = bmesh.new()
ellipsoid(bm, (0.32, 0.32, 0.08), (0, 0, 0.07), 10, 5, slot=M["nest_in"])
for k in range(11):
    a0 = 2 * math.pi * k / 11
    pts = []
    for s in range(5):
        a = a0 + s * 0.28
        r = 0.34 + 0.03 * math.sin(s * 2.0 + k)
        pts.append(Vector((math.cos(a) * r, math.sin(a) * r, 0.1 + 0.05 * math.sin(s * 1.7 + k * 0.9))))
    tube(bm, pts, [0.045, 0.05, 0.05, 0.045, 0.0], 5, M["twig"], flatten=0.8)
export("nest", bm)

# Egg: smooth, slightly pointy at the top.
bm = bmesh.new()
verts, _ = ellipsoid(bm, (0.09, 0.09, 0.115), (0, 0, 0.115), 10, 8, slot=M["shell"], top_squash=1.0)
for v in verts:
    if v.co.z > 0.115:
        t = (v.co.z - 0.115) / 0.115
        v.co.x *= 1.0 - 0.18 * t
        v.co.y *= 1.0 - 0.18 * t
export("egg", bm)

os.makedirs(os.path.join(OUT, "source"), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "source/env_props.blend"))
print("PROPS_OK")
