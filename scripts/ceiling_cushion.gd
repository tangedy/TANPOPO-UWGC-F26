@tool
extends Node2D

## Width and height of the slow-down band. The top edge is where rising stops.
@export var zone_size := Vector2(9600, 800):
	set(value):
		zone_size = value
		_apply_zone_size()

@onready var visual: ColorRect = $Visual


func _enter_tree() -> void:
	add_to_group("ceiling_cushion")


func _ready() -> void:
	_apply_zone_size()
	if visual != null and not Engine.is_editor_hint():
		visual.visible = false


## Fastest rise still allowed at this point, in pixels per second.
## Negative means the point is outside the band.
func rise_limit(head: Vector2, full_speed: float) -> float:
	var rect := Rect2(global_position - zone_size * 0.5, zone_size)
	if head.x < rect.position.x or head.x > rect.end.x:
		return -1.0
	if head.y > rect.end.y:
		return -1.0
	if head.y <= rect.position.y:
		return 0.0
	var closeness := clampf(inverse_lerp(rect.end.y, rect.position.y, head.y), 0.0, 1.0)
	var eased := closeness * closeness * (3.0 - 2.0 * closeness)
	return full_speed * (1.0 - eased)


func _edit_is_selected_on_click(at_position: Vector2, tolerance: float) -> bool:
	return Rect2(-zone_size * 0.5, zone_size).grow(tolerance).has_point(at_position)


func _apply_zone_size() -> void:
	var band := get_node_or_null("Visual") as ColorRect
	if band == null:
		return
	band.position = -zone_size * 0.5
	band.size = zone_size
