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
var _play_token := 0
var _debug_buttons: Array[Button] = []


func _ready() -> void:
	InputSetup.ensure()
	fade.color = Color.BLACK
	var from_black := get_tree().has_meta("fade_from_black")
	if from_black:
		get_tree().remove_meta("fade_from_black")
	fade.modulate.a = 1.0 if from_black else 0.0
	line_box.visible = false
	_build_level_debug()
	_play_level(from_black)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.physical_keycode != KEY_L:
		return
	_debug_select((_level + 1) % LEVELS.size())
	get_viewport().set_input_as_handled()


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
	var token := _play_token
	var scene := _swap(LEVELS[_level])
	_refresh_level_debug()
	if from_black:
		await _fade_to(0.0, 1.15)
	if token != _play_token or not is_instance_valid(scene):
		return
	scene.returned.connect(_on_level_returned, CONNECT_ONE_SHOT)


func _on_level_returned() -> void:
	_advance.call_deferred(_play_token)


func _advance(token: int) -> void:
	if token != _play_token:
		return
	await _fade_to(1.0, 1.2)
	if token != _play_token or not is_inside_tree():
		return
	_level += 1
	if _level >= LEVELS.size():
		_level = 0
		await present_line()
		if token != _play_token or not is_inside_tree():
			return
	await _play_level(true)


func _build_level_debug() -> void:
	var bar := HBoxContainer.new()
	bar.name = "LevelDebug"
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -430.0
	bar.offset_top = 16.0
	bar.offset_right = -16.0
	bar.offset_bottom = 52.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(bar)
	var hint := Label.new()
	hint.text = "L"
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	bar.add_child(hint)
	for i in LEVELS.size():
		var button := Button.new()
		button.text = str(i + 1)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_debug_select.bind(i))
		bar.add_child(button)
		_debug_buttons.append(button)
	_refresh_level_debug()


func _debug_select(index: int) -> void:
	_play_token += 1
	_level = clampi(index, 0, LEVELS.size() - 1)
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	fade.modulate.a = 0.0
	line_box.visible = false
	var scene := _swap(LEVELS[_level])
	_refresh_level_debug()
	if is_instance_valid(scene):
		scene.returned.connect(_on_level_returned, CONNECT_ONE_SHOT)


func _refresh_level_debug() -> void:
	for i in _debug_buttons.size():
		var button := _debug_buttons[i]
		button.modulate = Color(1, 1, 1, 1) if i == _level else Color(1, 1, 1, 0.55)


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
