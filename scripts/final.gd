extends Node2D

const GAME := "res://scenes/game.tscn"
const FADE_TIME := 1.6

@onready var anim: AnimationPlayer = $AnimationPlayer

var _cover: ColorRect
var _leaving := false


func _enter_tree() -> void:
	if get_tree().has_meta("fade_from_white"):
		_cover = _make_overlay(Color.WHITE)
		_cover.modulate.a = 1.0


func _ready() -> void:
	anim.animation_finished.connect(_on_animation_finished)
	if _cover == null:
		return
	get_tree().remove_meta("fade_from_white")
	SceneCurtain.fade_out(FADE_TIME)
	var tween := create_tween()
	tween.tween_property(_cover, "modulate:a", 0.0, FADE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	if is_instance_valid(_cover):
		_cover.get_parent().queue_free()
		_cover = null


func _on_animation_finished(anim_name: StringName) -> void:
	if _leaving or anim_name != &"anim":
		return
	_leaving = true
	_go_to_credits()


func _go_to_credits() -> void:
	var rect := _make_overlay(Color.WHITE)
	rect.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(rect, "modulate:a", 1.0, FADE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	if not is_inside_tree():
		return
	get_tree().set_meta("drift_play_credits", true)
	SceneCurtain.change_scene(GAME, Color.WHITE)


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
