@tool
extends Area2D

## Upward speed of the one gust fired when the traveler is fully inside.
## Tuned so the arc crests at the top of the tall platform.
@export var lift_speed := 300.0
@export var zone_size := Vector2(4600, 700):
	set(value):
		zone_size = value
		_apply_zone_size()
		queue_redraw()

var _launched := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 6
	monitoring = true
	monitorable = false
	set_notify_transform(true)
	_apply_zone_size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	queue_redraw()
	if lift_speed <= 0.0:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("body_rect") or not player.has_method("apply_gust"):
		return
	var bounds := Rect2(global_position - zone_size * 0.5, zone_size)
	var body: Rect2 = player.body_rect()
	var inset := Rect2(body.position + Vector2(1, 1), body.size - Vector2(2, 2))
	if bounds.encloses(inset):
		if not _launched:
			_launched = true
			player.apply_gust(lift_direction(), lift_speed)
	else:
		_launched = false


func lift_direction() -> Vector2:
	var direction := -global_transform.y
	if direction.length_squared() < 0.0001:
		return Vector2.UP
	return direction.normalized()


func _edit_is_selected_on_click(at_position: Vector2, tolerance: float) -> bool:
	return Rect2(-zone_size * 0.5, zone_size).grow(tolerance).has_point(at_position)


func _apply_zone_size() -> void:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return
	var rect := RectangleShape2D.new()
	rect.size = zone_size
	shape_node.shape = rect


func _draw() -> void:
	var rect := Rect2(-zone_size * 0.5, zone_size)
	var line := Color(0.75, 0.92, 1.0, 0.8)
	draw_rect(rect, Color(0.55, 0.82, 1.0, 0.1), true)
	draw_rect(rect, line, false, 2.0)
	var columns := 7
	if zone_size.x < 400.0:
		columns = 3
	var margin := zone_size.x * 0.08
	var span := zone_size.x - margin * 2.0
	var arrow_h := minf(zone_size.y * 0.28, 90.0)
	for i in columns:
		var x := -zone_size.x * 0.5 + margin
		if columns > 1:
			x += span * (float(i) / float(columns - 1))
		var base := Vector2(x, arrow_h * 0.5)
		var tip := Vector2(x, -arrow_h * 0.5)
		draw_line(base, tip, line, 2.0, true)
		draw_colored_polygon(PackedVector2Array([
			tip,
			tip + Vector2(-6, 12),
			tip + Vector2(6, 12),
		]), line)
