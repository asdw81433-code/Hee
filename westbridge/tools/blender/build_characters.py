"""
WESTBRIDGE character asset builder (Blender 4.2+ / tested with Blender 5.3).

Builds the stylized character BASE MESH and the whole modular outfit library in
Blender, rigs everything to one armature that uses the game's bone names
(SkeletonProfileHumanoid + face bones), and exports:

    assets/characters/westbridge_characters.glb   <- imported by Godot
    assets/characters/source/westbridge_characters.blend  <- open/edit in Blender
    assets/characters/renders/*.png                 <- preview renders (--render)

Run:
    blender -b -P tools/blender/build_characters.py -- [--render] [--views]
or with the bpy module:
    python tools/blender/build_characters.py [--render] [--views]
(--views = front/back/side/size turnaround in A-pose, used by make_sheets.py)

Modelling techniques used: Skin modifier + Subdivision Surface for the body and
shoes, deformed quad spheres for the head, Metaballs for organic hair/beards,
garments fitted from the body surface (copied faces pushed along normals, so they
keep the body's shape keys), primitives for props, procedural joint weights.
Every part is a separate object so artists can refine any piece in Blender and
re-export; the Godot loader picks parts by object name.
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector, Quaternion, Matrix

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
RENDER = "--render" in ARGS
HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(PROJECT, "assets", "characters")
SRC_DIR = os.path.join(OUT_DIR, "source")
REN_DIR = os.path.join(OUT_DIR, "renders")

# Level of detail of the set being built: 0 = close-up game mesh, 1 = distant NPCs.
# The LOD1 set is exported next to LOD0 with every object name suffixed "_LOD1".
LOD = 0
LOD1_SKIP = ("Iris_", "LowerLid_", "Detail_Buttons", "Detail_CapBadge", "Text_", "Watch", "Acc_Earrings")
LOD0_MAX_TRIS = 640           # cap for rigid props (hats, shoes, beards...)
LOD1_RATIO = 0.36             # rigid props in the LOD1 set
LOD1_MAX_TRIS = 260
# Body-coverage bits (colour attribute "CoverMask" on the body, 4 bits per RGB channel):
# a body triangle is hidden in game when all 3 vertices carry the bit of a worn garment.
COVER_BITS = {"Top_TShirt": 0, "Top_LongSleeve": 1, "Top_ButtonShirt": 2, "Top_Polo": 3, "Top_Tank": 4,
              "Top_Hoodie": 5, "Top_Sweater": 6, "Pants_Long": 7, "Pants_Shorts": 8, "Pants_Cargo": 9,
              "Socks": 10, "Shoes": 11}
COVER = {}                    # garment name -> per-body-vertex keep flags (filled by garment())


def G(x, y, z):
    """Godot coordinates (Y up, character faces +Z) -> Blender (Z up, faces -Y)."""
    return Vector((x, -z, y))


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a))) if b != a else 0.0
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


# --------------------------------------------------------------------------- skeleton
# Joint positions (Godot space) - identical to HumanoidDef.bone_list({}) in the game.
JOINTS = {
    "Root": (0, 0, 0), "Hips": (0, 0.94, 0), "Spine": (0, 1.04, 0), "Chest": (0, 1.16, 0),
    "UpperChest": (0, 1.28, 0), "Neck": (0, 1.43, 0), "Head": (0, 1.53, 0),
}
PARENT = {"Hips": "Root", "Spine": "Hips", "Chest": "Spine", "UpperChest": "Chest", "Neck": "UpperChest", "Head": "Neck"}
for side, sg in (("Left", 1), ("Right", -1)):
    JOINTS[side + "Shoulder"] = (0.04 * sg, 1.39, 0)
    JOINTS[side + "UpperArm"] = (0.18 * sg, 1.37, 0)
    JOINTS[side + "LowerArm"] = (0.18 * sg, 1.10, 0)
    JOINTS[side + "Hand"] = (0.18 * sg, 0.85, 0)
    JOINTS[side + "UpperLeg"] = (0.09 * sg, 0.88, 0)
    JOINTS[side + "LowerLeg"] = (0.09 * sg, 0.47, 0)
    JOINTS[side + "Foot"] = (0.09 * sg, 0.07, 0)
    JOINTS[side + "Toes"] = (0.09 * sg, 0.02, 0.11)
    PARENT.update({side + "Shoulder": "UpperChest", side + "UpperArm": side + "Shoulder", side + "LowerArm": side + "UpperArm",
                   side + "Hand": side + "LowerArm", side + "UpperLeg": "Hips", side + "LowerLeg": side + "UpperLeg",
                   side + "Foot": side + "LowerLeg", side + "Toes": side + "Foot"})
HEAD = JOINTS["Head"]
for s, sg in (("L", 1), ("R", -1)):
    JOINTS["Eye" + s] = (0.052 * sg, HEAD[1] + 0.165, 0.098)
    JOINTS["Lid" + s] = (0.052 * sg, HEAD[1] + 0.165, 0.098)
    JOINTS["Brow" + s] = (0.056 * sg, HEAD[1] + 0.228, 0.112)
    PARENT.update({"Eye" + s: "Head", "Lid" + s: "Head", "Brow" + s: "Head"})
JOINTS["Mouth"] = (0, HEAD[1] + 0.062, 0.118)
JOINTS["MouthL"] = (0.022, HEAD[1] + 0.062, 0.116)
JOINTS["MouthR"] = (-0.022, HEAD[1] + 0.062, 0.116)
PARENT.update({"Mouth": "Head", "MouthL": "Mouth", "MouthR": "Mouth"})
BONE_ORDER = ["Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
              "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
              "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
              "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
              "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
              "EyeL", "EyeR", "LidL", "LidR", "BrowL", "BrowR", "Mouth", "MouthL", "MouthR"]

# --------------------------------------------------------------------------- final proportions
# Every part is modelled around JOINTS (the "build space" above) and then re-proportioned
# to NEW_JOINTS through its own skin weights (reproportion()): short legs, long torso,
# big round head, thick neck, chunky feet - the stylized look of the reference sheets.
# NEW_JOINTS must stay identical to HumanoidDef.bone_list({}) in the game.
NEW_JOINTS = {
    "Root": (0, 0, 0), "Hips": (0, 0.77, 0), "Spine": (0, 0.89, 0), "Chest": (0, 1.03, 0),
    "UpperChest": (0, 1.19, 0), "Neck": (0, 1.33, 0), "Head": (0, 1.385, 0),
}
for side, sg in (("Left", 1), ("Right", -1)):
    NEW_JOINTS[side + "Shoulder"] = (0.04 * sg, 1.31, 0)
    NEW_JOINTS[side + "UpperArm"] = (0.155 * sg, 1.265, 0)
    NEW_JOINTS[side + "LowerArm"] = (0.155 * sg, 0.99, 0)
    NEW_JOINTS[side + "Hand"] = (0.155 * sg, 0.76, 0)
    NEW_JOINTS[side + "UpperLeg"] = (0.084 * sg, 0.71, 0)
    NEW_JOINTS[side + "LowerLeg"] = (0.084 * sg, 0.40, 0)
    NEW_JOINTS[side + "Foot"] = (0.084 * sg, 0.08, 0)
    NEW_JOINTS[side + "Toes"] = (0.084 * sg, 0.025, 0.13)
HEAD_SCALE = (1.12, 1.06, 1.06)     # head width / height / depth (Godot axes) - bigger, wider skull
EYE_PUSH = 0.008                    # eyes sit a little further out of the face
BROW_SCALE = (1.3, 1.6, 1.0)        # longer, thicker brows (Godot axes)
EYE_SCALE = 0.95                    # eyeball size vs the build mesh (lids and lower lids follow)
# Thickness across each bone (1 = unchanged), as (width, height, depth) in Godot axes,
# and tips for the end bones (build -> final).
BONE_K = {"Neck": (1.25, 1.25, 1.3), "Hips": (1.08, 1.0, 1.06), "Spine": (1.04, 1.0, 1.1), "Chest": (1.08, 1.0, 1.12),
          "UpperChest": (1.08, 1.0, 1.08)}
for side in ("Left", "Right"):
    BONE_K.update({side + "UpperArm": (1.38, 1.38, 1.38), side + "LowerArm": (1.42, 1.42, 1.42),
                   side + "UpperLeg": (1.06, 1.0, 1.0),
                   side + "Hand": (1.45, 1.45, 1.45), side + "Foot": (1.72, 1.14, 1.14), side + "Toes": (1.72, 1.14, 1.14)})
TIPS = {}
for side, sg in (("Left", 1), ("Right", -1)):
    TIPS[side + "Hand"] = ((0.18 * sg, 0.70, 0), (0.155 * sg, 0.61, 0))
    TIPS[side + "Toes"] = ((0.09 * sg, 0.02, 0.18), (0.084 * sg, 0.025, 0.215))
CHILD = {"Hips": "Spine", "Spine": "Chest", "Chest": "UpperChest", "UpperChest": "Neck", "Neck": "Head"}
for side in ("Left", "Right"):
    CHILD.update({side + "Shoulder": side + "UpperArm", side + "UpperArm": side + "LowerArm", side + "LowerArm": side + "Hand",
                  side + "UpperLeg": side + "LowerLeg", side + "LowerLeg": side + "Foot", side + "Foot": side + "Toes"})


def _head_map():
    h, H = G(*JOINTS["Head"]), G(*NEW_JOINTS["Head"])
    S = Matrix.Diagonal((HEAD_SCALE[0], HEAD_SCALE[2], HEAD_SCALE[1], 1.0))   # Blender x, y(depth), z(up)
    return Matrix.Translation(H) @ S @ Matrix.Translation(-h)


def bone_maps():
    """Affine map (Blender space) per bone: build-space segment -> final segment."""
    maps = {"Root": Matrix.Identity(4)}
    for b in BONE_ORDER:
        if b in maps:
            continue
        if b in CHILD or b in TIPS:
            h, t = (G(*JOINTS[b]), G(*JOINTS[CHILD[b]])) if b in CHILD else (G(*JOINTS[b]), G(*TIPS[b][0]))
            H, T = (G(*NEW_JOINTS[b]), G(*NEW_JOINTS[CHILD[b]])) if b in CHILD else (G(*NEW_JOINTS[b]), G(*TIPS[b][1]))
            u = (t - h).normalized()
            u2 = (T - H).normalized()
            s = (T - H).length / (t - h).length
            kx, ky, kz = BONE_K.get(b, (1.0, 1.0, 1.0))
            K = Matrix.Diagonal((kx, kz, ky))            # Godot (w, h, d) -> Blender (x, y=depth, z=up)
            outer = Matrix(((u.x * u.x, u.x * u.y, u.x * u.z), (u.y * u.x, u.y * u.y, u.y * u.z), (u.z * u.x, u.z * u.y, u.z * u.z)))
            A = outer * s + K @ (Matrix.Identity(3) - outer)
            R = u.rotation_difference(u2).to_matrix()
            maps[b] = Matrix.Translation(H) @ (R @ A).to_4x4() @ Matrix.Translation(-h)
    hm = _head_map()
    maps["Head"] = hm
    push = Matrix.Translation(G(0, 0, EYE_PUSH))
    for s_ in ("L", "R"):
        e = G(*JOINTS["Eye" + s_])
        maps["Eye" + s_] = push @ Matrix.Translation(hm @ e) @ Matrix.Scale(EYE_SCALE, 4) @ Matrix.Translation(-e)
        maps["Lid" + s_] = maps["Eye" + s_]
        b = G(*JOINTS["Brow" + s_])
        maps["Brow" + s_] = Matrix.Translation(hm @ b + G(0, 0, -0.008)) @ Matrix.Diagonal((BROW_SCALE[0], BROW_SCALE[2], BROW_SCALE[1], 1.0)) @ Matrix.Translation(-b)
    for m in ("Mouth", "MouthL", "MouthR"):
        p = G(*JOINTS[m])
        maps[m] = Matrix.Translation(hm @ p - p + G(0, 0, -0.003))
    maps["_HeadFace"] = push @ hm         # glasses: follow the head, stay in front of the eyes
    return maps


def final_joint(name):
    """Final (game) position of a joint, Godot coordinates."""
    if name in NEW_JOINTS:
        return NEW_JOINTS[name]
    v = bone_maps()[name] @ G(*JOINTS[name])
    return (v.x, v.z, -v.y)


# Objects whose rigid weight is "Head" but that must follow the eyeballs.
MAP_OVERRIDE = {"LowerLid_L": "EyeL", "LowerLid_R": "EyeR"}


def reproportion(ob, maps):
    """Moves every vertex (and every shape key) from build space to the final proportions
    by blending the per-bone affine maps with the vertex's own skin weights."""
    me = ob.data
    names = {g.index: g.name for g in ob.vertex_groups}
    base = ob.name.replace("_LOD1", "")
    forced = MAP_OVERRIDE.get(base) or ("_HeadFace" if base.startswith("Glasses") else None)
    per_vertex = []
    for v in me.vertices:
        if forced:
            per_vertex.append(maps[forced])
            continue
        ws = [(names[g.group], g.weight) for g in v.groups if g.weight > 0.0001 and names.get(g.group) in maps]
        tot = sum(w for _, w in ws)
        if tot <= 0:
            per_vertex.append(Matrix.Identity(4))
            continue
        M = Matrix(((0, 0, 0, 0), (0, 0, 0, 0), (0, 0, 0, 0), (0, 0, 0, 0)))
        for n_, w in ws:
            M = M + maps[n_] * (w / tot)
        per_vertex.append(M)
    if me.shape_keys:
        for kb in me.shape_keys.key_blocks:
            for i, d in enumerate(kb.data):
                d.co = per_vertex[i] @ d.co
        basis = me.shape_keys.key_blocks[0].data
        for i, v in enumerate(me.vertices):
            v.co = basis[i].co.copy()
    else:
        for i, v in enumerate(me.vertices):
            v.co = per_vertex[i] @ v.co
    me.update()


HEAD_C = G(0, HEAD[1] + 0.15, 0.005)            # centre of the head ellipsoid
HEAD_R = Vector((0.118, 0.125, 0.168))          # x width, y depth, z height (Blender)
JAW = 0.97


# --------------------------------------------------------------------------- scene utils
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def link(ob, coll=None):
    (coll or bpy.context.scene.collection).objects.link(ob)
    return ob


def collection(name):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    return c


def activate(ob):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)


def apply_modifiers(ob):
    activate(ob)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def material(name, color, rough=0.6):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    return m


def set_mat(ob, mat):
    ob.data.materials.clear()
    ob.data.materials.append(mat)


def mesh_object(name, verts, faces, coll):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    return link(bpy.data.objects.new(name, me), coll)


def join(objs, name):
    activate(objs[0])
    for o in objs[1:]:
        o.select_set(True)
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def smooth(ob):
    for p in ob.data.polygons:
        p.use_smooth = True


def ellipsoid(name, center, radii, coll, segs=16, rings=10, rot=None, lat=(-90, 90), lon=(-180, 180)):
    """Lat/long ellipsoid patch (lon 0 = front -Y, +90 = +X). Closed if full range."""
    verts, faces = [], []
    la0, la1 = lat
    lo0, lo1 = lon
    full_lon = (lo1 - lo0) >= 359.9
    ncol = segs if full_lon else segs + 1
    for j in range(rings + 1):
        la = math.radians(lerp(la0, la1, j / rings))
        for i in range(ncol):
            lo = math.radians(lerp(lo0, lo1, i / segs))
            p = Vector((math.cos(la) * math.sin(lo) * radii[0], -math.cos(la) * math.cos(lo) * radii[1], math.sin(la) * radii[2]))
            if rot is not None:
                p = rot @ p
            verts.append(center + p)
    for j in range(rings):
        for i in range(segs):
            i1 = (i + 1) % ncol if full_lon else i + 1
            faces.append((j * ncol + i, j * ncol + i1, (j + 1) * ncol + i1, (j + 1) * ncol + i))
    ob = mesh_object(name, verts, faces, coll)
    activate(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0001)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    smooth(ob)
    return ob


def prim(kind, name, coll, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), **kw):
    if kind == "cube":
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    elif kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=kw.get("verts", 16), radius=1.0, depth=1.0, location=loc, rotation=rot)
    elif kind == "cone":
        bpy.ops.mesh.primitive_cone_add(vertices=kw.get("verts", 16), radius1=kw.get("r1", 1.0), radius2=kw.get("r2", 0.0), depth=1.0, location=loc, rotation=rot)
    elif kind == "torus":
        bpy.ops.mesh.primitive_torus_add(major_radius=kw.get("R", 1.0), minor_radius=kw.get("r", 0.1), major_segments=kw.get("maj", 24), minor_segments=kw.get("mnr", 8), location=loc, rotation=rot)
    elif kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=kw.get("segs", 16), ring_count=kw.get("rings", 10), radius=1.0, location=loc, rotation=rot)
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.scale = scale
    if coll is not None:
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        coll.objects.link(ob)
    activate(ob)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if kw.get("bevel"):
        m = ob.modifiers.new("Bevel", "BEVEL")
        m.width = kw["bevel"]
        m.segments = 2
        apply_modifiers(ob)
    if kw.get("sub"):
        m = ob.modifiers.new("Sub", "SUBSURF")
        m.levels = kw["sub"]
        apply_modifiers(ob)
    if kw.get("smooth", True):
        smooth(ob)
    return ob


def head_fullness(uz):
    """Superellipse skull: broad U-shaped jaw (n=2.8) and a fuller, squarer cranium (n=2.4)."""
    n = 2.8 if uz < 0.0 else 2.4
    a = min(abs(uz), 0.9999)
    return min(1.6, (1.0 - a ** n) ** (1.0 / n) / math.sqrt(1.0 - a * a))


def head_point(lon, lat, s=1.0):
    """Point on the (tapered) head surface; lon 0 = front, lat 90 = top."""
    la, lo = math.radians(lat), math.radians(lon)
    u = Vector((math.cos(la) * math.sin(lo), -math.cos(la) * math.cos(lo), math.sin(la)))
    taper = lerp(JAW, 1.0, smoothstep(-0.95, 0.25, u.z)) * head_fullness(u.z)
    zt = lerp(0.9, 1.0, smoothstep(-0.95, 0.2, u.z)) * lerp(1.0, head_fullness(u.z), 0.6)
    return HEAD_C + Vector((u.x * HEAD_R.x * taper * s, u.y * HEAD_R.y * zt * s, u.z * HEAD_R.z * s))


# --------------------------------------------------------------------------- body
def body_graph(variant):
    """Skin-modifier graph: node -> (godot pos, radius) ; variants keep topology."""
    n = {}
    e = []
    v = variant

    def node(name, p, r):
        n[name] = [list(p), list(r)]

    def chain(*names):
        for a, b in zip(names, names[1:]):
            e.append((a, b))

    # Base proportions (slim stylized adult)
    node("pelvis", (0, 0.90, 0), (0.122, 0.092))
    node("hip", (0, 0.97, 0), (0.135, 0.100))
    node("waist", (0, 1.08, 0), (0.12, 0.092))
    node("chest", (0, 1.22, 0), (0.138, 0.10))
    node("upper", (0, 1.33, 0), (0.134, 0.092))
    node("nbase", (0, 1.415, 0), (0.09, 0.074))
    node("neck", (0, 1.49, 0), (0.07, 0.066))
    node("headb", (0, 1.59, 0), (0.066, 0.062))
    chain("pelvis", "hip", "waist", "chest", "upper", "nbase", "neck", "headb")
    for s, sg in (("L", 1), ("R", -1)):
        node("sh" + s, (0.125 * sg, 1.335, 0), (0.056, 0.054))      # sloping shoulders
        node("ua" + s, (0.18 * sg, 1.305, 0), (0.046, 0.044))
        node("el" + s, (0.18 * sg, 1.10, 0), (0.033, 0.033))
        node("fa" + s, (0.18 * sg, 1.0, 0.0), (0.035, 0.033))
        node("wr" + s, (0.18 * sg, 0.86, 0), (0.025, 0.023))
        node("pa" + s, (0.182 * sg, 0.80, 0.0), (0.017, 0.031))
        chain("upper", "sh" + s, "ua" + s, "el" + s, "fa" + s, "wr" + s, "pa" + s)
        # four fingers (curled slightly forward) + thumb
        for k, (fz, ln, rr) in enumerate(((0.021, 0.068, 0.0118), (0.007, 0.075, 0.0124), (-0.007, 0.071, 0.0121), (-0.02, 0.056, 0.011))):
            b0 = "fb%d%s" % (k, s)
            b1 = "fm%d%s" % (k, s)
            b2 = "ft%d%s" % (k, s)
            node(b0, (0.182 * sg, 0.778, fz), (rr, rr))
            node(b1, (0.181 * sg, 0.778 - ln * 0.5, fz + 0.004), (rr * 0.95, rr * 0.95))
            node(b2, (0.178 * sg, 0.778 - ln, fz + 0.011), (rr * 0.8, rr * 0.8))
            chain("pa" + s, b0, b1, b2)
        node("th" + s, (0.17 * sg, 0.83, 0.03), (0.014, 0.014))
        node("tt" + s, (0.164 * sg, 0.79, 0.046), (0.012, 0.012))
        e.append(("wr" + s, "th" + s))
        e.append(("th" + s, "tt" + s))
        node("hj" + s, (0.09 * sg, 0.86, 0), (0.068, 0.068))
        node("kn" + s, (0.09 * sg, 0.47, 0), (0.046, 0.046))
        node("ca" + s, (0.09 * sg, 0.36, 0), (0.049, 0.051))
        node("an" + s, (0.09 * sg, 0.085, 0), (0.033, 0.033))
        node("ba" + s, (0.09 * sg, 0.035, 0.095), (0.04, 0.026))
        node("to" + s, (0.09 * sg, 0.035, 0.145), (0.033, 0.024))
        chain("pelvis", "hj" + s, "kn" + s, "ca" + s, "an" + s, "ba" + s, "to" + s)

    def scale(names, fx, fy=None):
        for k in names:
            n[k][1][0] *= fx
            n[k][1][1] *= fy if fy is not None else fx

    arms = [k for k in n if k[:2] in ("ua", "el", "fa", "sh")]
    legs = [k for k in n if k[:2] in ("hj", "kn", "ca")]
    if v == "Heavy":
        scale(["waist"], 1.62, 2.3)
        scale(["hip"], 1.42, 1.75)
        scale(["chest"], 1.28, 1.42)
        scale(["upper", "pelvis"], 1.16, 1.2)
        scale(["nbase", "neck"], 1.3)
        scale(arms, 1.36)
        scale(legs, 1.32)
    elif v == "Thin":
        scale(["waist", "hip", "chest", "pelvis"], 0.84)
        scale(["upper"], 0.9)
        scale(arms, 0.8)
        scale(legs, 0.8)
    elif v == "Muscular":
        scale(["chest"], 1.24, 1.26)
        scale(["upper"], 1.3, 1.2)
        scale(["waist"], 1.05, 1.0)
        scale(["nbase", "neck"], 1.35)
        scale([k for k in arms if k[:2] in ("ua", "sh")], 1.5)
        scale([k for k in arms if k[:2] in ("fa",)], 1.3)
        scale(legs, 1.2)
    elif v == "Female":
        scale(["upper"], 0.9)
        scale(["waist"], 0.84)
        scale(["hip", "pelvis"], 1.18, 1.1)
        scale(["chest"], 0.98, 1.26)
        scale(arms, 0.9)
        for s in ("L", "R"):
            n["sh" + s][0][0] *= 0.94
    return n, e


def build_body(coll):
    nodes, edges = body_graph("Base")
    names = list(nodes)
    me = bpy.data.meshes.new("Body")
    me.from_pydata([G(*nodes[k][0]) for k in names], [(names.index(a), names.index(b)) for a, b in edges], [])
    body = link(bpy.data.objects.new("Body", me), coll)
    body.modifiers.new("Skin", "SKIN")
    for i, k in enumerate(names):
        me.skin_vertices[0].data[i].radius = nodes[k][1]
    me.skin_vertices[0].data[names.index("pelvis")].use_root = True
    sub = body.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1          # game resolution; add a Subdivision modifier in Blender for close-ups
    apply_modifiers(body)
    # Polygon budget: the five-finger hands are over half of the subdivided body, so they
    # are decimated on their own (vertex-group weighted); LOD1 then reduces everything.
    cls = classify_body(body, nodes, edges)
    hand_v = [i for i in range(len(body.data.vertices)) if region_of(cls[i][0]) == "hand"]
    hand_f = sum(1 for p in body.data.polygons if all(region_of(cls[v][0]) == "hand" for v in p.vertices))
    total_f = len(body.data.polygons)
    vg = body.vertex_groups.new(name="_HandDecimate")
    vg.add(hand_v, 1.0, "REPLACE")
    dec = body.modifiers.new("HandDec", "DECIMATE")
    dec.ratio = (total_f - hand_f + hand_f * (0.42 if LOD == 0 else 0.12)) / total_f
    dec.vertex_group = vg.name
    dec.vertex_group_factor = 10.0
    apply_modifiers(body)
    body.vertex_groups.remove(body.vertex_groups["_HandDecimate"])
    if LOD > 0:
        dec = body.modifiers.new("Dec", "DECIMATE")
        dec.ratio = 0.5
        apply_modifiers(body)
    smooth(body)
    return body, nodes, edges


def add_body_shape_keys(body, nodes, edges, cls):
    """Body-type shape keys made by re-scaling every vertex around its skeleton segment
    (same topology), then smoothing the displacement so junctions stay seamless."""
    me = body.data
    body.shape_key_add(name="Basis", from_mix=False)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    neighbours = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
    bm.free()
    torso = {"pelvis", "hip", "waist", "chest", "upper", "nbase", "neck", "headb"}
    for variant in ("Female", "Heavy", "Thin", "Muscular"):
        vn, _ = body_graph(variant)
        disp = []
        for i, v in enumerate(me.vertices):
            seg, t = cls[i]
            a, b = seg.split("-")
            cb = G(*nodes[a][0]).lerp(G(*nodes[b][0]), t)
            cv = G(*vn[a][0]).lerp(G(*vn[b][0]), t)
            rb = (lerp(nodes[a][1][0], nodes[b][1][0], t), lerp(nodes[a][1][1], nodes[b][1][1], t))
            rv = (lerp(vn[a][1][0], vn[b][1][0], t), lerp(vn[a][1][1], vn[b][1][1], t))
            o = v.co - cb
            if a in torso and b in torso:
                o2 = Vector((o.x * rv[0] / rb[0], o.y * rv[1] / rb[1], o.z))
            else:
                k = ((rv[0] / rb[0]) + (rv[1] / rb[1])) * 0.5
                axis = (G(*nodes[b][0]) - G(*nodes[a][0])).normalized()
                along = axis * o.dot(axis)
                o2 = along + (o - along) * k
            disp.append(cv + o2 - v.co)
        for _ in range(6):
            disp = [(disp[i] * 2.0 + sum((disp[j] for j in neighbours[i]), Vector()) / max(len(neighbours[i]), 1)) / 3.0 for i in range(len(disp))]
        kb = body.shape_key_add(name=variant, from_mix=False)
        for i, v in enumerate(me.vertices):
            kb.data[i].co = v.co + disp[i]


def box_uv(ob):
    """Simple box-projection UVs (a starting point for texture painting)."""
    me = ob.data
    layer = me.uv_layers[0] if len(me.uv_layers) else me.uv_layers.new(name="UVMap")
    uv = layer.data
    for p in me.polygons:
        n = p.normal
        ax = max(range(3), key=lambda k: abs(n[k]))
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                uv[li].uv = (co.y * 2.0 + 0.5, co.z * 0.5)
            elif ax == 1:
                uv[li].uv = (co.x * 2.0 + 0.5, co.z * 0.5)
            else:
                uv[li].uv = (co.x * 2.0 + 0.5, co.y * 2.0 + 0.5)


# --------------------------------------------------------------------------- weights
def classify_body(body, nodes, edges):
    """Nearest skin-graph segment (distance normalised by its radius) for each vertex."""
    segs = []
    for a, b in edges:
        pa, pb = G(*nodes[a][0]), G(*nodes[b][0])
        ra = (nodes[a][1][0] + nodes[a][1][1]) * 0.5
        rb = (nodes[b][1][0] + nodes[b][1][1]) * 0.5
        segs.append((a, b, pa, pb, ra, rb))
    out = []
    for v in body.data.vertices:
        best = None
        for a, b, pa, pb, ra, rb in segs:
            ab = pb - pa
            t = max(0.0, min(1.0, (v.co - pa).dot(ab) / max(ab.length_squared, 1e-9)))
            d = (v.co - (pa + ab * t)).length / max(lerp(ra, rb, t), 0.005)
            if best is None or d < best[0]:
                best = (d, a + "-" + b, t)
        out.append((best[1], best[2]))
    return fix_limb_islands(body, out, segs)


def limb_of(seg):
    """'armL' / 'armR' / 'legL' / 'legR' / 'torso' for a skin-graph segment."""
    b = seg.split("-")[1]
    if b[:2] in ("sh", "ua", "el", "fa", "wr", "pa", "fb", "fm", "ft", "th", "tt"):
        return "arm" + b[-1]
    if b[:2] in ("hj", "kn", "ca", "an", "ba", "to"):
        return "leg" + b[-1]
    return "torso"


def fix_limb_islands(body, cls, segs):
    """Nearest-segment classification can put fingertips on the thigh or the inner arm on
    the torso. Every limb label must form ONE connected patch: smaller islands are given
    to the label that surrounds them (nearest segment of that limb)."""
    me = body.data
    nv = len(me.vertices)
    adj = [[] for _ in range(nv)]
    for e in me.edges:
        a, b = e.vertices
        adj[a].append(b)
        adj[b].append(a)
    label = [limb_of(c[0]) for c in cls]
    for _ in range(4):
        seen = [False] * nv
        comps = []
        for i in range(nv):
            if seen[i]:
                continue
            stack, comp = [i], []
            seen[i] = True
            while stack:
                v = stack.pop()
                comp.append(v)
                for w in adj[v]:
                    if not seen[w] and label[w] == label[i]:
                        seen[w] = True
                        stack.append(w)
            comps.append((label[i], comp))
        biggest = {}
        for lab, comp in comps:
            if len(comp) > len(biggest.get(lab, [])):
                biggest[lab] = comp
        changed = 0
        for lab, comp in comps:
            if comp is biggest[lab]:
                continue
            inside = set(comp)
            votes = {}
            for v in comp:
                for w in adj[v]:
                    if w not in inside:
                        votes[label[w]] = votes.get(label[w], 0) + 1
            if not votes:
                continue
            new = max(votes, key=votes.get)
            for v in comp:
                co = me.vertices[v].co
                best = None
                for a, b_, pa, pb, ra, rb in segs:
                    if limb_of(a + "-" + b_) != new:
                        continue
                    ab = pb - pa
                    t = max(0.0, min(1.0, (co - pa).dot(ab) / max(ab.length_squared, 1e-9)))
                    d = (co - (pa + ab * t)).length / max(lerp(ra, rb, t), 0.005)
                    if best is None or d < best[0]:
                        best = (d, a + "-" + b_, t)
                if best:
                    cls[v] = (best[1], best[2])
                    label[v] = new
                    changed += 1
        if changed == 0:
            break
        print("LIMB islands fixed: %d vertices" % changed)
    return cls


def side_of(seg):
    return "Left" if seg.split("-")[-1].endswith("L") else "Right"


def body_weights(co, seg, t):
    """Joint-blended weights for one body vertex: {bone: weight}."""
    z = co.z  # Godot height
    a, b = seg.split("-")
    torso = {"pelvis", "hip", "waist", "chest", "upper", "nbase", "neck", "headb"}
    if a in torso and b in torso:
        levels = [(0.0, "Hips"), (1.04, "Spine"), (1.16, "Chest"), (1.28, "UpperChest"), (1.43, "Neck"), (1.535, "Head")]
        return chain_blend(z, levels, 0.035)
    sd = side_of(seg)
    if b.startswith("sh"):           # upper -> shoulder (clavicle)
        return {"UpperChest": 1.0 - t * 0.7, sd + "Shoulder": t * 0.7}
    if b.startswith("ua"):           # shoulder joint
        return {sd + "Shoulder": 1.0 - t * 0.6, sd + "UpperArm": t * 0.6}
    if b.startswith(("el", "fa", "wr", "pa", "fb", "fm", "ft", "th", "tt")):
        arm_z = [(9.0, sd + "UpperArm"), (1.10, sd + "LowerArm"), (0.85, sd + "Hand")]
        return chain_blend_down(z, arm_z, 0.03)
    if b.startswith("hj"):           # pelvis -> hip joint
        return {"Hips": 1.0 - t * 0.55, sd + "UpperLeg": t * 0.55}
    if b.startswith(("kn", "ca", "an", "ba", "to")):
        leg_z = [(9.0, sd + "UpperLeg"), (0.47, sd + "LowerLeg"), (0.07, sd + "Foot")]
        w = chain_blend_down(z, leg_z, 0.035)
        return w
    return {"Hips": 1.0}


def chain_blend(z, levels, blend):
    """levels ascending [(start_z, bone)], blends +-blend around each start."""
    idx = 0
    for i, (lz, _) in enumerate(levels):
        if z >= lz:
            idx = i
    bone = levels[idx][1]
    w = {bone: 1.0}
    if idx > 0 and z - levels[idx][0] < blend:
        f = 0.5 + 0.5 * (z - levels[idx][0]) / blend
        w = {bone: f, levels[idx - 1][1]: 1.0 - f}
    elif idx + 1 < len(levels) and levels[idx + 1][0] - z < blend:
        f = 0.5 + 0.5 * (levels[idx + 1][0] - z) / blend
        w = {bone: f, levels[idx + 1][1]: 1.0 - f}
    return w


def chain_blend_down(z, levels, blend):
    """levels descending [(above_z, bone_from_here_down)] e.g. upper arm, then lower arm below elbow z."""
    bone_i = 0
    for i, (lz, _) in enumerate(levels):
        if z <= lz:
            bone_i = i
    w = {levels[bone_i][1]: 1.0}
    if bone_i + 1 < len(levels) and z - levels[bone_i + 1][0] < blend:
        f = 0.5 + 0.5 * (z - levels[bone_i + 1][0]) / blend
        w = {levels[bone_i][1]: f, levels[bone_i + 1][1]: 1.0 - f}
    elif bone_i > 0 and levels[bone_i][0] - z < blend:
        f = 0.5 + 0.5 * (levels[bone_i][0] - z) / blend
        w = {levels[bone_i][1]: f, levels[bone_i - 1][1]: 1.0 - f}
    return w


def assign_weights(ob, weights_per_vertex):
    groups = {}
    for i, w in enumerate(weights_per_vertex):
        for bone, val in w.items():
            if val <= 0.0001:
                continue
            if bone not in groups:
                groups[bone] = ob.vertex_groups.get(bone) or ob.vertex_groups.new(name=bone)
            groups[bone].add([i], val, "REPLACE")


def rigid(ob, bone):
    assign_weights(ob, [{bone: 1.0}] * len(ob.data.vertices))


def rigid_by_side(ob, left_bone, right_bone):
    assign_weights(ob, [{left_bone if v.co.x > 0 else right_bone: 1.0} for v in ob.data.vertices])


# --------------------------------------------------------------------------- garments
def arm_s(seg, t):
    b = seg.split("-")[1]
    if b.startswith("ua"):
        return -0.05
    if b.startswith("el"):
        return t * 0.52
    if b.startswith("fa"):
        return 0.52 + t * 0.19
    if b.startswith("wr"):
        return 0.71 + t * 0.29
    return 1.2  # hand


def leg_s(seg, t):
    b = seg.split("-")[1]
    if b.startswith("hj"):
        return -0.05
    if b.startswith("kn"):
        return t * 0.5
    if b.startswith("ca"):
        return 0.5 + t * 0.14
    if b.startswith("an"):
        return 0.64 + t * 0.36
    return 1.2  # foot


def region_of(seg):
    a, b = seg.split("-")
    torso = {"pelvis", "hip", "waist", "chest", "upper", "nbase", "neck", "headb"}
    if a in torso and b in torso:
        return "neck" if b in ("neck", "headb") or (a == "upper" and b == "nbase" and False) else "torso"
    if b.startswith(("sh", "ua")):
        return "shoulder"
    if b.startswith(("el", "fa", "wr")):
        return "arm"
    if b.startswith(("pa", "fb", "fm", "ft", "th", "tt")):
        return "hand"
    if b.startswith("hj"):
        return "hipjoint"
    if b.startswith(("kn", "ca", "an")):
        return "leg"
    return "foot"


def garment(name, body, cls, coll, keep, offset):
    """Copy body faces where keep(co, seg, t) holds for every vertex, push along normals."""
    ob = body.copy()
    ob.data = body.data.copy()
    ob.name = name
    ob.data.name = name
    coll.objects.link(ob)
    me = ob.data
    keep_v = [keep(v.co, cls[i][0], cls[i][1]) for i, v in enumerate(me.vertices)]
    if LOD == 0 or not name.startswith(("Top_", "Pants_", "Jacket_Puffer", "Jacket_Vest", "Jacket_PoliceVest")):
        face_keep = [all(keep_v[v] for v in p.vertices) for p in me.polygons]
    else:
        # The decimated LOD body has irregular rings: keep faces that are mostly inside,
        # otherwise hems jump up a whole ring (e.g. trousers ending mid-shin).
        face_keep = [sum(1 for v in p.vertices if keep_v[v]) * 2 >= len(p.vertices) for p in me.polygons]
    if name in COVER_BITS:
        COVER[name] = face_keep
    used = set()
    for p in me.polygons:
        if face_keep[p.index]:
            used.update(p.vertices)
    normals = [v.normal.copy() for v in me.vertices]
    offs = [offset(v.co, cls[i][0], cls[i][1]) if i in used else 0.0 for i, v in enumerate(me.vertices)]
    for kb in me.shape_keys.key_blocks:
        for i in range(len(me.vertices)):
            kb.data[i].co = kb.data[i].co + normals[i] * offs[i]
    for i, v in enumerate(me.vertices):
        v.co = v.co + normals[i] * offs[i]
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    kill = [f for f in bm.faces if not face_keep[f.index]]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(me)
    bm.free()
    me.update()
    return ob


def build_garments(body, cls, coll):
    """All fitted clothing. Returns {name: object}."""
    def torso_top(co, seg, t, bottom=0.93, sleeve=0.3, neck_open=1.405):
        r = region_of(seg)
        if r == "torso" or r == "neck":          # crew necks reach up onto the neck base, dipping at the front
            return bottom <= co.z <= neck_open - 0.016 * smoothstep(0.0, 0.08, -co.y) - 0.3 * max(0.0, abs(co.x) - 0.045)
        if r == "shoulder":
            return co.z <= neck_open
        if r == "arm":
            return arm_s(seg, t) < sleeve
        return False

    def pants(co, seg, t, end=0.93, top=1.08):
        r = region_of(seg)
        if r == "torso":
            return co.z <= top
        if r == "hipjoint":
            return True
        if r == "leg":
            return leg_s(seg, t) < end
        return False

    out = {}
    hem = lambda co, base, extra, z0=0.93, z1=1.12: base + extra * (1.0 - smoothstep(z0, z1, co.z))
    boxy = lambda c, base, extra: base + extra * (1.0 - smoothstep(0.93, 1.32, c.z))     # loose, trapezoid shirt body
    out["Top_TShirt"] = garment("Top_TShirt", body, cls, coll, lambda c, s, t: torso_top(c, s, t, sleeve=0.4, neck_open=1.44),
                                lambda c, s, t: boxy(c, 0.03, 0.015) if region_of(s) in ("torso", "neck") else (0.02 + 0.016 * max(0.0, arm_s(s, t)) if region_of(s) == "arm" else 0.02))
    out["Top_LongSleeve"] = garment("Top_LongSleeve", body, cls, coll, lambda c, s, t: torso_top(c, s, t, sleeve=0.95),
                                    lambda c, s, t: hem(c, 0.010, 0.008) if region_of(s) == "torso" else 0.009)
    out["Top_ButtonShirt"] = garment("Top_ButtonShirt", body, cls, coll, lambda c, s, t: torso_top(c, s, t, sleeve=0.95, neck_open=1.415),
                                     lambda c, s, t: hem(c, 0.011, 0.01) if region_of(s) == "torso" else 0.011)
    out["Top_Polo"] = garment("Top_Polo", body, cls, coll, lambda c, s, t: torso_top(c, s, t, sleeve=0.36, neck_open=1.425),
                              lambda c, s, t: boxy(c, 0.016, 0.04) if region_of(s) == "torso" else (0.018 + 0.05 * max(0.0, arm_s(s, t)) if region_of(s) == "arm" else 0.018))
    out["Top_Tank"] = garment("Top_Tank", body, cls, coll,
                              lambda c, s, t: region_of(s) == "torso" and 0.975 <= c.z <= 1.39 and not (c.z > 1.3 and abs(c.x) > 0.075),
                              lambda c, s, t: hem(c, 0.008, 0.008))
    out["Top_Hoodie"] = garment("Top_Hoodie", body, cls, coll, lambda c, s, t: torso_top(c, s, t, bottom=0.94, sleeve=0.97),
                                lambda c, s, t: hem(c, 0.02, 0.012, 0.94, 1.1) if region_of(s) == "torso" else 0.017)
    out["Top_Sweater"] = garment("Top_Sweater", body, cls, coll, lambda c, s, t: torso_top(c, s, t, bottom=0.95, sleeve=0.97, neck_open=1.43),
                                 lambda c, s, t: hem(c, 0.016, 0.006, 0.95, 1.1) if region_of(s) == "torso" else 0.015)
    # Jackets (worn over a top)
    def jacket_keep(c, s, t, sleeves=True, gap=0.048, bottom=0.865):
        r = region_of(s)
        if r == "torso":
            if c.z < bottom or c.z > 1.43:
                return False
            return not (gap > 0 and abs(c.x) < gap + (c.z - 1.0) * 0.08 and c.y < -0.02)
        if r == "shoulder":
            return True
        if r == "arm":
            return sleeves and arm_s(s, t) < 0.96
        return False
    out["Jacket_Open"] = garment("Jacket_Open", body, cls, coll, lambda c, s, t: jacket_keep(c, s, t),
                                 lambda c, s, t: hem(c, 0.03, 0.012, 0.865, 1.05) if region_of(s) == "torso" else 0.024)
    out["Jacket_Blazer"] = garment("Jacket_Blazer", body, cls, coll, lambda c, s, t: jacket_keep(c, s, t, gap=0.03),
                                   lambda c, s, t: hem(c, 0.026, 0.008, 0.865, 1.05) if region_of(s) == "torso" else 0.02)
    out["Jacket_Vest"] = garment("Jacket_Vest", body, cls, coll, lambda c, s, t: region_of(s) == "torso" and 0.93 <= c.z <= 1.41 and not (c.z > 1.31 and abs(c.x) > 0.085),
                                 lambda c, s, t: hem(c, 0.024, 0.006, 0.93, 1.1))
    out["Jacket_PoliceVest"] = garment("Jacket_PoliceVest", body, cls, coll, lambda c, s, t: region_of(s) == "torso" and 0.95 <= c.z <= 1.405 and not (c.z > 1.3 and abs(c.x) > 0.09),
                                       lambda c, s, t: hem(c, 0.036, 0.004, 0.95, 1.1))
    out["Jacket_Puffer"] = garment("Jacket_Puffer", body, cls, coll, lambda c, s, t: jacket_keep(c, s, t, gap=0.0, bottom=0.9),
                                   lambda c, s, t: 0.045 if region_of(s) == "torso" else 0.036)
    # Legwear
    flare = lambda c, s, t, base, extra: base + (extra * leg_s(s, t) if region_of(s) == "leg" else 0.0)
    out["Pants_Long"] = garment("Pants_Long", body, cls, coll, lambda c, s, t: pants(c, s, t),
                                lambda c, s, t: flare(c, s, t, 0.016, 0.022))
    out["Pants_Shorts"] = garment("Pants_Shorts", body, cls, coll, lambda c, s, t: pants(c, s, t, end=0.36),
                                  lambda c, s, t: flare(c, s, t, 0.014, 0.03))
    out["Pants_Cargo"] = garment("Pants_Cargo", body, cls, coll, lambda c, s, t: pants(c, s, t),
                                 lambda c, s, t: flare(c, s, t, 0.018, 0.024))
    out["Socks"] = garment("Socks", body, cls, coll, lambda c, s, t: region_of(s) == "leg" and leg_s(s, t) > 0.8,
                           lambda c, s, t: 0.004)
    out["Belt"] = garment("Belt", body, cls, coll, lambda c, s, t: region_of(s) == "torso" and 0.955 <= c.z <= 1.04,
                          lambda c, s, t: 0.02)
    return out


# --------------------------------------------------------------------------- head & face
def build_head(coll):
    ob = ellipsoid("HeadBase", Vector((0, 0, 0)), Vector((1, 1, 1)), coll, segs=28 if LOD == 0 else 16, rings=20 if LOD == 0 else 11)
    base = [v.co.copy() for v in ob.data.vertices]

    def shape(u, jaw=JAW, w=1.0, h=1.0):
        taper = lerp(jaw, 1.0, smoothstep(-0.95, 0.25, u.z)) * head_fullness(u.z)
        zt = lerp(0.9, 1.0, smoothstep(-0.95, 0.2, u.z)) * lerp(1.0, head_fullness(u.z), 0.6)
        chin = 0.012 * smoothstep(-0.55, -0.95, u.z) * max(0.0, -u.y)   # chin pokes forward a bit
        return HEAD_C + Vector((u.x * HEAD_R.x * taper * w, u.y * HEAD_R.y * zt - chin, u.z * HEAD_R.z * h))

    for i, v in enumerate(ob.data.vertices):
        v.co = shape(base[i])
    ob.shape_key_add(name="Basis", from_mix=False)
    for name, kw in (("HeadWide", {"w": 1.15}), ("HeadLong", {"h": 1.15}), ("JawWide", {"jaw": 1.05}), ("JawNarrow", {"jaw": 0.68})):
        kb = ob.shape_key_add(name=name, from_mix=False)
        for i in range(len(base)):
            kb.data[i].co = shape(base[i], **kw)
    rigid(ob, "Head")
    # Ears (separate so they can be swapped/edited)
    ears = []
    for sg in (1, -1):
        e = ellipsoid("Ears" if sg > 0 else "EarR", head_point(90 * sg, -6, 0.93), Vector((0.017, 0.022, 0.031)), coll, 10, 6)
        ears.append(e)
    ear = join(ears, "Ears")
    rigid(ear, "Head")
    return ob, ear


def build_face(coll):
    parts = {}
    es = 1.0
    r = 0.05 * es
    for s in ("L", "R"):
        ep = G(*JOINTS["Eye" + s])
        parts["EyeWhite_" + s] = ellipsoid("EyeWhite_" + s, ep, Vector((r, r * 0.95, r)), coll, 16, 10)
        parts["Iris_" + s] = ellipsoid("Iris_" + s, ep + Vector((0, -r * 0.86, 0)), Vector((0.017, 0.008, 0.017)), coll, 12, 6)
        parts["Pupil_" + s] = ellipsoid("Pupil_" + s, ep + Vector((0, -r * 0.97, 0)), Vector((0.0095, 0.005, 0.0095)), coll, 10, 6)
        for p in ("EyeWhite_", "Iris_", "Pupil_"):
            rigid(parts[p + s], "Eye" + s)
        parts["Lid_" + s] = ellipsoid("Lid_" + s, ep, Vector((r * 1.07, r * 1.03, r * 1.07)), coll, 16, 6, lat=(0, 90))
        rigid(parts["Lid_" + s], "Lid" + s)
        parts["LowerLid_" + s] = ellipsoid("LowerLid_" + s, ep, Vector((r * 1.04, r * 1.02, r * 1.04)), coll, 16, 3, lat=(-90, -74))
        rigid(parts["LowerLid_" + s], "Head")
        sg = 1 if s == "L" else -1
        rot = Matrix.Rotation(math.radians(-16 * sg), 3, "Z")       # level
        parts["Brow_" + s] = ellipsoid("Brow_" + s, G(*JOINTS["Brow" + s]) + Vector((0, 0, 0.004)), Vector((0.03, 0.009, 0.0085)), coll, 12, 6, rot=rot)
        bc = sum((v.co for v in parts["Brow_" + s].data.vertices), Vector()) / len(parts["Brow_" + s].data.vertices)
        for v in parts["Brow_" + s].data.vertices:                    # bend into a soft arch
            d = (v.co.x - bc.x) / 0.03
            v.co.z += 0.007 * (1.0 - min(1.0, d * d))
        rigid(parts["Brow_" + s], "Brow" + s)
    mp = G(*JOINTS["Mouth"])
    parts["MouthCenter"] = ellipsoid("MouthCenter", mp, Vector((0.017, 0.006, 0.0042)), coll, 10, 6)
    rigid(parts["MouthCenter"], "Mouth")
    for s, sg in (("L", 1), ("R", -1)):
        c = G(*JOINTS["Mouth" + s]) + Vector((-0.003 * sg, 0, 0))
        parts["MouthCorner_" + s] = ellipsoid("MouthCorner_" + s, c, Vector((0.009, 0.0055, 0.0036)), coll, 8, 5)
        rigid(parts["MouthCorner_" + s], "Mouth" + s)
    # Noses
    np_ = head_point(0, -14, 0.995)
    noses = {"Nose_Round": (np_, Vector((0.012, 0.014, 0.012)), 0),
             "Nose_Long": (np_ + Vector((0, -0.004, -0.008)), Vector((0.013, 0.024, 0.027)), -20),
             "Nose_Button": (np_ + Vector((0, 0.004, -0.01)), Vector((0.012, 0.013, 0.011)), 0),
             "Nose_Wide": (np_, Vector((0.024, 0.016, 0.016)), 0)}
    for name, (p, rr, tilt) in noses.items():
        parts[name] = ellipsoid(name, p, rr, coll, 12, 8, rot=Matrix.Rotation(math.radians(tilt), 3, "X"))
        rigid(parts[name], "Head")
    return parts


# --------------------------------------------------------------------------- metaball hair & beards
def metaball_part(name, elements, coll, resolution=0.012, decimate=0.22, bone="Head"):
    mb = bpy.data.metaballs.new("MB" + name.replace("_", ""))
    mb.resolution = resolution
    mb.render_resolution = resolution
    mb.threshold = 0.6
    ob = link(bpy.data.objects.new("MB" + name.replace("_", ""), mb), coll)
    for el in elements:
        e = mb.elements.new(type=el.get("type", "BALL"))
        e.co = el["co"]
        e.radius = el["r"]
        e.stiffness = el.get("stiff", 2.0)
        if "size" in el:
            e.size_x, e.size_y, e.size_z = el["size"]
        if "rot" in el:
            e.rotation = el["rot"]
    activate(ob)
    bpy.ops.object.convert(target="MESH")
    mesh_ob = bpy.context.view_layer.objects.active
    mesh_ob.name = name
    mesh_ob.data.name = name
    if decimate < 1.0:
        d = mesh_ob.modifiers.new("Dec", "DECIMATE")
        d.ratio = decimate
        apply_modifiers(mesh_ob)
    smooth(mesh_ob)
    rigid(mesh_ob, bone)
    return mesh_ob


def scalp_cover(front=40, side=8, back=-28, step_lon=20, step_lat=14, s=0.97, r=0.05, top_r=0.06):
    els = []
    lat = -40
    while lat <= 90:
        lon = -180
        while lon < 180:
            a = abs(lon)
            limit = front if a < 60 else (side if a < 115 else back)
            if a >= 60 and a < 115:
                limit = lerp(front, side, smoothstep(60, 80, a)) if a < 80 else side
            if lat >= limit:
                els.append({"co": head_point(lon, lat, s), "r": r if lat < 75 else top_r})
            lon += step_lon if lat < 80 else 60
        lat += step_lat
    return els


def scalp_shell(name, head, coll, front, side, back, offset):
    """Close-cropped hair: the scalp faces of the head copied and pushed out along the
    normals (like the garments), so it keeps the head's shape keys and skin weights."""
    ob = head.copy()
    ob.data = head.data.copy()
    ob.name = name
    ob.data.name = name
    coll.objects.link(ob)
    me = ob.data
    keep = []
    for v in me.vertices:
        u = v.co - HEAD_C
        u = Vector((u.x / HEAD_R.x, u.y / HEAD_R.y, u.z / HEAD_R.z)).normalized()
        lat = math.degrees(math.asin(max(-1.0, min(1.0, u.z))))
        a = abs(math.degrees(math.atan2(u.x, -u.y)))
        if a < 60:
            limit = front
        elif a < 80:
            limit = lerp(front, side, smoothstep(60, 80, a))
        elif a < 115:
            limit = side
        else:
            limit = lerp(side, back, smoothstep(115, 140, a))
        keep.append(lat >= limit)
    normals = [v.normal.copy() for v in me.vertices]
    for kb in me.shape_keys.key_blocks:
        for i in range(len(me.vertices)):
            kb.data[i].co = kb.data[i].co + normals[i] * offset
    for i, v in enumerate(me.vertices):
        v.co = v.co + normals[i] * offset
    bm = bmesh.new()
    bm.from_mesh(me)
    kill = [f for f in bm.faces if not all(keep[v.index] for v in f.verts)]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(me)
    bm.free()
    me.update()
    return ob


def build_hair(coll, head):
    parts = {}
    # Short wavy cut (default style): close on the sides, forehead free, volume + waves on top
    import random
    rnd = random.Random(7)
    els = scalp_cover(front=48, side=14, back=-30, s=0.99, r=0.048, top_r=0.052)
    for k in range(34):
        lon = rnd.uniform(-165, 165)
        lat = rnd.uniform(46, 78)
        if abs(lon) < 45 and lat < 56:
            continue
        els.append({"co": head_point(lon, lat, 1.08 + rnd.uniform(0.0, 0.04)), "r": rnd.uniform(0.034, 0.046)})
    for sg in (1, -1):                          # square-ish top corners
        for lon in (55, 80, 105, 130):
            els.append({"co": head_point(lon * sg, 62 + rnd.uniform(-3, 3), 1.1), "r": 0.042})
    for lon in (-38, -20, -2, 16, 34):          # wavy front edge
        els.append({"co": head_point(lon, 58 + rnd.uniform(-2, 3), 1.08), "r": 0.036})
    parts["Hair_Short"] = metaball_part("Hair_Short", els, coll, decimate=0.42)
    parts["Hair_Buzz"] = scalp_shell("Hair_Buzz", head, coll, front=44, side=6, back=-30, offset=0.005)
    els = scalp_cover(front=44, side=12, back=-26, s=1.0, r=0.05)
    for k in range(9):
        lon = -64 + k * 16
        tip = head_point(lon, 80, 1.28)
        base = head_point(lon, 64, 1.0)
        mid = (tip + base) * 0.5
        d = (tip - base).normalized()
        q = Vector((1, 0, 0)).rotation_difference(d)
        els.append({"co": mid, "r": 0.03, "type": "CAPSULE", "size": ((tip - base).length * 0.5, 0, 0), "rot": q})
    parts["Hair_Spiky"] = metaball_part("Hair_Spiky", els, coll)
    els = []
    for lat in range(-20, 91, 18):
        for lon in range(-180, 180, 30):
            if abs(lon) < 70 and lat < 40:
                continue
            els.append({"co": head_point(lon, lat, 1.22), "r": 0.085})
    parts["Hair_Afro"] = metaball_part("Hair_Afro", els, coll, decimate=0.25)
    els = scalp_cover(front=36, side=-10, back=-40, s=0.99, r=0.05)
    for k in range(6):
        z = HEAD_C.z - 0.06 - k * 0.04
        for x in (-0.07, 0.0, 0.07):
            els.append({"co": Vector((x, HEAD_C.y + 0.09 + k * 0.006, z)), "r": 0.05})
    for sg in (1, -1):
        for k in range(4):
            els.append({"co": Vector((0.105 * sg, HEAD_C.y + 0.02, HEAD_C.z - 0.02 - k * 0.045)), "r": 0.04})
    parts["Hair_Long"] = metaball_part("Hair_Long", els, coll)
    els = scalp_cover(front=38, side=10, back=-26, s=1.0, r=0.052)
    els.append({"co": head_point(180, 22, 1.12), "r": 0.05})          # tie
    for k in range(7):
        els.append({"co": Vector((0, HEAD_C.y + 0.16 + k * 0.012, HEAD_C.z + 0.02 - k * 0.04)), "r": 0.056 - k * 0.004})
    parts["Hair_Ponytail"] = metaball_part("Hair_Ponytail", els, coll)
    els = scalp_cover(front=38, side=10, back=-26, s=1.0, r=0.052)
    els.append({"co": head_point(180, 55, 1.22), "r": 0.09})
    parts["Hair_Bun"] = metaball_part("Hair_Bun", els, coll)
    els = []
    for sg in (1, -1):
        for lat in (-6, 6, 18):
            for lon in (80, 100, 120, 140):
                els.append({"co": head_point(lon * sg, lat, 1.04), "r": 0.042})
    for lon in range(150, 211, 20):
        els.append({"co": head_point(lon, 0, 1.04), "r": 0.042})
    parts["Hair_SideTufts"] = metaball_part("Hair_SideTufts", els, coll)
    els = scalp_cover(front=44, side=12, back=-28, s=1.0, r=0.052)
    for lon in (-20, 0, 20):
        els.append({"co": head_point(lon, 62, 1.18), "r": 0.06})
    els.append({"co": head_point(0, 50, 1.22), "r": 0.055})
    parts["Hair_Quiff"] = metaball_part("Hair_Quiff", els, coll)
    els = []
    for lat in range(-34, 91, 14):
        for lon in range(-180, 180, 20):
            a = abs(lon)
            if a < 58 and lat < 34:
                continue
            els.append({"co": head_point(lon, lat, 1.04), "r": 0.055})
    parts["Hair_Bob"] = metaball_part("Hair_Bob", els, coll)
    # Facial hair
    mouth = G(*JOINTS["Mouth"])
    # chin tuft + thin moustache (two separate blobs, no ring around the mouth)
    els = [{"co": mouth + Vector((0, -0.008, -0.047)), "r": 0.03, "type": "ELLIPSOID", "size": (0.95, 0.75, 1.35)},
           {"co": mouth + Vector((0, -0.006, 0.015)), "r": 0.017, "type": "ELLIPSOID", "size": (2.3, 0.6, 0.55)}]
    parts["Beard_Goatee"] = metaball_part("Beard_Goatee", els, coll, resolution=0.006)
    els = []
    for lat in range(-80, -9, 12):
        for lon in range(-100, 101, 18):
            if lat > -38 and abs(lon) < 40:
                continue
            els.append({"co": head_point(lon, lat, 1.06), "r": 0.04})
    parts["Beard_Full"] = metaball_part("Beard_Full", els, coll)
    els = []
    for lon in range(-100, 101, 14):
        lat = lerp(-62, -16, smoothstep(30, 100, abs(lon)))
        els.append({"co": head_point(lon, lat, 1.07), "r": 0.026})
    parts["Beard_ChinStrap"] = metaball_part("Beard_ChinStrap", els, coll, resolution=0.007)
    parts["Beard_SoulPatch"] = metaball_part("Beard_SoulPatch", [{"co": mouth + Vector((0, 0.002, -0.022)), "r": 0.014}], coll, resolution=0.004, decimate=1.0)
    for name, rr, size in (("Mustache_Thin", 0.014, (2.6, 0.7, 0.5)), ("Mustache_Thick", 0.02, (2.2, 0.8, 0.7))):
        parts[name] = metaball_part(name, [{"co": mouth + Vector((0, -0.003, 0.015)), "r": rr, "type": "ELLIPSOID", "size": size}], coll, resolution=0.005, decimate=1.0)
    els = [{"co": mouth + Vector((0, -0.003, 0.015)), "r": 0.016, "type": "ELLIPSOID", "size": (2.3, 0.8, 0.6)}]
    for sg in (1, -1):
        els.append({"co": mouth + Vector((0.042 * sg, 0.0, 0.004)), "r": 0.009})
        els.append({"co": mouth + Vector((0.05 * sg, 0.0, -0.01)), "r": 0.008})
    parts["Mustache_Handlebar"] = metaball_part("Mustache_Handlebar", els, coll, resolution=0.005, decimate=1.0)
    return parts


# --------------------------------------------------------------------------- shoes
def skin_part(name, nodes, edges, coll, root, levels=2, flatten_z=None):
    names = list(nodes)
    me = bpy.data.meshes.new(name)
    me.from_pydata([nodes[k][0] for k in names], [(names.index(a), names.index(b)) for a, b in edges], [])
    ob = link(bpy.data.objects.new(name, me), coll)
    ob.modifiers.new("Skin", "SKIN")
    for i, k in enumerate(names):
        me.skin_vertices[0].data[i].radius = nodes[k][1]
    me.skin_vertices[0].data[names.index(root)].use_root = True
    sub = ob.modifiers.new("Sub", "SUBSURF")
    sub.levels = levels
    apply_modifiers(ob)
    if flatten_z is not None:
        for v in ob.data.vertices:
            if v.co.z < flatten_z:
                v.co.z = flatten_z
    smooth(ob)
    return ob


def sole_from_shoe(shoe, name, coll, height):
    """Sole = bottom slice of the shoe itself (bisected, capped, grown 6% sideways),
    so it follows the shoe outline instead of being a box."""
    so = shoe.copy()
    so.data = shoe.data.copy()
    so.name = name
    so.data.name = name
    coll.objects.link(so)
    bm = bmesh.new()
    bm.from_mesh(so.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, height), plane_no=(0, 0, 1), clear_outer=True)
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    for side in (1, -1):
        vs = [v for v in bm.verts if v.co.x * side > 0]
        if not vs:
            continue
        c = sum((v.co for v in vs), Vector()) / len(vs)
        for v in vs:
            v.co.x = c.x + (v.co.x - c.x) * 1.07
            v.co.y = c.y + (v.co.y - c.y) * 1.035
            v.co.z = max(0.0, v.co.z) - 0.001
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(so.data)
    bm.free()
    so.data.update()
    rigid_by_side(so, "LeftFoot", "RightFoot")
    return so


def build_shoes(coll):
    parts = {}
    styles = {
        "Shoes_Boots": {"shaft": 0.14, "rs": 0.066, "rh": (0.076, 0.08), "rb": (0.086, 0.074), "rt": (0.08, 0.066), "toe": 0.19, "h": 0.05, "sole": 0.024},
        "Shoes_Sneakers": {"shaft": 0.11, "rs": 0.058, "rh": (0.066, 0.064), "rb": (0.076, 0.05), "rt": (0.07, 0.046), "toe": 0.19, "h": 0.054, "sole": 0.026},
        "Shoes_Dress": {"shaft": 0.1, "rs": 0.048, "rh": (0.054, 0.054), "rb": (0.058, 0.036), "rt": (0.044, 0.03), "toe": 0.2, "h": 0.042, "sole": 0.014},
    }
    for name, st in styles.items():
        objs = []
        for sg in (1, -1):
            x = 0.09 * sg
            nodes = {"top": [G(x, st["shaft"], -0.005), (st["rs"], st["rs"])],
                     "heel": [G(x, 0.045, -0.025), st["rh"]],
                     "ball": [G(x, st["h"], 0.1), st["rb"]],
                     "toe": [G(x, st["h"] - 0.004, st["toe"]), st["rt"]]}
            o = skin_part(name + ("L" if sg > 0 else "R"), nodes, [("top", "heel"), ("heel", "ball"), ("ball", "toe")], coll, "top", flatten_z=0.0)
            objs.append(o)
        ob = join(objs, name)
        rigid_by_side(ob, "LeftFoot", "RightFoot")
        parts[name] = ob
        parts[name + "_Sole"] = sole_from_shoe(ob, name + "_Sole", coll, st["sole"])
    soles = []
    for sg in (1, -1):
        soles.append(prim("cube", "SandTmp", coll, loc=G(0.09 * sg, 0.01, 0.06), scale=(0.095, 0.27, 0.02), bevel=0.006))
        soles.append(prim("cube", "StrapTmp", coll, loc=G(0.09 * sg, 0.045, 0.1), scale=(0.09, 0.03, 0.06), bevel=0.01))
    sa = join(soles, "Shoes_Sandals")
    rigid_by_side(sa, "LeftFoot", "RightFoot")
    parts["Shoes_Sandals"] = sa
    return parts


# --------------------------------------------------------------------------- hats, glasses, accessories, details
def build_props(coll, body, cls):
    parts = {}
    # Hats
    cap = metaball_part("Hat_Cap", scalp_cover(front=22, side=6, back=4, s=1.04, r=0.055, top_r=0.06), coll)
    bill = prim("sphere", "BillTmp", coll, loc=head_point(0, 30, 1.02) + Vector((0, -0.07, -0.005)), scale=(0.1, 0.085, 0.012), segs=20, rings=8)
    parts["Hat_Cap"] = join([cap, bill], "Hat_Cap")
    rigid(parts["Hat_Cap"], "Head")
    beanie = metaball_part("Hat_Beanie", scalp_cover(front=30, side=2, back=-6, s=1.07, r=0.06, top_r=0.07), coll)
    rigid(beanie, "Head")
    parts["Hat_Beanie"] = beanie
    top = HEAD_C + Vector((0, 0, HEAD_R.z * 0.62))
    crown = prim("cyl", "CrownTmp", coll, loc=top + Vector((0, 0, 0.07)), scale=(0.112, 0.118, 0.13), verts=24, bevel=0.01)
    brim = prim("cyl", "BrimTmp", coll, loc=top, scale=(0.19, 0.19, 0.012), verts=32, bevel=0.004)
    band = prim("cyl", "BandTmp", coll, loc=top + Vector((0, 0, 0.025)), scale=(0.116, 0.122, 0.028), verts=24)
    parts["Hat_Brimmed"] = join([crown, brim, band], "Hat_Brimmed")
    rigid(parts["Hat_Brimmed"], "Head")
    bucket = prim("cone", "BucketTmp", coll, loc=top + Vector((0, 0, 0.06)), scale=(1, 1, 0.12), r1=0.13, r2=0.1, verts=24)
    bbrim = prim("cone", "BucketBrimTmp", coll, loc=top + Vector((0, 0, -0.005)), scale=(1, 1, 0.04), r1=0.18, r2=0.13, verts=24)
    parts["Hat_Bucket"] = join([bucket, bbrim], "Hat_Bucket")
    rigid(parts["Hat_Bucket"], "Head")
    pcap = metaball_part("Hat_PoliceCap", scalp_cover(front=22, side=6, back=4, s=1.05, r=0.056, top_r=0.062), coll)
    pbill = prim("sphere", "PBillTmp", coll, loc=head_point(0, 30, 1.02) + Vector((0, -0.07, -0.005)), scale=(0.1, 0.085, 0.012), segs=20, rings=8)
    parts["Hat_PoliceCap"] = join([pcap, pbill], "Hat_PoliceCap")
    rigid(parts["Hat_PoliceCap"], "Head")
    d = (head_point(0, 47, 1.0) - HEAD_C).normalized()
    hit, loc, nrm, _ = parts["Hat_PoliceCap"].ray_cast(HEAD_C + d * 0.4, -d)
    loc = loc if hit else head_point(0, 47, 1.25)
    nrm = nrm if hit else d
    badge = prim("sphere", "Detail_CapBadge", coll, loc=(0, 0, 0), scale=(0.022, 0.026, 0.005), segs=12, rings=6)
    rot = Vector((0, 0, 1)).rotation_difference(nrm).to_matrix().to_4x4()
    badge.data.transform(Matrix.Translation(loc + nrm * 0.002) @ rot)
    badge.data.update()
    parts["Detail_CapBadge"] = badge
    rigid(badge, "Head")
    # Glasses
    eyez = G(*JOINTS["EyeL"])
    face_y = eyez.y - 0.047 - 0.014
    rims = []
    for sg in (1, -1):
        c = Vector((0.052 * sg, face_y, eyez.z))
        rims.append(prim("torus", "RimTmp", coll, loc=c, rot=(math.radians(90), 0, 0), R=0.036, r=0.0035, maj=20, mnr=6))
        ear = Vector((HEAD_R.x * 0.96 * sg, HEAD_C.y + 0.0, eyez.z))
        st = Vector((0.088 * sg, face_y + 0.004, eyez.z))
        mid = (st + ear) * 0.5
        arm = prim("cube", "ArmTmp", coll, loc=mid, scale=(0.006, (ear - st).length, 0.006))
        arm.rotation_euler = (0, 0, math.atan2(-(ear.x - st.x), ear.y - st.y))
        rims.append(arm)
    rims.append(prim("cube", "BridgeTmp", coll, loc=Vector((0, face_y, eyez.z + 0.006)), scale=(0.035, 0.005, 0.005)))
    parts["Glasses_Round"] = join(rims, "Glasses_Round")
    rigid(parts["Glasses_Round"], "Head")
    sq = []
    for sg in (1, -1):
        c = Vector((0.052 * sg, face_y, eyez.z))
        for dz, sx, sz in ((0.03, 0.084, 0.006), (-0.03, 0.084, 0.006)):
            sq.append(prim("cube", "SqTmp", coll, loc=c + Vector((0, 0, dz)), scale=(sx, 0.006, sz)))
        for dx in (0.042, -0.042):
            sq.append(prim("cube", "SqTmp", coll, loc=c + Vector((dx, 0, 0)), scale=(0.006, 0.006, 0.066)))
    sq.append(prim("cube", "BridgeTmp", coll, loc=Vector((0, face_y, eyez.z + 0.01)), scale=(0.025, 0.005, 0.005)))
    parts["Glasses_Square"] = join(sq, "Glasses_Square")
    rigid(parts["Glasses_Square"], "Head")
    sun = []
    for sg in (1, -1):
        sun.append(prim("sphere", "LensTmp", coll, loc=Vector((0.052 * sg, face_y, eyez.z)), scale=(0.042, 0.006, 0.033), segs=16, rings=8))
    sun.append(prim("cube", "BridgeTmp", coll, loc=Vector((0, face_y, eyez.z + 0.01)), scale=(0.025, 0.005, 0.005)))
    parts["Glasses_Sun"] = join(sun, "Glasses_Sun")
    rigid(parts["Glasses_Sun"], "Head")
    # Accessories
    neck = G(*JOINTS["Neck"])
    parts["Acc_Necklace"] = prim("torus", "Acc_Necklace", coll, loc=neck + Vector((0, -0.012, -0.03)), rot=(math.radians(-18), 0, 0), R=0.058, r=0.004, maj=24, mnr=6)
    rigid(parts["Acc_Necklace"], "UpperChest")
    ers = [prim("sphere", "ErTmp", coll, loc=head_point(90 * sg, -26, 0.95), scale=(0.008, 0.008, 0.008), segs=8, rings=6) for sg in (1, -1)]
    parts["Acc_Earrings"] = join(ers, "Acc_Earrings")
    rigid(parts["Acc_Earrings"], "Head")
    sc = prim("torus", "ScarfTmp", coll, loc=neck + Vector((0, 0, 0.0)), R=0.062, r=0.03, maj=20, mnr=8)
    tail = prim("cube", "TailTmp", coll, loc=neck + Vector((0.05, -0.1, -0.12)), scale=(0.055, 0.02, 0.2), rot=(math.radians(-8), 0, math.radians(8)), bevel=0.008)
    parts["Acc_Scarf"] = join([sc, tail], "Acc_Scarf")
    rigid(parts["Acc_Scarf"], "UpperChest")
    hand = G(*JOINTS["LeftHand"])
    w1 = prim("cyl", "Watch", coll, loc=hand + Vector((0, 0, 0.03)), scale=(0.031, 0.029, 0.024), verts=16)
    w2 = prim("cube", "WFace", coll, loc=hand + Vector((0.03, 0, 0.03)), scale=(0.008, 0.024, 0.026))
    parts["Watch"] = join([w1, w2], "Watch")
    rigid(parts["Watch"], "LeftLowerArm")
    chest = G(*JOINTS["Chest"])
    bp = prim("cube", "Bag_Backpack", coll, loc=chest + Vector((0, 0.17, 0.07)), scale=(0.25, 0.11, 0.3), bevel=0.03)
    pocket = prim("cube", "PocketTmp", coll, loc=chest + Vector((0, 0.235, 0.0)), scale=(0.19, 0.03, 0.12), bevel=0.012)
    straps = [prim("cube", "StrapTmp", coll, loc=chest + Vector((0.075 * sg, -0.02, 0.15)), scale=(0.03, 0.24, 0.012), rot=(math.radians(-70), 0, 0)) for sg in (1, -1)]
    parts["Bag_Backpack"] = join([bp, pocket] + straps, "Bag_Backpack")
    rigid(parts["Bag_Backpack"], "Chest")
    hips = G(*JOINTS["Hips"])
    sb = prim("cube", "Bag_Shoulder", coll, loc=hips + Vector((-0.19, -0.02, 0.02)), scale=(0.06, 0.2, 0.16), bevel=0.015)
    strap = prim("cube", "SStrapTmp", coll, loc=chest + Vector((-0.02, -0.13, 0.07)), scale=(0.03, 0.01, 0.55), rot=(0, math.radians(38), 0))
    parts["Bag_Shoulder"] = join([sb, strap], "Bag_Shoulder")
    rigid(parts["Bag_Shoulder"], "Chest")
    # Clothing details (buttons, collars, buckle, pockets, hi-vis stripes, police text, hood)
    btn = []
    for k in range(5):
        z = 1.36 - k * 0.075
        btn.append(prim("sphere", "BtnTmp", coll, loc=surface_front(body, z) + Vector((0, -0.016, 0)), scale=(0.006, 0.003, 0.006), segs=8, rings=4))
    parts["Detail_Buttons"] = join(btn, "Detail_Buttons")
    rigid(parts["Detail_Buttons"], "Chest")
    col = []
    for sg in (1, -1):
        col.append(prim("cube", "ColTmp", coll, loc=G(0.036 * sg, 1.415, 0.055), scale=(0.055, 0.012, 0.035), rot=(math.radians(20), math.radians(-25 * sg), 0), bevel=0.004))
    parts["Detail_Collar"] = join(col, "Detail_Collar")
    rigid(parts["Detail_Collar"], "UpperChest")
    parts["Detail_Buckle"] = prim("cube", "Detail_Buckle", coll, loc=surface_front(body, 0.995) + Vector((0, -0.024, 0)), scale=(0.04, 0.008, 0.03), bevel=0.003)
    rigid(parts["Detail_Buckle"], "Hips")
    hood = metaball_part("Detail_Hood", [{"co": G(0, 1.43, -0.09), "r": 0.07, "type": "ELLIPSOID", "size": (1.6, 0.9, 0.8)}], coll, bone="UpperChest")
    parts["Detail_Hood"] = hood
    pk = prim("cube", "Detail_HoodiePocket", coll, loc=surface_front(body, 1.06) + Vector((0, -0.03, 0)), scale=(0.17, 0.012, 0.08), bevel=0.006)
    rigid(pk, "Spine")
    parts["Detail_HoodiePocket"] = pk
    cargo = []
    for sg in (1, -1):
        cargo.append(prim("cube", "CargoTmp", coll, loc=G(0.16 * sg, 0.69, 0.0), scale=(0.018, 0.085, 0.1), bevel=0.006))
    parts["Detail_CargoPockets"] = join(cargo, "Detail_CargoPockets")
    assign_weights(parts["Detail_CargoPockets"], [{"LeftUpperLeg" if v.co.x > 0 else "RightUpperLeg": 1.0} for v in parts["Detail_CargoPockets"].data.vertices])
    stripes = garment("Detail_HiVisStripes", body, cls, coll,
                      lambda c, s, t: region_of(s) == "torso" and ((1.02 <= c.z <= 1.1) or (1.17 <= c.z <= 1.25)) and not (c.z > 1.3),
                      lambda c, s, t: 0.03)
    parts["Detail_HiVisStripes"] = stripes
    pouches = []
    for k, x in enumerate((-0.07, 0.0, 0.07)):
        pouches.append(prim("cube", "PouchTmp", coll, loc=surface_front(body, 1.06) + Vector((x, -0.05, 0)), scale=(0.06, 0.03, 0.07), bevel=0.008))
    parts["Detail_Pouches"] = join(pouches, "Detail_Pouches")
    rigid(parts["Detail_Pouches"], "Spine")
    parts["Text_PoliceVest"] = text_part("Text_PoliceVest", "POLICE", surface_front(body, 1.24) + Vector((0, -0.056, 0)), 0.048, coll, "Chest")
    skirt = prim("cone", "Pants_Skirt", coll, loc=G(0, 0.8, 0), scale=(1, 1, 0.38), r1=0.25, r2=0.15, verts=24)
    rigid(skirt, "Hips")
    parts["Pants_Skirt"] = skirt
    return parts


def surface_front(body, z):
    best = None
    for v in body.data.vertices:
        if abs(v.co.z - z) < 0.02 and abs(v.co.x) < 0.02:
            if best is None or v.co.y < best.y:
                best = v.co.copy()
    return best if best is not None else Vector((0, -0.1, z))


def text_part(name, text, loc, size, coll, bone, tilt=0.0):
    cu = bpy.data.curves.new(name, type="FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.extrude = 0.002
    cu.resolution_u = 2
    ob = link(bpy.data.objects.new(name, cu), coll)
    ob.location = loc
    ob.rotation_euler = (math.radians(90 + tilt), 0, 0)
    activate(ob)
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    rigid(ob, bone)
    return ob


# --------------------------------------------------------------------------- armature & export
def build_armature(coll):
    arm_data = bpy.data.armatures.new("Armature")
    arm = link(bpy.data.objects.new("Armature", arm_data), coll)
    activate(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    children = {}
    for b, p in PARENT.items():
        children.setdefault(p, []).append(b)
    for name in BONE_ORDER:
        bone = eb.new(name)
        head = G(*final_joint(name))
        bone.head = head
        kids = [k for k in children.get(name, []) if not k.startswith(("Eye", "Lid", "Brow", "Mouth"))]
        main = None
        if name in ("Hips",):
            main = "Spine"
        elif kids:
            main = kids[0]
        if main and (G(*final_joint(main)) - head).length > 0.02:
            bone.tail = G(*final_joint(main))
        elif name in ("EyeL", "EyeR", "LidL", "LidR", "BrowL", "BrowR", "Mouth", "MouthL", "MouthR"):
            bone.tail = head + Vector((0, -0.025, 0))
        elif name == "Head":
            bone.tail = head + Vector((0, 0, 0.2))
        elif name.endswith("Hand"):
            bone.tail = head + Vector((0, 0, -0.12))
        elif name.endswith("Toes"):
            bone.tail = head + Vector((0, -0.05, 0))
        elif name == "Root":
            bone.tail = head + Vector((0, 0.15, 0))
        else:
            bone.tail = head + Vector((0, 0, 0.08))
    for name in BONE_ORDER:
        if name in PARENT:
            eb[name].parent = eb[PARENT[name]]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def bind(ob, arm):
    ob.parent = arm
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = arm


def cover_mask(body, cls):
    """Writes the garment-coverage bitmask into a second UV map of the body.
    A vertex gets a garment's bit only if EVERY face around it is covered by that garment,
    so any triangle whose 3 vertices share the bit lies fully under the garment."""
    me = body.data
    nv = len(me.vertices)
    keep = dict(COVER)
    foot = [region_of(cls[i][0]) == "foot" for i in range(nv)]
    keep["Shoes"] = [all(foot[v] for v in p.vertices) for p in me.polygons]
    face_ok = keep
    mask = [0] * nv
    blocked = {name: [False] * nv for name in keep}
    for p in me.polygons:
        for name in keep:
            if not face_ok[name][p.index]:
                for v in p.vertices:
                    blocked[name][v] = True
    for name, bit in COVER_BITS.items():
        if name not in keep:
            continue
        for v in range(nv):
            if not blocked[name][v]:
                mask[v] |= 1 << bit
    # Stored as a per-vertex float colour, 4 bits per channel (exported as COLOR_0;
    # the glTF exporter drops UV maps that no material uses).
    ca = me.color_attributes.new(name="CoverMask", type="FLOAT_COLOR", domain="POINT")
    for v in range(nv):
        m = mask[v]
        ca.data[v].color = ((m & 15) / 15.0, ((m >> 4) & 15) / 15.0, ((m >> 8) & 15) / 15.0, 1.0)
    me.color_attributes.active_color = ca
    covered = sum(1 for p in me.polygons if any(face_ok[n][p.index] for n in keep))
    print("COVER mask on %s: %d/%d faces coverable" % (body.name, covered, len(me.polygons)))
    if os.environ.get("WB_DEBUG_COVER"):
        reg = {}
        for p in me.polygons:
            r = region_of(cls[p.vertices[0]][0])
            tot, cov = reg.get(r, (0, 0))
            reg[r] = (tot + 1, cov + (1 if any(face_ok[n][p.index] for n in keep) else 0))
        print("COVER by region", reg)
        for n in keep:
            print("  ", n, sum(face_ok[n]))


def tris_of(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def build_set(lod):
    """Builds one complete part library at the given LOD. Returns (meshes, body, cls)."""
    global LOD
    LOD = lod
    COVER.clear()
    pre = "" if lod == 0 else "LOD%d_" % lod
    before = set(bpy.data.objects)
    cols = {n: collection(pre + n) for n in ("Body", "Face", "Hair", "FacialHair", "Tops", "Jackets", "Legwear", "Shoes", "Headwear", "Glasses", "Accessories", "Details")}
    body, nodes, edges = build_body(cols["Body"])
    cls = classify_body(body, nodes, edges)
    add_body_shape_keys(body, nodes, edges, cls)
    assign_weights(body, [body_weights(v.co, cls[i][0], cls[i][1]) for i, v in enumerate(body.data.vertices)])
    garments = build_garments(body, cls, cols["Tops"])
    # garments copied the body's vertex groups -> already skinned; sort into collections
    for name, ob in garments.items():
        if name.startswith("Jacket"):
            cols["Tops"].objects.unlink(ob)
            cols["Jackets"].objects.link(ob)
        elif name.startswith(("Pants", "Socks", "Belt")):
            cols["Tops"].objects.unlink(ob)
            cols["Legwear"].objects.link(ob)
    head, ears = build_head(cols["Body"])
    face = build_face(cols["Face"])
    hair = build_hair(cols["Hair"], head)
    for k in [k for k in hair if k.startswith(("Beard", "Mustache"))]:
        cols["Hair"].objects.unlink(hair[k])
        cols["FacialHair"].objects.link(hair[k])
    shoes = build_shoes(cols["Shoes"])
    props = build_props(cols["Accessories"], body, cls)
    for k, ob in props.items():
        dst = "Headwear" if k.startswith(("Hat", "Detail_CapBadge")) else ("Glasses" if k.startswith("Glasses") else ("Details" if k.startswith(("Detail", "Text_")) else ("Legwear" if k.startswith("Pants") else "Accessories")))
        if dst != "Accessories":
            for c in list(ob.users_collection):
                c.objects.unlink(ob)
            cols[dst].objects.link(ob)
    cover_mask(body, cls)
    meshes = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    maps = bone_maps()
    for o in meshes:
        reproportion(o, maps)
    # feet grew: put every shoe (and its sole, same offset) back on the ground
    for o in meshes:
        if o.name.startswith("Shoes_") and not o.name.endswith("_Sole"):
            dz = -min((o.matrix_world @ v.co).z for v in o.data.vertices)
            for t in [o] + [x for x in meshes if x.name == o.name + "_Sole"]:
                for v in t.data.vertices:
                    v.co.z += dz
                t.data.update()
    # Polygon budget: rigid parts (no shape keys) are decimated - capped at LOD0, reduced at LOD1.
    for o in list(meshes):
        if lod > 0 and o.name.startswith(LOD1_SKIP):
            meshes.remove(o)
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        if o.data.shape_keys is not None:
            continue
        t = tris_of(o)
        target = LOD0_MAX_TRIS if lod == 0 else max(48, min(LOD1_MAX_TRIS, int(t * LOD1_RATIO)))
        if t > target and t > 60:
            d = o.modifiers.new("Budget", "DECIMATE")
            d.ratio = target / t
            apply_modifiers(o)
    if lod > 0:
        for o in meshes:
            o.name = o.name + "_LOD%d" % lod
            o.data.name = o.name
    return meshes


def main():
    reset_scene()
    os.makedirs(SRC_DIR, exist_ok=True)
    os.makedirs(REN_DIR, exist_ok=True)
    rig = collection("Rig")
    # LOD1 first so the LOD0 objects get the clean names.
    lod1 = build_set(1)
    lod0 = build_set(0)
    arm = build_armature(rig)
    meshes = lod0 + lod1
    # Blender 5 creates shape keys with value 1.0: rest every key at 0 so the .blend opens
    # with the neutral body and the glTF default morph weights are 0.
    for o in meshes:
        if o.data.shape_keys:
            for kb in o.data.shape_keys.key_blocks[1:]:
                kb.value = 0.0
    for o in meshes:
        bind(o, arm)
        box_uv(o)
        set_mat(o, material("M_" + o.name, (0.6, 0.6, 0.62)))
    for c in bpy.data.collections:
        if c.name.startswith("LOD1_"):
            c.hide_render = True
            c.hide_viewport = True
    # report
    for label, group in (("LOD0", lod0), ("LOD1", lod1)):
        total = 0
        for o in sorted(group, key=lambda x: x.name):
            tris = tris_of(o)
            total += tris
            print("PART %-28s verts %5d tris %5d keys %d" % (o.name, len(o.data.vertices), tris, len(o.data.shape_keys.key_blocks) - 1 if o.data.shape_keys else 0))
        print(label, "PARTS", len(group), "TOTAL TRIS", total)
    blend = os.path.join(SRC_DIR, "westbridge_characters.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
    glb = os.path.join(OUT_DIR, "westbridge_characters.glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=False, export_skins=True,
                              export_morph=True, export_morph_normal=False, export_animations=False, export_yup=True,
                              export_apply=False, export_materials="EXPORT",
                              export_vertex_color="NAME", export_vertex_color_name="CoverMask",
                              export_all_vertex_colors=False, export_active_vertex_color_when_no_material=False)
    print("EXPORTED", glb, os.path.getsize(glb))
    if RENDER:
        import render_previews
        render_previews.render_all(REN_DIR, quick="--quick" in ARGS)
    if "--views" in ARGS:
        import render_previews
        render_previews.render_reference_views(REN_DIR)


if __name__ == "__main__":
    sys.path.insert(0, HERE)
    main()
