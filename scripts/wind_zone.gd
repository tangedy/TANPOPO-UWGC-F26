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

var _time := 0.0
var _active_blend := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 6
	monitoring = true
	monitorable = false
	var visual := get_node_or_null("WindVisual") as ColorRect
	if visual != null and visual.material != null:
		visual.material = visual.material.duplicate()
	_apply_zone_size()
	_update_visual(0.0)
	update_configuration_warnings()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_time += delta
	_update_visual(delta)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta
	_update_visual(delta)
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
	if shape_node != null:
		var rect := RectangleShape2D.new()
		rect.size = zone_size
		shape_node.shape = rect
	var visual := get_node_or_null("WindVisual") as ColorRect
	if visual == null:
		return
	visual.position = -zone_size * 0.5
	visual.size = zone_size
	var mat := visual.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("zone_size", zone_size)


func _edit_is_selected_on_click(at_position: Vector2, tolerance: float) -> bool:
	return Rect2(-zone_size * 0.5, zone_size).grow(tolerance).has_point(at_position)


func _get_configuration_warnings() -> PackedStringArray:
	if not always_active and on_duration <= 0.0:
		return PackedStringArray(["On duration is 0, so this wind never blows."])
	return PackedStringArray()


func _update_visual(delta: float) -> void:
	var visual := get_node_or_null("WindVisual") as ColorRect
	if visual == null:
		return
	var mat := visual.material as ShaderMaterial
	if mat == null:
		return
	var target := 1.0 if is_blowing() else 0.0
	_active_blend = move_toward(_active_blend, target, delta * 4.0)
	mat.set_shader_parameter("active", _active_blend)
	var flow := lerpf(52.0, 160.0, clampf(strength / 800.0, 0.0, 1.0))
	mat.set_shader_parameter("flow_speed", flow)
