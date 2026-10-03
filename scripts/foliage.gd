extends Node2D


func _ready() -> void:
	for child in get_children():
		if child is Node2D:
			child.scale.x = 1.0 if randi() % 2 == 0 else -1.0
			child.z_index = -4 if randi() % 2 == 0 else -6
		_randomize_shader_offset(child)


func _randomize_shader_offset(node: Node) -> void:
	if node is CanvasItem and node.material is ShaderMaterial:
		var mat := (node.material as ShaderMaterial).duplicate() as ShaderMaterial
		mat.set_shader_parameter("offset", randf() * 10.0)
		node.material = mat
	for child in node.get_children():
		_randomize_shader_offset(child)
