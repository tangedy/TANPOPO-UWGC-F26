extends Node2D

## 1 matches the world. Lower sits farther back, higher rushes past in front.
@export var scroll_scale := Vector2(0.4, 0.4)
## When on, overlapping sprites in this layer fade so the traveler stays readable behind them.
@export var fade_when_covering := false
@export_range(0.05, 1.0, 0.01) var covered_alpha := 0.65
@export var fade_speed := 6.0
## Shrink the cloud bounds used for overlap, as a fraction of size, to skip empty texture padding.
@export_range(0.0, 0.45, 0.01) var cover_inset := 0.18

var _origin := Vector2.ZERO
var _cam_origin := Vector2.ZERO
var _rest_alpha: Dictionary = {}


func _ready() -> void:
	_origin = position
	var cam := get_viewport().get_camera_2d()
	if cam:
		_cam_origin = cam.get_screen_center_position()
	for child in get_children():
		var sprite := child as CanvasItem
		if sprite:
			_rest_alpha[sprite.get_instance_id()] = sprite.modulate.a


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam:
		var cam_delta := cam.get_screen_center_position() - _cam_origin
		position = _origin + cam_delta * (Vector2.ONE - scroll_scale)
	if fade_when_covering:
		_fade_covering_clouds(delta)


func _fade_covering_clouds(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var body := Rect2()
	var has_body := false
	if player and player.has_method("body_rect"):
		body = player.body_rect()
		has_body = true
	var rate := 1.0 - exp(-fade_speed * delta)
	for child in get_children():
		var sprite := child as Sprite2D
		if sprite == null:
			continue
		var rest: float = _rest_alpha.get(sprite.get_instance_id(), sprite.modulate.a)
		var covering := has_body and _sprite_aabb(sprite).intersects(body)
		var goal := covered_alpha if covering else rest
		var color := sprite.modulate
		color.a = lerpf(color.a, goal, rate)
		sprite.modulate = color


func _sprite_aabb(sprite: Sprite2D) -> Rect2:
	var local := sprite.get_rect()
	var inset := local.size * cover_inset
	local = local.grow_individual(-inset.x * 0.5, -inset.y * 0.5, -inset.x * 0.5, -inset.y * 0.5)
	var xf := sprite.global_transform
	var p0: Vector2 = xf * local.position
	var p1: Vector2 = xf * (local.position + Vector2(local.size.x, 0.0))
	var p2: Vector2 = xf * (local.position + local.size)
	var p3: Vector2 = xf * (local.position + Vector2(0.0, local.size.y))
	var min_p := p0.min(p1).min(p2).min(p3)
	var max_p := p0.max(p1).max(p2).max(p3)
	return Rect2(min_p, max_p - min_p)
