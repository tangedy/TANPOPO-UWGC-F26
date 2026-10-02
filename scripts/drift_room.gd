extends Node2D

signal returned

const InputSetup = preload("res://scripts/input_setup.gd")

@export var required_collectibles := 3

var collected := 0

var _ending := false
var _chase := false
var _listen_for_chase := false

@onready var glow: CanvasItem = $Platform/CompletionArea/Glow
@onready var completion_area: Area2D = $Platform/CompletionArea
@onready var prompt: Label = $UI/Prompt
@onready var drifter: Node = $Drifter


func _enter_tree() -> void:
	add_to_group("drift_room")


func _ready() -> void:
	InputSetup.ensure()
	glow.visible = false
	completion_area.monitoring = false
	completion_area.monitorable = false
	completion_area.collision_mask = 2
	completion_area.body_entered.connect(_on_return_body)
	prompt.visible = false
	set_process_unhandled_input(true)
	_opening()


func _process(_delta: float) -> void:
	if _listen_for_chase and Input.is_action_just_pressed("chase"):
		_chase = true
	if not glow.visible:
		return
	var pulse := 0.35 + 0.45 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004))
	glow.modulate = Color(1, 1, 1, pulse)


func _unhandled_input(event: InputEvent) -> void:
	if _listen_for_chase and event.is_action_pressed("chase"):
		_chase = true
		get_viewport().set_input_as_handled()


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
	if not is_inside_tree():
		return
	prompt.visible = false
	if drifter.has_method("start_run"):
		drifter.start_run()


func note_collected() -> void:
	collected += 1
	if collected < required_collectibles:
		return
	glow.visible = true
	completion_area.monitoring = true
	_check_return_overlap.call_deferred()


func _check_return_overlap() -> void:
	await get_tree().physics_frame
	if _ending or not is_inside_tree():
		return
	for body in completion_area.get_overlapping_bodies():
		_on_return_body(body)


func _on_return_body(body: Node) -> void:
	if _ending or collected < required_collectibles:
		return
	if body.is_in_group("player"):
		_ending = true
		if body.has_method("finish"):
			body.finish()
		returned.emit()


func _physics_process(_delta: float) -> void:
	if _ending or collected < required_collectibles or not completion_area.monitoring:
		return
	for body in completion_area.get_overlapping_bodies():
		_on_return_body(body)
