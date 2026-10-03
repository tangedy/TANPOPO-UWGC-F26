extends Node2D


func _ready() -> void:
	scale.x = absf(scale.x) * (1.0 if randi() % 2 == 0 else -1.0)
	z_index = -4 if randi() % 2 == 0 else -6
	_randomize_shader_offset(self)


func _randomize_shader_offset(node: Node) -> void:
	if node is CanvasItem:
		var canvas := node as CanvasItem
		if canvas.material is ShaderMaterial:
			var mat := (canvas.material as ShaderMaterial).duplicate() as ShaderMaterial
			mat.resource_local_to_scene = true
			mat.set_shader_parameter("offset", randf_range(1.0, 1000.0))
			canvas.material = mat
	for child in node.get_children():
		_randomize_shader_offset(child)
