extends RefCounted
class_name ChromaEnvironment
# Chroma "environment enhancement": reads the map's _environment list (v2) / environment list (v3)
# and applies it to the nodes under the event driver's "Level" node.
#
# Supported per entry: _id + _lookupMethod (Exact, Contains, StartsWith, EndsWith, Regex),
# _active, _duplicate, _position, _localPosition, _rotation, _localRotation, _scale, _track,
# and _geometry (Cube, Sphere, Capsule, Cylinder, Plane, Quad, Triangle) with a material (named in the
# difficulty's _materials table, or inline: _shader + _color). Geometry stays fixed in the world and is
# animated by Noodle track events (update_tracks()).
# Not supported: _components (lights), _lightID, _follow, _collision.
#
# Beat Saber's object names (Pillar, Mirror, clouds...) don't exist in this game's environment,
# so unmatched ids fall back to the ALIASES table below. Edit it to point more ids at your nodes.

const MAX_DUPLICATES := 64     # cap so a map can't spawn thousands of nodes on Quest
const MAX_GEOMETRY := 256

# lowercase fragment of a Beat Saber id -> node paths under the Level node
const ALIASES := {
	"glowline": ["floor/line0", "floor/line1", "floor/line2", "floor/line3", "floor/line4"],
	"laser": ["DiagonalLasers", "SquareLasers", "LeftWavingLasers", "RightWavingLasers"],
	"ring": ["rings"],
	"tracklight": ["TrackLights"],
	"frame": ["SquareLasers"],
	"construction": ["SquareLasers", "Endpath"],
	"rectanglefakeglow": ["SquareLasers"],
	"bottomglow": ["TrackLights"],
	"mirror": ["floor", "../../StandingGround"],
}

# Nodes under "Level" that get hidden when a difficulty has an "_environmentRemoval" list.
# Edit this to taste: remove "TrackLights", for example, to keep the glowing lane edges.
const REMOVAL_HIDES := ["rings", "DiagonalLasers", "SquareLasers", "LeftWavingLasers", "RightWavingLasers", "TrackLights", "Endpath"]

var tracks := {}                   # track name -> Array of nodes (for future track events)
var hidden_registry := {}          # the event driver's chroma_hidden dictionary (set by the game)
var _hidden_nodes: Array[Node3D] = []

var _root: Node3D
var _nodes: Array[Node3D] = []
var _names := PackedStringArray()  # dotted path of every node under _root, e.g. "SquareLasers.Bar7"
var _match_cache := {}
var _regex_cache := {}
var _saved: Array = []             # [node, visible, transform] for nodes we changed
var _saved_set := {}
var _spawned: Array[Node] = []     # duplicates and geometry we created

# false: geometry stays fixed in the world, like in Beat Saber (the Level node is under the player rig,
# so anything added there would travel with the player)
const GEOMETRY_FOLLOWS_PLAYER := false
# true: "Standard" materials are lit by the scene's lights; false: flat color (safer, the game's
# environment has few lights)
const STANDARD_IS_LIT := false

var geometry_root: Node3D = null   # set by the game: a node that is NOT under the player rig
var _named_materials := {}         # the difficulty's _materials table
var _material_cache := {}
var _geo: Array = []               # geometry with its base transform and tracks, animated by update_tracks()

func _init(root: Node3D) -> void:
	_root = root

static func _g(d: Dictionary, key: String) -> Variant:
	return d.get("_" + key, d.get(key, null))

static func _has3(v: Variant) -> bool:
	return v is Array and (v as Array).size() >= 3

static func _v3(v: Variant) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2]))

# Unity euler degrees (ZXY order) -> game basis (z axis is mirrored, so x/y rotations flip sign)
static func _euler_basis(deg: Vector3) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(-deg.x), deg_to_rad(-deg.y), deg_to_rad(deg.z)), EULER_ORDER_YXZ)

func apply(map_data: Dictionary) -> void:
	if _root == null:
		return
	var custom: Variant = map_data.get("_customData", map_data.get("customData", null))
	if not custom is Dictionary:
		return
	var env: Variant = (custom as Dictionary).get("_environment", (custom as Dictionary).get("environment", null))
	if not env is Array or (env as Array).is_empty():
		return
	var mats: Variant = (custom as Dictionary).get("_materials", (custom as Dictionary).get("materials", null))
	if mats is Dictionary:
		_named_materials = mats as Dictionary
	_index_nodes()
	for entry: Variant in env:
		if entry is Dictionary:
			_apply_entry(entry as Dictionary)
# Info.dat "_environmentRemoval" (Lucy, Midnight Lady...): the map removes Beat Saber's environment
# and builds its own out of walls. Those object names don't exist here, so when the difficulty
# removes anything we hide this game's decorative environment instead.
func apply_removal(difficulty_custom_data: Dictionary) -> void:
	if _root == null:
		return
	var rem: Variant = difficulty_custom_data.get("_environmentRemoval", difficulty_custom_data.get("environmentRemoval", null))
	if not rem is Array or (rem as Array).is_empty():
		return
	for path: String in REMOVAL_HIDES:
		var n := _root.get_node_or_null(path)
		if n is Node3D:
			var n3 := n as Node3D
			_save(n3)
			n3.visible = false
			hidden_registry[n3] = true      # keeps the light events from switching it back on
			_hidden_nodes.append(n3)
# Undo everything: delete duplicates/geometry and put changed nodes back as they were.
func restore() -> void:
	for n: Node in _spawned:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()
	_spawned.clear()
	for h: Node3D in _hidden_nodes:
		hidden_registry.erase(h)
	_hidden_nodes.clear()
	for s: Array in _saved:
		var n := s[0] as Node3D
		if is_instance_valid(n):
			n.visible = s[1]
			n.transform = s[2]
	_saved.clear()
	_saved_set.clear()
	tracks.clear()
	_geo.clear()
	_named_materials = {}
	_material_cache.clear()
	_match_cache.clear()

func _index_nodes() -> void:
	_nodes.clear()
	_names = PackedStringArray()
	_match_cache.clear()
	_collect(_root, "")

func _collect(parent: Node, prefix: String) -> void:
	for c: Node in parent.get_children():
		if c is Node3D:
			var nm := prefix + String(c.name)
			_nodes.append(c as Node3D)
			_names.append(nm)
			_collect(c, nm + ".")

func _lookup(id: String, method: String, allow_alias: bool) -> Array:
	var key := method + "|" + id + "|" + str(allow_alias)
	if _match_cache.has(key):
		return _match_cache[key]
	var rx: RegEx = null
	if method == "Regex":
		if _regex_cache.has(id):
			rx = _regex_cache[id]
		else:
			rx = RegEx.new()
			if rx.compile(id) != OK:
				rx = null
			_regex_cache[id] = rx
	var result: Array = []
	for i in _nodes.size():
		var nm := _names[i]
		var hit := false
		match method:
			"Exact":
				hit = nm == id or String(_nodes[i].name) == id
			"Contains":
				hit = nm.contains(id)
			"StartsWith":
				hit = nm.begins_with(id)
			"EndsWith":
				hit = nm.ends_with(id)
			"Regex":
				hit = rx != null and rx.search(nm) != null
		if hit:
			result.append(_nodes[i])
	if result.is_empty() and allow_alias:
		result = _alias_lookup(id)
	_match_cache[key] = result
	return result

func _alias_lookup(id: String) -> Array:
	var result: Array = []
	var low := id.to_lower()
	for key: String in ALIASES:
		if low.contains(key):
			for path: String in ALIASES[key]:
				var n := _root.get_node_or_null(path)
				if n is Node3D:
					result.append(n)
			break
	return result

func _apply_entry(e: Dictionary) -> void:
	var geometry: Variant = _g(e, "geometry")
	if geometry is Dictionary:
		_make_geometry(e, geometry as Dictionary)
		return
	var id: Variant = _g(e, "id")
	if not id is String:
		return
	var method_v: Variant = _g(e, "lookupMethod")
	var method := String(method_v) if method_v is String else "Exact"
	var dup_v: Variant = _g(e, "duplicate")
	var dup_count := int(dup_v) if (dup_v is float or dup_v is int) else 0
	# Beat Saber ids are only mapped onto your nodes through ALIASES for plain "hide" entries
	# (_active: false). Duplicating or moving a stand-in node would just make a mess.
	var active_v: Variant = _g(e, "active")
	var allow_alias := false
	if active_v is bool:
		allow_alias = (not (active_v as bool)) and dup_count == 0
	var targets := _lookup(String(id), method, allow_alias)
	if targets.is_empty():
		return
	if dup_count > 0:
		# the transform in this entry applies to the copies, the originals stay as they are
		var copies: Array = []
		for n: Node3D in targets:
			for k in dup_count:
				if _spawned.size() >= MAX_DUPLICATES:
					break
				var d := n.duplicate() as Node3D
				n.get_parent().add_child(d)
				_spawned.append(d)
				copies.append(d)
		targets = copies
	for n: Node3D in targets:
		_apply_transform(n, e)

func _save(n: Node3D) -> void:
	if _saved_set.has(n):
		return
	_saved_set[n] = true
	_saved.append([n, n.visible, n.transform])

func _apply_transform(n: Node3D, e: Dictionary) -> void:
	if not _spawned.has(n):
		_save(n)
	var active: Variant = _g(e, "active")
	if active is bool:
		n.visible = active
		if active:
			hidden_registry.erase(n)
		else:
			hidden_registry[n] = true
			_hidden_nodes.append(n)
	var unit := Vector3(Settings.LANE_DISTANCE_X, Constants.LANE_DISTANCE_Y, Settings.LANE_DISTANCE_X)
	var scale_v: Variant = _g(e, "scale")
	if _has3(scale_v):
		n.scale = n.scale * _v3(scale_v)
	var rot_v: Variant = _g(e, "rotation")
	if _has3(rot_v):
		n.global_basis = _euler_basis(_v3(rot_v)) * Basis.from_scale(n.scale)
	var lrot_v: Variant = _g(e, "localRotation")
	if _has3(lrot_v):
		n.basis = _euler_basis(_v3(lrot_v)) * Basis.from_scale(n.scale)
	var pos_v: Variant = _g(e, "position")
	if _has3(pos_v):
		var p := _v3(pos_v)
		n.global_position = Vector3(p.x * unit.x, p.y * unit.y, -p.z * unit.z)
	var lpos_v: Variant = _g(e, "localPosition")
	if _has3(lpos_v):
		var lp := _v3(lpos_v)
		n.position = Vector3(lp.x * unit.x, lp.y * unit.y, -lp.z * unit.z)
	var track_v: Variant = _g(e, "track")
	if track_v is String:
		if not tracks.has(track_v):
			tracks[track_v] = []
		(tracks[track_v] as Array).append(n)

static func _make_triangle() -> ArrayMesh:
	var verts := PackedVector3Array([Vector3(-0.5, -0.5, 0.0), Vector3(0.5, -0.5, 0.0), Vector3(0.0, 0.5, 0.0)])
	var normals := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var uvs := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

# Unity's primitive sizes: cube 1, sphere diameter 1, capsule and cylinder height 2 radius 0.5,
# plane 10 x 10, quad 1 x 1.
func _mesh_for(type_name: String) -> Mesh:
	match type_name:
		"Cube":
			return BoxMesh.new()
		"Sphere":
			return SphereMesh.new()
		"Capsule":
			return CapsuleMesh.new()
		"Cylinder":
			return CylinderMesh.new()
		"Plane":
			var p := PlaneMesh.new()
			p.size = Vector2(10.0, 10.0)
			return p
		"Quad":
			return QuadMesh.new()
		"Triangle":
			return _make_triangle()
	return null

# Maps Chroma's shaders onto a few Godot materials. The special environment shaders (water,
# pillars, concrete, cars, mirrors) are approximated.
func _build_material(mat_v: Variant, flat_sided: bool) -> StandardMaterial3D:
	var def := {}
	if mat_v is String:
		var named: Variant = _named_materials.get(mat_v, null)
		if named is Dictionary:
			def = named as Dictionary
	elif mat_v is Dictionary:
		def = mat_v as Dictionary
	var shader := "Standard"
	var sv: Variant = _g(def, "shader")
	if sv is String:
		shader = sv as String
	var color := Color.WHITE
	var c: Variant = _g(def, "color")
	if _has3(c):
		var arr := c as Array
		color = Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]) if arr.size() > 3 else 1.0)
	var key := "%s|%s|%s" % [shader, str(color), str(flat_sided)]
	if _material_cache.has(key):
		return _material_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED if flat_sided else BaseMaterial3D.CULL_BACK
	match shader:
		"OpaqueLight":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"TransparentLight":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		"BaseWater", "BillieWater":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			if color.a >= 1.0:
				m.albedo_color = Color(color.r, color.g, color.b, 0.6)
		_:
			# "Standard" and everything else (BTSPillar, InterscopeConcrete, Obstacle, ...)
			if not STANDARD_IS_LIT:
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if color.a < 1.0:
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material_cache[key] = m
	return m

func _make_geometry(e: Dictionary, g: Dictionary) -> void:
	if _spawned.size() >= MAX_DUPLICATES + MAX_GEOMETRY:
		return
	var type_v: Variant = _g(g, "type")
	var type_name := String(type_v) if type_v is String else ""
	var mesh := _mesh_for(type_name)
	if mesh == null:
		return
	var flat_sided := type_name in ["Plane", "Quad", "Triangle"]
	var track_names := PackedStringArray()
	var track_v: Variant = _g(e, "track")
	if track_v is String:
		track_names.append(track_v as String)
	elif track_v is Array:
		for tn: Variant in track_v:
			if tn is String:
				track_names.append(tn as String)
	var material := _build_material(_g(g, "material"), flat_sided)
	if not track_names.is_empty():
		material = material.duplicate() as StandardMaterial3D   # a track may animate this object's color
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var parent: Node3D = _root
	if not GEOMETRY_FOLLOWS_PLAYER and geometry_root != null:
		parent = geometry_root
	parent.add_child(mi)
	_spawned.append(mi)
	_apply_transform(mi, e)
	if not track_names.is_empty():
		_geo.append({
			"n": mi,
			"tracks": track_names,
			"pos": mi.position,
			"b": mi.basis.orthonormalized(),
			"s": mi.basis.get_scale(),
			"mat": material,
			"color": material.albedo_color,
		})

# Called once per frame by the game (after NoodleTracks.begin_frame): moves geometry that has a _track
# with the track's animation, exactly like Noodle objects.
func update_tracks() -> void:
	var trk := NoodleTracks.current
	if trk == null or _geo.is_empty():
		return
	for g: Dictionary in _geo:
		var n := g["n"] as Node3D
		if not is_instance_valid(n):
			continue
		var track_names: PackedStringArray = g["tracks"]
		var sc: Vector3 = g["s"]
		var pos: Vector3 = g["pos"]
		var world_b := Basis.IDENTITY
		var local_b := Basis.IDENTITY
		var opacity := 1.0
		var mat := g["mat"] as StandardMaterial3D
		var base_color: Color = g["color"]
		var new_color := base_color
		for tname: String in track_names:
			var ts := trk.state(tname)
			sc *= ts.scale
			pos += ts.position
			world_b = Basis(ts.rot_q) * world_b
			local_b = local_b * Basis(ts.local_rot_q)
			opacity *= ts.dissolve
			if ts.has_color:
				new_color = ts.color
		var basis_final := (world_b * (g["b"] as Basis) * local_b).scaled_local(sc)
		n.transform = trk.parent_transform(track_names[0]) * Transform3D(basis_final, world_b * pos)
		n.visible = opacity > 0.01
		if new_color != mat.albedo_color:
			mat.albedo_color = new_color
			if new_color.a < 1.0:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
