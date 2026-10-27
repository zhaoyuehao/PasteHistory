"""Run in Blender with the editable Ivory_Tree.blend open and export_path set.
Exports the tree, five bird bodies, and five small bird accent meshes; the
original scene remains untouched. Bird controllers are exported with their
current transforms so depth staging in the authoring file survives packaging.
"""
import bpy
import math
from pathlib import Path

def depth(x, z):
    return .42*x*math.sin(z*1.1)+.35*(math.sin(x*1.7+z*.2)-math.sin(z*.2))

source = next(s for s in bpy.data.scenes if any(o.name.startswith('白枝 ·') for o in s.objects))
groups = [('Tree', [o for o in source.objects if o.name.startswith('白枝 ·')])]
for root in sorted([o for o in source.objects if o.type == 'EMPTY' and o.name.startswith('Bird ')], key=lambda o: o.name):
    bird_name = root.name.split(' ·')[0].replace(' ', '_')
    children = list(root.children)
    # Keep small high-contrast details as a separate mesh so the native
    # renderer can give the bird a restrained graphite/amber material split.
    accents = [o for o in children if any(token in o.name for token in ('尖嘴', '眼', '足', '趾'))]
    body = [o for o in children if o not in accents]
    groups.append((bird_name, body))
    groups.append((bird_name + '_accent', accents))
count = 0
total = 0
with bpy.context.temp_override(scene=source, view_layer=source.view_layers[0]):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    Path(export_path).mkdir(parents=True, exist_ok=True)
    for name, objects in groups:
        count = 0
        with open(str(Path(export_path) / (name + '.obj')), 'w') as output:
            output.write('# Ivory tree, Blender to SceneKit: x,z,-y\n')
            output.write('o '+name+'\ns 1\n')
            for original in objects:
                if original.type not in {'MESH', 'CURVE'}:
                    continue
                mesh = bpy.data.meshes.new_from_object(original.evaluated_get(depsgraph))
                mesh.transform(original.matrix_world)
                shift = depth(original.parent.location.x, original.parent.location.z) if original.parent else None
                for v in mesh.vertices:
                    v.co.y += shift if shift is not None else depth(v.co.x, v.co.z)
                obj = bpy.data.objects.new('Export temporary', mesh)
                source.collection.objects.link(obj)
                modifier = obj.modifiers.new('Realtime LOD', 'DECIMATE')
                modifier.ratio = .22 if name == 'Tree' else .55
                depsgraph.update()
                evaluated = obj.evaluated_get(depsgraph)
                reduced = evaluated.to_mesh()
                reduced.calc_loop_triangles()
                for v in reduced.vertices:
                    output.write('v %.6f %.6f %.6f\n' % (v.co.x, v.co.z, -v.co.y))
                for v in reduced.vertices:
                    output.write('vn %.6f %.6f %.6f\n' % (v.normal.x, v.normal.z, -v.normal.y))
                for triangle in reduced.loop_triangles:
                    output.write('f '+' '.join('%d//%d' % (count+i+1, count+i+1) for i in triangle.vertices)+'\n')
                count += len(reduced.vertices)
                total += len(reduced.vertices)
                evaluated.to_mesh_clear()
                bpy.data.objects.remove(obj, do_unlink=True)
                bpy.data.meshes.remove(mesh)
result = {'exported': export_path, 'meshes': len(groups), 'vertices': total}
