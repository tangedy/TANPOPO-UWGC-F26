extends Control

const INTRO := "res://shaders/intro.tscn"
const OUTLINE_SIZE := 20
const ARROW_GAP := -8.0

@onready var music: AudioStreamPlayer = $Music
@onready var arrow: Sprite2D = $DriftArrow
@onready var play_button: Button = $Play
@onready var exit_button: Button = $Exit
@onready var hover_sfx: AudioStreamPlayer2D = $hover
@onready var click_sfx: AudioStreamPlayer2D = $click

var _leaving := false

func _ready() -> void:
	_loop_music()
	music.play()
	if get_tree().has_meta("fade_from_black"):
		get_tree().remove_meta("fade_from_black")
		_fade_from_black(1.8)
	for button in [play_button, exit_button]:
		button.mouse_entered.connect(_on_button_hover)
		button.mouse_entered.connect(_refresh_buttons)
		button.mouse_exited.connect(_refresh_buttons)
	play_button.pressed.connect(_on_play)
	exit_button.pressed.connect(_on_exit)
	arrow.visible = false
	_refresh_buttons()


func _on_button_hover() -> void:
	hover_sfx.play()


func _refresh_buttons() -> void:
	var active := _hovered_button()
	for button in [play_button, exit_button]:
		button.add_theme_constant_override("outline_size", OUTLINE_SIZE if button == active else 0)
	if active == null:
		arrow.visible = false
		return
	arrow.visible = true
	_place_arrow(active)


func _hovered_button() -> Button:
	if play_button.is_hovered():
		return play_button
	if exit_button.is_hovered():
		return exit_button
	return null


func _place_arrow(button: Button) -> void:
	var font := button.get_theme_font("font")
	var font_size := button.get_theme_font_size("font_size")
	var outline := float(button.get_theme_constant("outline_size"))
	var text_width := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	text_width += outline * 2.0
	var rect := button.get_global_rect()
	var center := rect.get_center()
	var visual_scale := button.offset_transform_scale if button.offset_transform_enabled else Vector2.ONE
	var pivot := rect.position + button.offset_transform_pivot + rect.size * button.offset_transform_pivot_ratio
	var unscaled_right := center + Vector2(text_width * 0.5, 0.0)
	var visual_right := pivot + (unscaled_right - pivot) * visual_scale
	var arrow_half := arrow.texture.get_size().x * absf(arrow.scale.x) * 0.5
	arrow.global_position = Vector2(visual_right.x + ARROW_GAP + arrow_half, visual_right.y)


func _loop_music() -> void:
	if music.stream is AudioStreamWAV:
		var wav := music.stream as AudioStreamWAV
		var frames := int(wav.get_length() * wav.mix_rate)
		wav.loop_begin = 0
		if frames > 1:
			wav.loop_end = frames
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD


func _on_play() -> void:
	if _leaving:
		return
	_leaving = true
	click_sfx.play()
	await _fade_black(0.45)
	get_tree().set_meta("fade_from_black", true)
	get_tree().change_scene_to_file(INTRO)


func _on_exit() -> void:
	if _leaving:
		return
	_leaving = true
	click_sfx.play()
	await get_tree().create_timer(0.12).timeout
	get_tree().quit()


func _fade_from_black(duration: float) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var tween := create_tween()
	tween.tween_property(rect, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	if is_instance_valid(layer):
		layer.queue_free()


func _fade_black(duration: float) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.modulate.a = 0.0
	layer.add_child(rect)
	var tween := create_tween()
	tween.tween_property(rect, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
