extends RefCounted

static func deliver(area: Area2D, accel: Vector2) -> void:
	var seen: Array[Node] = []
	for node in area.get_overlapping_bodies():
		_send_push(node, accel, seen)
	for node in area.get_overlapping_areas():
		_send_push(node, accel, seen)


## Push every overlapping receiver with an accel sampled from `field`, a
## Callable taking the receiver's global position and returning a Vector2.
static func deliver_field(area: Area2D, field: Callable) -> void:
	var seen: Array[Node] = []
	var keep_up := area.has_method("keeps_upward_push") and area.keeps_upward_push()
	for node in area.get_overlapping_bodies():
		_send_field(node, field, seen, keep_up)
	for node in area.get_overlapping_areas():
		_send_field(node, field, seen, keep_up)


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


static func _send_field(node: Node, field: Callable, seen: Array[Node], keep_up: bool) -> void:
	var receiver := _receiver(node)
	if receiver == null or receiver in seen:
		return
	seen.append(receiver)
	var accel: Vector2 = field.call(receiver.global_position)
	var scale := 1.0
	if receiver.has_method("air_push_scale"):
		scale = receiver.air_push_scale()
	receiver.add_air_push(accel * scale, keep_up)


static func _send_lift(node: Node, direction: Vector2, speed: float, accel: float, seen: Array[Node]) -> void:
	var receiver := _receiver(node)
	if receiver == null or receiver in seen or not receiver.has_method("add_lift"):
		return
	seen.append(receiver)
	var scale := 1.0
	if receiver.has_method("air_push_scale"):
		scale = receiver.air_push_scale()
	receiver.add_lift(direction, speed * scale, accel * scale)
