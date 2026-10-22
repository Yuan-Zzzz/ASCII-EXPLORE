import json
import sys

sys.path.insert(0, "/home/Yuan/data/Development/ascii_explore/tools")
from blender_client import run

code = r"""
import bpy, bmesh, math, random

scene = bpy.context.scene
for obj in list(scene.objects):
    if obj.type in {"MESH", "CAMERA", "LIGHT"}:
        bpy.data.objects.remove(obj, do_unlink=True)

random.seed(20261023)

def flat_color(name, rgba):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = False
    mat.use_backface_culling = False
    mat.diffuse_color = rgba
    mat.roughness = 0.9
    mat.specular_intensity = 0.0
    return mat

mat_ground = flat_color("Ground", (0.16, 0.34, 0.16, 1.0))
mat_shore  = flat_color("Shore",  (0.42, 0.38, 0.24, 1.0))
mat_rock   = flat_color("Rock",   (0.34, 0.36, 0.38, 1.0))
mat_wood   = flat_color("Wood",   (0.30, 0.18, 0.10, 1.0))
mat_stone  = flat_color("Stone",  (0.45, 0.47, 0.50, 1.0))

# Ground: lowpoly subdivided disc with gentle hills; pond area kept low.
bpy.ops.mesh.primitive_circle_add(vertices=48, radius=60, fill_type="NGON", location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.subdivide(number_cuts=3)
bpy.ops.object.mode_set(mode="OBJECT")
for v in ground.data.vertices:
    x, y = v.co.x, v.co.y
    rim = math.sqrt(x * x + y * y) / 60.0
    h = 0.9 * math.sin(x * 0.12) * math.cos(y * 0.10) + 0.5 * math.sin(x * 0.05 + 1.3)
    pond = max(0.0, 1.0 - math.sqrt((x + 14) ** 2 + (y - 8) ** 2) / 16.0)
    v.co.z = h * (0.35 + 0.65 * rim) - pond * 1.2
for poly in ground.data.polygons:
    poly.use_smooth = False
ground.data.materials.append(mat_ground)

# Shore ring around the pond.
bpy.ops.mesh.primitive_circle_add(vertices=24, radius=17.5, fill_type="NOTHING", location=(-14, 8, -0.55))
shore = bpy.context.active_object
shore.name = "ShoreRing"
bm = bmesh.new(); bm.from_mesh(shore.data)
bm.edges.ensure_lookup_table()
bmesh.ops.contextual_create(bm, geom=bm.edges)
bm.to_mesh(shore.data); bm.free()
shore.data.materials.append(mat_shore)
for poly in shore.data.polygons:
    poly.use_smooth = False

# Rocks: icospheres with random scale and one deleted vertex cluster.
for i in range(7):
    angle = i * 2.4 + random.uniform(-0.3, 0.3)
    dist = random.uniform(22, 52)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=random.uniform(1.2, 3.2),
                                          location=(math.cos(angle) * dist, math.sin(angle) * dist, 0.2))
    rock = bpy.context.active_object
    rock.name = f"Rock{i}"
    rock.scale = (1.0, random.uniform(0.6, 1.1), random.uniform(0.5, 0.9))
    rock.rotation_euler = (random.uniform(0, 0.3), random.uniform(0, 0.3), random.uniform(0, 6.28))
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    rock.data.materials.append(mat_rock)
    for poly in rock.data.polygons:
        poly.use_smooth = False

# Bonfire: stone ring + crossed logs.
for i in range(8):
    angle = i / 8 * math.tau
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.38,
                                          location=(6 + math.cos(angle) * 1.1, -4 + math.sin(angle) * 1.1, 0.15))
    st = bpy.context.active_object
    st.name = f"FireStone{i}"
    st.scale = (1.0, 1.0, random.uniform(0.6, 1.0))
    st.rotation_euler = (0, 0, angle)
    st.data.materials.append(mat_stone)
    for poly in st.data.polygons:
        poly.use_smooth = False

for i in range(5):
    angle = i / 5 * math.pi
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.16, depth=1.7,
                                        location=(6, -4, 0.42))
    log = bpy.context.active_object
    log.name = f"FireLog{i}"
    log.rotation_euler = (math.pi / 2 + random.uniform(-0.2, 0.2), random.uniform(-0.2, 0.2), angle)
    log.data.materials.append(mat_wood)

# Grass blade card: single lowpoly quad, exported for reference/tinting.
bpy.ops.mesh.primitive_plane_add(size=0.12, location=(0, 0, 0.5))
blade = bpy.context.active_object
blade.name = "GrassBlade"
blade.scale = (1.0, 1.0, 8.0)
bpy.ops.object.transform_apply(scale=True)
blade.data.materials.append(flat_color("Grass", (0.30, 0.55, 0.20, 1.0)))

names = sorted(o.name for o in scene.objects if o.type == "MESH")
print("OBJECTS=" + ",".join(names))
"""

response = run(code)
print(json.dumps(response, ensure_ascii=False)[:1500])
