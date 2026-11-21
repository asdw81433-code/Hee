"""Studio preview renders of the WESTBRIDGE character library (Cycles, headless)."""
import bpy
import math
import os
from mathutils import Matrix, Vector


LID_REST_DEG = -20.0     # resting upper-lid angle (game: FaceRig closed 0.32 -> heavy lids)


def srgb(c):
    return tuple(pow(max(0.0, x), 2.2) for x in c)


SKIN_TONES = {"tan": (0.66, 0.47, 0.28), "light": (0.96, 0.8, 0.66), "brown": (0.62, 0.42, 0.28), "dark": (0.42, 0.27, 0.18), "pale": (0.98, 0.86, 0.74)}
FACE = ["HeadBase", "Ears", "EyeWhite_L", "EyeWhite_R", "Iris_L", "Iris_R", "Pupil_L", "Pupil_R", "Lid_L", "Lid_R",
        "LowerLid_L", "LowerLid_R", "Brow_L", "Brow_R", "MouthCenter", "MouthCorner_L", "MouthCorner_R"]

# Original outfits made from the modular library.
OUTFITS = {
    "casual": {"skin": "tan", "nose": "Nose_Round", "hair": ("Hair_Short", (0.24, 0.12, 0.01)),
               "parts": [("Top_TShirt", (0.13, 0.2, 0.42)), ("Pants_Long", (0.02, 0.04, 0.15)), ("Shoes_Boots", (0.28, 0.15, 0.06)), ("Shoes_Boots_Sole", (0.16, 0.09, 0.04))]},
    "gardener": {"skin": "light", "nose": "Nose_Long", "hair": None,
                 "parts": [("Top_ButtonShirt", (0.2, 0.72, 0.16)), ("Detail_Buttons", (0.08, 0.3, 0.06)), ("Detail_Collar", (0.22, 0.76, 0.18)),
                           ("Pants_Long", (0.2, 0.3, 0.55)), ("Shoes_Boots", (0.33, 0.2, 0.12)), ("Shoes_Boots_Sole", (0.18, 0.11, 0.07))]},
    "photographer": {"skin": "light", "nose": "Nose_Round", "hair": ("Hair_Buzz", (0.5, 0.48, 0.45)), "beard": ("Beard_Full", (0.55, 0.52, 0.48)),
                     "parts": [("Hat_Bucket", (0.62, 0.55, 0.38)), ("Glasses_Square", (0.12, 0.12, 0.12)), ("Top_TShirt", (0.9, 0.9, 0.88)),
                               ("Jacket_Open", (0.36, 0.4, 0.26)), ("Pants_Cargo", (0.58, 0.52, 0.36)), ("Detail_CargoPockets", (0.5, 0.45, 0.3)),
                               ("Shoes_Sneakers", (0.25, 0.25, 0.27)), ("Shoes_Sneakers_Sole", (0.92, 0.92, 0.9)), ("Bag_Shoulder", (0.35, 0.22, 0.12))]},
    "officer": {"skin": "brown", "nose": "Nose_Wide", "hair": ("Hair_Buzz", (0.1, 0.08, 0.06)), "beard": ("Beard_Goatee", (0.12, 0.09, 0.07)),
                "parts": [("Hat_PoliceCap", (0.12, 0.16, 0.34)), ("Detail_CapBadge", (0.98, 0.82, 0.2)), ("Top_LongSleeve", (0.2, 0.3, 0.6)),
                          ("Jacket_PoliceVest", (0.14, 0.15, 0.17)), ("Text_PoliceVest", (0.95, 0.95, 0.95)), ("Detail_Pouches", (0.1, 0.1, 0.11)),
                          ("Pants_Long", (0.12, 0.15, 0.32)), ("Shoes_Boots", (0.06, 0.06, 0.07)), ("Shoes_Boots_Sole", (0.03, 0.03, 0.03))]},
    "surfer": {"skin": "pale", "nose": "Nose_Button", "hair": ("Hair_Quiff", (0.85, 0.36, 0.12)), "beard": ("Beard_ChinStrap", (0.8, 0.33, 0.1)),
               "parts": [("Top_TShirt", (0.2, 0.7, 0.88)), ("Pants_Shorts", (0.18, 0.18, 0.2)), ("Socks", (0.95, 0.95, 0.95)),
                         ("Shoes_Sneakers", (0.5, 0.3, 0.15)), ("Shoes_Sneakers_Sole", (0.95, 0.95, 0.92))]},
    "designer": {"skin": "light", "nose": "Nose_Long", "hair": ("Hair_Short", (0.42, 0.25, 0.12)),
                 "parts": [("Glasses_Round", (0.9, 0.7, 0.2)), ("Top_TShirt", (0.06, 0.06, 0.07)), ("Jacket_Blazer", (0.95, 0.5, 0.08)),
                           ("Pants_Long", (0.06, 0.06, 0.07)), ("Belt", (0.08, 0.06, 0.04)), ("Detail_Buckle", (0.95, 0.78, 0.2)),
                           ("Shoes_Dress", (0.15, 0.08, 0.05)), ("Shoes_Dress_Sole", (0.08, 0.05, 0.03))]},
    "student": {"skin": "dark", "nose": "Nose_Button", "hair": ("Hair_Ponytail", (0.08, 0.06, 0.05)), "female": 1.0, "brow_scale": 0.7,
                "parts": [("Top_Hoodie", (0.7, 0.25, 0.4)), ("Detail_Hood", (0.66, 0.23, 0.37)), ("Detail_HoodiePocket", (0.6, 0.2, 0.34)),
                          ("Pants_Long", (0.25, 0.35, 0.6)), ("Shoes_Sneakers", (0.95, 0.95, 0.95)), ("Shoes_Sneakers_Sole", (0.85, 0.2, 0.2)),
                          ("Bag_Backpack", (0.2, 0.45, 0.4))]},
    "manager": {"skin": "light", "nose": "Nose_Round", "hair": ("Hair_Bob", (0.2, 0.12, 0.08)), "female": 1.0, "brow_scale": 0.7,
                "parts": [("Top_ButtonShirt", (0.92, 0.92, 0.94)), ("Detail_Collar", (0.95, 0.95, 0.96)), ("Jacket_Blazer", (0.18, 0.2, 0.3)),
                          ("Pants_Skirt", (0.18, 0.2, 0.3)), ("Shoes_Dress", (0.08, 0.06, 0.06)), ("Shoes_Dress_Sole", (0.05, 0.04, 0.04)),
                          ("Acc_Necklace", (0.9, 0.75, 0.3))]},
}

_mat_cache = {}


def mat(color, rough=0.55):
    key = (tuple(round(c, 3) for c in color), rough)
    if key in _mat_cache:
        return _mat_cache[key]
    m = bpy.data.materials.new("Prev_%d" % len(_mat_cache))
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(color), 1.0)
    b.inputs["Roughness"].default_value = rough
    for name in ("Specular IOR Level", "Specular"):
        if name in b.inputs:
            b.inputs[name].default_value = 0.22     # matte, toy-like plastic
            break
    _mat_cache[key] = m
    return m


def instance(name, color, coll, xf, keys=None, rough=0.55, scale_local=None):
    src = bpy.data.objects[name]
    ob = src.copy()
    ob.data = src.data.copy()
    ob.parent = None
    for m in list(ob.modifiers):
        ob.modifiers.remove(m)
    coll.objects.link(ob)
    ob.data.materials.clear()
    ob.data.materials.append(mat(color, rough))
    if ob.data.shape_keys:
        for kb in ob.data.shape_keys.key_blocks[1:]:
            kb.value = float((keys or {}).get(kb.name, 0.0))
    if scale_local is not None:
        pivot, s = scale_local
        ob.data.transform(Matrix.Translation(pivot) @ Matrix.Diagonal((*s, 1.0)) @ Matrix.Translation(-pivot))
    a_pose(ob, A_POSE_DEG)
    ob.matrix_world = xf @ ob.matrix_world
    ob.hide_render = False
    return ob


A_POSE_DEG = 0.0          # arms swung out from the body (character-sheet A-pose); 0 = rest pose
HAND_TWIST_DEG = 0.0     # in the A-pose the palms turn half-way forward, as on a character sheet


def a_pose(ob, deg):
    """Swings the arms out about the shoulders using the part's own skin weights."""
    if abs(deg) < 0.01:
        return
    arm = bpy.data.objects.get("Armature")
    if arm is None:
        return
    groups = {g.index: g.name for g in ob.vertex_groups}
    piv = {}
    for side, sg in (("Left", 1), ("Right", -1)):
        p = arm.data.bones[side + "UpperArm"].head_local
        piv[side] = (Matrix.Translation(p) @ Matrix.Rotation(math.radians(-deg * sg), 4, "Y") @ Matrix.Translation(-p))
    for side, sg in (("Left", 1), ("Right", -1)):     # shoulders follow half way
        p = arm.data.bones[side + "UpperArm"].head_local
        piv[side + "S"] = (Matrix.Translation(p) @ Matrix.Rotation(math.radians(-deg * 0.5 * sg), 4, "Y") @ Matrix.Translation(-p))
        # hands: twist about the forearm axis first, then swing with the arm
        h = arm.data.bones[side + "Hand"].head_local
        e = arm.data.bones[side + "LowerArm"].head_local
        tw = Matrix.Translation(h) @ Matrix.Rotation(math.radians(HAND_TWIST_DEG * sg), 4, (h - e).normalized()) @ Matrix.Translation(-h)
        piv[side + "H"] = piv[side] @ tw

    def side_of(n):
        for side in ("Left", "Right"):
            if n == side + "Hand":
                return side + "H"
            if n.startswith(side) and any(k in n for k in ("UpperArm", "LowerArm")):
                return side
            if n == side + "Shoulder":
                return side + "S"
        return None
    keys = ob.data.shape_keys.key_blocks if ob.data.shape_keys else None
    for v in ob.data.vertices:
        M = Matrix(((0, 0, 0, 0), (0, 0, 0, 0), (0, 0, 0, 0), (0, 0, 0, 0)))
        tot = 0.0
        moved = False
        for g in v.groups:
            sd = side_of(groups.get(g.group, ""))
            M = M + (piv[sd] if sd else Matrix.Identity(4)) * g.weight
            tot += g.weight
            moved = moved or sd is not None
        if not moved or tot <= 0:
            continue
        M = M * (1.0 / tot)
        if keys:
            for kb in keys:
                kb.data[v.index].co = M @ kb.data[v.index].co
        v.co = M @ v.co
    ob.data.update()


def build_outfit(name, coll, xf, body_keys=None):
    o = OUTFITS[name]
    skin = SKIN_TONES[o["skin"]]
    keys = dict(body_keys or {})
    if o.get("female"):
        keys["Female"] = o["female"]
    hair_col = o["hair"][1] if o.get("hair") else (0.3, 0.2, 0.12)
    objs = []
    objs.append(instance("Body", skin, coll, xf, keys))
    for f in FACE:
        if f.startswith("EyeWhite"):
            c = (0.97, 0.97, 0.95)
        elif f.startswith("Iris"):
            c = (0.36, 0.33, 0.3)
        elif f.startswith("Pupil"):
            c = (0.02, 0.02, 0.02)
        elif f.startswith("Lid"):
            c = tuple(x * 0.93 for x in skin)
        elif f.startswith("LowerLid"):
            c = tuple(x * 0.88 for x in skin)
        elif f.startswith("Brow"):
            c = tuple(x * 0.8 for x in hair_col)
        elif f.startswith("Mouth"):
            c = (0.22, 0.08, 0.06)
        else:
            c = skin
        sl = None
        if f.startswith("Brow") and o.get("brow_scale"):
            p = bpy.data.objects[f].data.vertices[0].co
            center = sum((v.co for v in bpy.data.objects[f].data.vertices), Vector()) / len(bpy.data.objects[f].data.vertices)
            sl = (center, (1.0, 1.0, o["brow_scale"]))
        ob = instance(f, c, coll, xf, None, 0.25 if f.startswith(("EyeWhite", "Pupil", "Iris")) else 0.55, sl)
        if f.startswith("Lid_"):
            eye = bpy.data.objects["EyeWhite_" + f[-1]]
            center = sum((v.co for v in eye.data.vertices), Vector()) / len(eye.data.vertices)
            ob.data.transform(Matrix.Translation(center) @ Matrix.Rotation(math.radians(LID_REST_DEG), 4, "X") @ Matrix.Translation(-center))
        objs.append(ob)
    objs.append(instance(o["nose"], tuple(x * 0.97 for x in skin), coll, xf))
    if o.get("hair"):
        sl = None
        if o["hair"][0] != "Hair_Buzz" and any(p.startswith("Hat") for p, _ in o["parts"]):
            # same as the game: hair is squeezed under hats
            head = bpy.data.objects["HeadBase"].data.vertices
            hc = sum((v.co for v in head), Vector()) / len(head)
            sl = (hc, (0.92, 0.92, 0.92))
        objs.append(instance(o["hair"][0], o["hair"][1], coll, xf, None, 0.7, sl))
    if o.get("beard"):
        objs.append(instance(o["beard"][0], o["beard"][1], coll, xf, None, 0.7))
    for part, col in o["parts"]:
        objs.append(instance(part, col, coll, xf, keys, 0.5 if "Shoes" in part else 0.65))
    return objs


def studio(scene, res=(480, 720), ortho=2.15, samples=32):
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    try:
        scene.cycles.use_denoising = True
    except Exception:
        pass
    scene.cycles.device = "CPU"
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    w = scene.world or bpy.data.worlds.new("Studio")
    scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes["Background"]
    bg.inputs[0].default_value = (0.95, 0.95, 0.96, 1)
    bg.inputs[1].default_value = 0.3
    if "CamBG" not in nt.nodes:
        # camera sees a light-grey backdrop, objects are lit by the dimmer environment
        cam_bg = nt.nodes.new("ShaderNodeBackground")
        cam_bg.name = "CamBG"
        cam_bg.inputs[0].default_value = (0.86, 0.87, 0.89, 1)
        cam_bg.inputs[1].default_value = 1.0
        lp = nt.nodes.new("ShaderNodeLightPath")
        mix = nt.nodes.new("ShaderNodeMixShader")
        out = nt.nodes["World Output"]
        nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
        nt.links.new(bg.outputs[0], mix.inputs[1])
        nt.links.new(cam_bg.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
    if "PrevFloor" not in bpy.data.objects:
        bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
        fl = bpy.context.view_layer.objects.active
        fl.name = "PrevFloor"
        fl.data.materials.append(mat((0.93, 0.93, 0.95), 0.8))
        for name, loc, energy, size in (("Key", (2.6, -3.6, 3.4), 135, 3.0), ("Fill", (-3.2, -2.4, 2.2), 38, 4.0), ("Rim", (0.5, 3.5, 3.2), 110, 2.5)):
            ld = bpy.data.lights.new(name, "AREA")
            ld.energy = energy
            ld.size = size
            lo = bpy.data.objects.new(name, ld)
            scene.collection.objects.link(lo)
            lo.location = loc
            direction = Vector((0, 0, 1.0)) - Vector(loc)
            lo.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        cam = bpy.data.cameras.new("PrevCam")
        cam.type = "ORTHO"
        co = bpy.data.objects.new("PrevCam", cam)
        scene.collection.objects.link(co)
        scene.camera = co
    scene.camera.data.ortho_scale = ortho


def look(scene, yaw_deg, target=(0, 0, 0.98), dist=6.0, height=1.05):
    cam = scene.camera
    a = math.radians(yaw_deg)
    pos = Vector((math.sin(a) * dist, -math.cos(a) * dist, height))
    cam.location = pos
    cam.rotation_euler = (Vector(target) - pos).to_track_quat("-Z", "Y").to_euler()


def shot(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)


def clear(coll):
    for ob in list(coll.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def render_reference_views(out_dir):
    """Front / back / sides / size comparison, framed like a character-sheet turnaround."""
    scene = bpy.context.scene
    for ob in bpy.data.objects:
        if ob.type == "MESH" and ob.name != "PrevFloor":
            ob.hide_render = True
    coll = bpy.data.collections.get("Preview") or bpy.data.collections.new("Preview")
    if coll.name not in scene.collection.children:
        scene.collection.children.link(coll)
    global A_POSE_DEG
    A_POSE_DEG = 17.0
    studio(scene, res=(720, 720), ortho=2.34)
    build_outfit("casual", coll, Matrix.Identity(4))
    for name, yaw in (("front", 0), ("back", 180), ("left", 90), ("right", -90)):
        look(scene, yaw, target=(0, 0, 0.86), height=0.86)
        shot(scene, os.path.join(out_dir, "view_%s.png" % name))
    clear(coll)
    build_outfit("casual", coll, Matrix.Translation((-0.42, 0, 0)) @ Matrix.Diagonal((0.84, 0.84, 0.84, 1)))
    build_outfit("casual", coll, Matrix.Translation((0.38, 0, 0)))
    look(scene, 0, target=(0, 0, 0.86), height=0.86)
    shot(scene, os.path.join(out_dir, "view_sizes.png"))
    clear(coll)
    A_POSE_DEG = 0.0


def render_all(out_dir, quick=False):
    scene = bpy.context.scene
    for ob in bpy.data.objects:
        ob.hide_render = True
    coll = bpy.data.collections.new("Preview")
    scene.collection.children.link(coll)
    studio(scene)
    # 1) Turnaround of the default casual look
    build_outfit("casual", coll, Matrix.Identity(4))
    for name, yaw in ((("front", 0), ("three_quarter", 30)) if quick else (("front", 0), ("back", 180), ("side_left", 90), ("side_right", -90), ("three_quarter", 30))):
        look(scene, yaw)
        shot(scene, os.path.join(out_dir, "turn_%s.png" % name))
    # Face close-up
    studio(scene, res=(600, 600), ortho=0.55)
    look(scene, 12, target=(0, 0, 1.66), height=1.68)
    shot(scene, os.path.join(out_dir, "face_closeup.png"))
    clear(coll)
    if quick:
        studio(scene, res=(480, 720), ortho=2.15)
        for name in ("officer", "student"):
            build_outfit(name, coll, Matrix.Identity(4))
            look(scene, 0)
            shot(scene, os.path.join(out_dir, "outfit_%s.png" % name))
            clear(coll)
        return
    # 2) Size comparison (short and tall)
    studio(scene, res=(720, 720), ortho=2.3)
    build_outfit("casual", coll, Matrix.Translation((-0.38, 0, 0)) @ Matrix.Diagonal((0.84, 0.84, 0.84, 1)))
    build_outfit("casual", coll, Matrix.Translation((0.38, 0, 0)) @ Matrix.Diagonal((1.06, 1.06, 1.06, 1)))
    look(scene, 0, target=(0, 0, 1.02))
    shot(scene, os.path.join(out_dir, "size_compare.png"))
    clear(coll)
    # 3) Body base mesh variants (clay)
    studio(scene, res=(1500, 700), ortho=4.3)
    for k, keyname in enumerate(["", "Thin", "Heavy", "Muscular", "Female"]):
        xf = Matrix.Translation(((k - 2) * 0.8, 0, 0))
        keys = {keyname: 1.0} if keyname else {}
        for part in ["Body"] + FACE + ["Nose_Round"]:
            c = (0.75, 0.75, 0.77)
            if part.startswith("Pupil"):
                c = (0.05, 0.05, 0.05)
            elif part.startswith(("EyeWhite",)):
                c = (0.95, 0.95, 0.95)
            instance(part, c, coll, xf, keys if part == "Body" else None, 0.6)
    look(scene, 0, target=(0, 0, 0.98))
    shot(scene, os.path.join(out_dir, "base_mesh_variants.png"))
    clear(coll)
    # 4) Outfit line-up (each rendered separately, composited outside Blender)
    studio(scene, res=(480, 720), ortho=2.15)
    for name in OUTFITS:
        build_outfit(name, coll, Matrix.Identity(4))
        look(scene, 0)
        shot(scene, os.path.join(out_dir, "outfit_%s.png" % name))
        clear(coll)
    # 5) Hair styles (head close-ups)
    studio(scene, res=(300, 300), ortho=0.62, samples=24)
    for hair in ["Hair_Short", "Hair_Buzz", "Hair_Spiky", "Hair_Afro", "Hair_Long", "Hair_Ponytail", "Hair_Bun", "Hair_SideTufts", "Hair_Quiff", "Hair_Bob",
                 "Beard_Goatee", "Beard_Full", "Hat_Cap", "Hat_Beanie", "Hat_Brimmed", "Hat_PoliceCap"]:
        OUTFITS["_tmp"] = {"skin": "tan", "nose": "Nose_Round", "hair": (hair, (0.35, 0.2, 0.1)) if hair.startswith(("Hair", "Beard")) else ("Hair_Short", (0.35, 0.2, 0.1)),
                           "parts": [("Top_TShirt", (0.6, 0.6, 0.62))] + ([(hair, (0.2, 0.3, 0.55))] if hair.startswith("Hat") else [])}
        build_outfit("_tmp", coll, Matrix.Identity(4))
        look(scene, 25, target=(0, 0, 1.68), height=1.72)
        shot(scene, os.path.join(out_dir, "style_%s.png" % hair))
        clear(coll)
