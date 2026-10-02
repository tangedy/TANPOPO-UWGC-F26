extends Node2D

signal returned

@export var required_collectibles := 3

var collected := 0

var _ending := false

@onready var glow: CanvasItem = $Platform/Glow
@onready var return_zone: Area2D = $Platform/ReturnZone


func _enter_tree() -> void:
	add_to_group("drift_room")


func _ready() -> void:
	glow.visible = false
	return_zone.monitoring = false
	return_zone.monitorable = false
	return_zone.collision_mask = 2
	return_zone.body_entered.connect(_on_return_body)
	queue_redraw()


func note_collected() -> void:
	collected += 1
	if collected < required_collectibles:
		return
	glow.visible = true
	return_zone.monitoring = true
	_check_return_overlap.call_deferred()


func _check_return_overlap() -> void:
	await get_tree().physics_frame
	if _ending or not is_inside_tree():
		return
	for body in return_zone.get_overlapping_bodies():
		_on_return_body(body)


func _on_return_body(body: Node) -> void:
	if _ending or collected < required_collectibles:
		return
	if body.is_in_group("player"):
		_ending = true
		returned.emit()


func _physics_process(_delta: float) -> void:
	if _ending or collected < required_collectibles or not return_zone.monitoring:
		return
	for body in return_zone.get_overlapping_bodies():
		_on_return_body(body)


func _process(_delta: float) -> void:
	if not glow.visible:
		return
	var pulse := 0.35 + 0.45 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004))
	glow.modulate = Color(1, 1, 1, pulse)


func _draw() -> void:
	var origin := Vector2(-1800, -3200)
	var cell := 160
	var blue := Color(0.36, 0.58, 0.92)
	var white := Color(0.96, 0.97, 1)
	for y in 48:
		for x in 48:
			var color := blue if (x + y) % 2 == 0 else white
			draw_rect(Rect2(origin + Vector2(x * cell, y * cell), Vector2(cell, cell)), color)
