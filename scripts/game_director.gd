extends Node

const LEVELS: Array[PackedScene] = [
	preload("res://scenes/level_1.tscn"),
	preload("res://scenes/level_2.tscn"),
	preload("res://scenes/level_3.tscn"),
]
const InputSetup = preload("res://scripts/input_setup.gd")

@onready var world: Node = $World
@onready var fade: ColorRect = $UI/Fade
@onready var line_box: Control = $UI/LineBox

var _fade_tween: Tween
var _level := 0


func _ready() -> void:
	InputSetup.ensure()
	fade.color = Color.BLACK
	fade.modulate.a = 0.0
	line_box.visible = false
	_play_level(false)


func present_line() -> void:
	await _fade_to(1.0, 1.2)
	if not is_inside_tree():
		return
	line_box.visible = true
	await get_tree().create_timer(2.8).timeout
	if not is_inside_tree():
		return
	line_box.visible = false


func _play_level(from_black: bool) -> void:
	var scene := _swap(LEVELS[_level])
	if from_black:
		await _fade_to(0.0, 1.15)
	if not is_instance_valid(scene):
		return
	scene.returned.connect(_on_level_returned, CONNECT_ONE_SHOT)


func _on_level_returned() -> void:
	_advance.call_deferred()


func _advance() -> void:
	await _fade_to(1.0, 1.2)
	if not is_inside_tree():
		return
	_level += 1
	if _level >= LEVELS.size():
		_level = 0
		await present_line()
		if not is_inside_tree():
			return
	await _play_level(true)


func _swap(packed: PackedScene) -> Node:
	var old: Array[Node] = []
	for child in world.get_children():
		old.append(child)
	for child in old:
		world.remove_child(child)
		child.queue_free()
	var node := packed.instantiate()
	world.add_child(node)
	return node


func _fade_to(target: float, duration: float) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade, "modulate:a", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _fade_tween.finished
