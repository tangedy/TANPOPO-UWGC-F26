extends RefCounted

static func deliver(area: Area2D, accel: Vector2) -> void:
	var seen: Array[Node] = []
	for node in area.get_overlapping_bodies():
		_send_push(node, accel, seen)
	for node in area.get_overlapping_areas():
		_send_push(node, accel, seen)


static func deliver_lift(area: Area2D, direction: Vector2, speed: float, accel: float) -> void:
	var seen: Array[Node] = []
	for node in area.get_overlapping_bodies():
		_send_lift(node, direction, speed, accel, seen)
	for node in area.get_overlapping_areas():
		_send_lift(node, direction, speed, accel, seen)


static func _receiver(node: Node) -> Node:
	if node.has_method("add_air_push"):
		return node
	var parent := node.get_parent()
	if parent and parent.has_method("add_air_push"):
		return parent
	return null


static func _send_push(node: Node, accel: Vector2, seen: Array[Node]) -> void:
	var receiver := _receiver(node)
	if receiver == null or receiver in seen:
		return
	seen.append(receiver)
	var scale := 1.0
	if receiver.has_method("air_push_scale"):
		scale = receiver.air_push_scale()
	receiver.add_air_push(accel * scale)


static func _send_lift(node: Node, direction: Vector2, speed: float, accel: float, seen: Array[Node]) -> void:
	var receiver := _receiver(node)
	if receiver == null or receiver in seen or not receiver.has_method("add_lift"):
		return
	seen.append(receiver)
	var scale := 1.0
	if receiver.has_method("air_push_scale"):
		scale = receiver.air_push_scale()
	receiver.add_lift(direction, speed * scale, accel * scale)
