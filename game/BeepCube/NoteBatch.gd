class_name NoteBatch
extends MultiMeshInstance3D
# Draws visual-only Noodle notes (fake / uninteractable: nothing to cut, only their arrow or dot is
# shown) in one MultiMesh instead of one full BeepCube node each. There are two batches, one for
# arrows and one for dots, because the glyph texture differs.

const CUBE_MESH_GLB := "res://game/BeepCube/BeepCubeMesh.glb"
const EMISSION_TEX := "res://game/BeepCube/BeepCubeEmission.png"
const SHADER := "res://game/BeepCube/note_batch.gdshader"
const MAX_NOTES := 1024
# the cube scene shows its mesh at scale 1 once its spawn animation has finished; change this
# if batched notes look bigger or smaller than real cubes
const MESH_SCALE := 1.0

class N extends RefCounted:
	var nm: NoodleMotion
	var base_color: Color

var _items: Array[N] = []
var _mm: MultiMesh


func setup(is_dot: bool) -> void:
	var src := (load(CUBE_MESH_GLB) as PackedScene).instantiate() as MeshInstance3D
	var mesh := src.mesh
	src.free()
	
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER) as Shader
	mat.set_shader_parameter(&"texture_emission", load(EMISSION_TEX))
	mat.set_shader_parameter(&"is_dot", is_dot)
	mat.set_shader_parameter(&"arrows_enabled", Settings.arrows_enabled)
	
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_mm.instance_count = MAX_NOTES
	_mm.visible_instance_count = 0
	multimesh = _mm
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the notes can be hundreds of meters from the origin (the player moves), so never cull the batch
	custom_aabb = AABB(Vector3(-20000, -20000, -20000), Vector3(40000, 40000, 40000))


func add_note(info: ColorNoteInfo, current_beat: float) -> void:
	if _items.size() >= MAX_NOTES or info.noodle == null:
		return
	var n := N.new()
	n.nm = NoodleMotion.new()
	var lane_xy := Vector2(
		Settings.LANE_DISTANCE_X * float(info.line_index) + Settings.LANE_ZERO_X,
		Constants.LANE_DISTANCE_Y * float(info.line_layer) + Constants.LAYER_ZERO_Y)
	n.nm.setup(info.noodle, info.beat, current_beat, info.rotation, lane_xy, info.cut_angle, Map.get_speed_scale(info.beat))
	n.nm.scale_mul = Vector3.ONE * (Settings.block_size / 100.0) * MESH_SCALE
	n.base_color = Map.color_left if info.color == 0 else Map.color_right
	_items.append(n)


func _physics_process(_delta: float) -> void:
	if Scoreboard.paused or not Map.current_info:
		return
	var i := 0
	while i < _items.size():
		var n := _items[i]
		if not n.nm.update():
			_remove(i)
			continue
		_write(i, n)
		i += 1
	_mm.visible_instance_count = _items.size()


func _write(i: int, n: N) -> void:
	var nm := n.nm
	if not nm.visible:
		_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0.0, -1000.0, 0.0)))
		return
	var c := nm.color if nm.has_color else n.base_color
	# glyph-only notes: the arrow dissolve and the whole-note dissolve both just fade what is drawn
	var d := 1.0 - nm.opacity * nm.arrow_opacity
	_mm.set_instance_transform(i, nm.xf)
	_mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, d))


# swap-remove: move the last note into slot i
func _remove(i: int) -> void:
	_items[i] = _items[_items.size() - 1]
	_items.pop_back()


# called when the track is cleared (the game calls this on every child of the track)
func clear_from_track() -> void:
	_items.clear()
	_mm.visible_instance_count = 0
