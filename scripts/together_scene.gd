extends Node2D

signal finished

const InputSetup = preload("res://scripts/input_setup.gd")

@onready var waiter: Node2D = $Waiter
@onready var traveler: Node2D = $Traveler
@onready var prompt: Label = $UI/Prompt
@onready var camera: Camera2D = $Camera2D


var _chase := false
var _listen_for_chase := false


func _process(_delta: float) -> void:
	if _listen_for_chase and Input.is_action_just_pressed("chase"):
		_chase = true


func _unhandled_input(event: InputEvent) -> void:
	if _listen_for_chase and event.is_action_pressed("chase"):
		_chase = true
		get_viewport().set_input_as_handled()


func _ready() -> void:
	InputSetup.ensure()
	prompt.visible = false
	camera.make_current()
	set_process_unhandled_input(true)
	if get_tree().current_scene == self:
		play_opening()


func play_opening() -> void:
	_opening()


func play_reunion() -> void:
	_reunion()


func _opening() -> void:
	_chase = false
	_listen_for_chase = false
	prompt.visible = false
	await get_tree().create_timer(1.15).timeout
	if not is_inside_tree():
		return
	prompt.visible = true
	_listen_for_chase = true
	while is_inside_tree() and not _chase:
		await get_tree().process_frame
	_listen_for_chase = false
	if is_inside_tree():
		finished.emit()


func _reunion() -> void:
	prompt.visible = false
	var target := waiter.position + Vector2(46, 0)
	var tween := create_tween()
	tween.tween_property(traveler, "position", target, 1.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.85).timeout
	if not is_inside_tree():
		return
	var director := get_tree().current_scene
	if director and director.has_method("present_line"):
		await director.present_line()
	if is_inside_tree():
		finished.emit()
