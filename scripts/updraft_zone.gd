@tool
extends Area2D

## Upward speed of the one gust fired when the traveler is fully inside.
## Tuned so the arc crests at the top of the tall platform.
@export var lift_speed := 200.0
@export var zone_size := Vector2(16000, 700):
	set(value):
		zone_size = value
		_apply_zone_size()

## Padding so the rising lines fade out instead of clipping on the quad.
const VISUAL_MARGIN := Vector2(48.0, 80.0)

var _launched := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 6
	monitoring = true
	monitorable = false
	var visual := get_node_or_null("WindVisual") as ColorRect
	if visual != null and visual.material != null:
		visual.material = visual.material.duplicate()
	_apply_zone_size()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
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
	if shape_node != null:
		var rect := RectangleShape2D.new()
		rect.size = zone_size
		shape_node.shape = rect
	var visual := get_node_or_null("WindVisual") as ColorRect
	if visual == null:
		return
	var rect_size := zone_size + VISUAL_MARGIN * 2.0
	visual.position = -rect_size * 0.5
	visual.size = rect_size
	var mat := visual.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("zone_size", zone_size)
	mat.set_shader_parameter("rect_size", rect_size)
	mat.set_shader_parameter("upward", 1.0)
	mat.set_shader_parameter("line_gap", 3.5)
	mat.set_shader_parameter("curve", 0.0)
	mat.set_shader_parameter("active", 1.0)
	mat.set_shader_parameter("fill_mode", 1.0)
	var flow := lerpf(70.0, 150.0, clampf(lift_speed / 800.0, 0.0, 1.0))
	mat.set_shader_parameter("flow_speed", flow)
