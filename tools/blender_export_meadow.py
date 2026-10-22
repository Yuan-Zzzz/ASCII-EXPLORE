import json
import sys

sys.path.insert(0, "/home/Yuan/data/Development/ascii_explore/tools")
from blender_client import run

code = r"""
import bpy, os

out_dir = "/home/Yuan/data/Development/ascii_explore/features/meadow/models"
os.makedirs(out_dir, exist_ok=True)

bpy.ops.object.select_all(action="DESELECT")
for obj in bpy.context.scene.objects:
    if obj.type == "MESH" and obj.name != "GrassBlade":
        obj.select_set(True)

bpy.ops.export_scene.gltf(
    filepath=os.path.join(out_dir, "meadow_set.glb"),
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_materials="EXPORT",
)

files = sorted(os.listdir(out_dir))
print("EXPORTED=" + ",".join(files))
"""

response = run(code)
print(json.dumps(response, ensure_ascii=False)[:1200])
