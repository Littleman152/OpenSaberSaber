extends Node

var floor_albedo_texture : Texture2D = null

# The player rig moved some nodes (StandingGround, event_driver, the HUD labels) under "PlayerRig",
# so look there first and fall back to the old location.
func _n(path: String) -> Node:
	var root := get_node_or_null("/root/BeepSaber")
	if root == null:
		return null
	var rig := root.get_node_or_null("PlayerRig")
	var n: Node = null
	if rig != null:
		n = rig.get_node_or_null(path)
	if n == null:
		n = root.get_node_or_null(path)
	return n

func set_mixed_reality(mr: bool):
	var xr_interface := XRServer.find_interface("OpenXR") as XRInterface
	if xr_interface and xr_interface.is_passthrough_supported():
		if mr:
			if xr_interface.start_passthrough():
				get_viewport().transparent_bg = true
				xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
				print("BeepSaber: MR")
		else:
			xr_interface.stop_passthrough()
			get_viewport().transparent_bg = false
			xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	
	var cut_floor := _n("StandingGround/Node3D/cutFloor") as MeshInstance3D
	var sphere := _n("event_driver/Level/Sphere") as Node3D
	var mult_bg := _n("Multiplier_Label/Text_Background") as Node3D
	var point_bg := _n("Point_Label/Text_Background2") as Node3D
	
	if cut_floor != null:
		var material := cut_floor.material_override as StandardMaterial3D
		if material != null:
			if floor_albedo_texture == null:
				floor_albedo_texture = material.albedo_texture
			if mr:
				material.transparency = 1
				material.albedo_texture = null
				material.albedo_color = Color(0,0,0,.6)
			else:
				material.transparency = 0
				material.albedo_texture = floor_albedo_texture
	
	if mr:
		if sphere != null: sphere.hide()
		if mult_bg != null: mult_bg.show()
		if point_bg != null: point_bg.show()
	else:
		if sphere != null: sphere.show()
		if mult_bg != null: mult_bg.hide()
		if point_bg != null: point_bg.hide()
	
	var floor_mesh := _n("event_driver/Level/floor") as MeshInstance3D
	if floor_mesh != null:
		var floor_material := floor_mesh.material_override as StandardMaterial3D
		if floor_material != null:
			var gradient_texture := floor_material.albedo_texture as GradientTexture2D
			if gradient_texture != null:
				var gradient := gradient_texture.gradient
				for i in gradient.get_point_count():
					var c := gradient.get_color(i)
					if Settings.mixed_reality:
						gradient.set_color(i, Color(c.r,c.g,c.b,0.6))
					else:
						gradient.set_color(i, Color(c.r,c.g,c.b))
