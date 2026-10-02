@tool
extends Area2D

const AirPush = preload("res://scripts/air_push.gd")

## Push strength in pixels per second squared. Direction is this node's local right.
@export_range(0.0, 2000.0, 1.0) var strength := 240.0
@export var always_active := false
## Seconds the wind blows each cycle.
@export var on_duration := 1.5
## Seconds the wind rests each cycle.
@export var off_duration := 1.5
## Seconds to wait before the first cycle.
@export var start_delay := 0.0
@export var zone_size := Vector2(260, 180):
	set(value):
		zone_size = value
		_apply_zone_size()
		queue_redraw()

var _time := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 6
	monitoring = true
	monitorable = false
	set_notify_transform(true)
	_apply_zone_size()
	update_configuration_warnings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_time += delta
	queue_redraw()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta
	queue_redraw()
	if is_blowing():
		AirPush.deliver(self, push_direction() * strength)


func push_direction() -> Vector2:
	var direction := global_transform.x
	if direction.length_squared() < 0.0001:
		return Vector2.RIGHT
	return direction.normalized()


func is_blowing() -> bool:
	if always_active:
		return true
	if on_duration <= 0.0:
		return false
	if _time < start_delay:
		return false
	var cycle := on_duration + maxf(off_duration, 0.0)
	if cycle <= 0.0:
		return false
	return fposmod(_time - start_delay, cycle) < on_duration


func _apply_zone_size() -> void:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return
	var rect := RectangleShape2D.new()
	rect.size = zone_size
	shape_node.shape = rect


func _edit_is_selected_on_click(at_position: Vector2, tolerance: float) -> bool:
	return Rect2(-zone_size * 0.5, zone_size).grow(tolerance).has_point(at_position)


func _get_configuration_warnings() -> PackedStringArray:
	if not always_active and on_duration <= 0.0:
		return PackedStringArray(["On duration is 0, so this wind never blows."])
	return PackedStringArray()


func _draw() -> void:
	var rect := Rect2(-zone_size * 0.5, zone_size)
	var active := is_blowing()
	var line := Color(0.35, 1.0, 0.25, 0.95)
	if active:
		draw_rect(rect, Color(0.2, 0.95, 0.15, 0.45), true)
	draw_rect(rect, line, false, 2.0)
	var length := clampf(28.0 + strength * 0.12, 28.0, minf(zone_size.x, zone_size.y) * 0.45)
	draw_line(Vector2.ZERO, Vector2(length, 0.0), line, 3.0, true)
	var tip := Vector2(length, 0.0)
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip + Vector2(-14, -7),
		tip + Vector2(-14, 7),
	]), line)
