extends Node2D

const DRIFT := "res://scenes/drift.tscn"
## Point in the intro animation (seconds) where the white fade-out to drift begins.
const DRIFT_CUE := 30.0
const FADE_IN_TIME := 0.9
const WHITE_FADE_TIME := 1.2

@onready var anim: AnimationPlayer = $AnimationPlayer

var _leaving := false


func _ready() -> void:
	if get_tree().has_meta("fade_from_black"):
		get_tree().remove_meta("fade_from_black")
		_fade_from_black(FADE_IN_TIME)


func _process(_delta: float) -> void:
	if _leaving:
		return
	if anim.is_playing() and anim.current_animation_position >= DRIFT_CUE:
		_leaving = true
		_go_to_drift()


func _go_to_drift() -> void:
	await _fade_white(WHITE_FADE_TIME)
	get_tree().set_meta("fade_from_white", true)
	get_tree().change_scene_to_file(DRIFT)


func _fade_from_black(duration: float) -> void:
	var rect := _make_overlay(Color.BLACK)
	rect.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(rect, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	rect.get_parent().queue_free()


func _fade_white(duration: float) -> void:
	var rect := _make_overlay(Color.WHITE)
	rect.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(rect, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


func _make_overlay(color: Color) -> ColorRect:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	return rect
