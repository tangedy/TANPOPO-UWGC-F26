extends Node2D

signal returned

const InputSetup = preload("res://scripts/input_setup.gd")
const DAY_MUSIC := preload("res://Assets/music/drift_day.wav")
const NIGHT_MUSIC := preload("res://Assets/music/drift_night.wav")

enum TimeOfDay { DAY, SUNSET, NIGHT }

@export var required_collectibles := 3
@export var time_of_day: TimeOfDay = TimeOfDay.DAY:
	set(value):
		time_of_day = value
		if is_inside_tree():
			_apply_time_of_day()

const _SKY := {
	TimeOfDay.DAY: Color(0.690196, 0.878431, 0.917647, 1),
	TimeOfDay.SUNSET: Color(0.93, 0.48, 0.36, 1),
	TimeOfDay.NIGHT: Color(0.05, 0.07, 0.16, 1),
}
const _TINT := {
	TimeOfDay.DAY: Color(1, 1, 1, 1),
	TimeOfDay.SUNSET: Color(1.0, 0.72, 0.52, 1),
	TimeOfDay.NIGHT: Color(0.38, 0.42, 0.68, 1),
}
const _TIME_LABELS := {
	TimeOfDay.DAY: "Day",
	TimeOfDay.SUNSET: "Sunset",
	TimeOfDay.NIGHT: "Night",
}

var collected := 0

var _ending := false
var _chase := false
var _listen_for_chase := false
var _time_button: Button

@onready var glow: CanvasItem = $Platform/CompletionArea/Glow
@onready var completion_area: Area2D = $Platform/CompletionArea
@onready var prompt: Label = $UI/Prompt
@onready var peppermint: Node = $Peppermint
@onready var music: AudioStreamPlayer = $Music
@onready var sky: ColorRect = $Sky/ColorRect
@onready var day_night: CanvasModulate = $DayNight
@onready var moon: Node2D = $Platform/BGCloudsLayer/Moon


func _enter_tree() -> void:
	add_to_group("drift_room")


func _ready() -> void:
	_build_time_toggle()
	_build_level_label()
	_apply_time_of_day()
	InputSetup.ensure()
	glow.visible = false
	completion_area.monitoring = false
	completion_area.monitorable = false
	completion_area.collision_mask = 2
	completion_area.body_entered.connect(_on_return_body)
	prompt.visible = false
	set_process_unhandled_input(true)
	if get_tree().has_meta("fade_from_white"):
		get_tree().remove_meta("fade_from_white")
		_fade_from_color(Color.WHITE, 0.9)
	elif get_tree().has_meta("fade_from_black"):
		get_tree().remove_meta("fade_from_black")
		_fade_from_color(Color.BLACK, 0.55)
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


func _build_time_toggle() -> void:
	var button := Button.new()
	button.name = "TimeToggle"
	button.position = Vector2(16, 16)
	button.custom_minimum_size = Vector2(120, 36)
	$UI.add_child(button)
	button.pressed.connect(_cycle_time)
	_time_button = button
	_refresh_time_button()


func _build_level_label() -> void:
	var label := Label.new()
	label.name = "LevelLabel"
	label.position = Vector2(152, 20)
	label.text = name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	$UI.add_child(label)


func _cycle_time() -> void:
	time_of_day = ((int(time_of_day) + 1) % 3) as TimeOfDay


func _refresh_time_button() -> void:
	if _time_button:
		_time_button.text = _TIME_LABELS[time_of_day]


func _apply_time_of_day() -> void:
	if sky:
		sky.color = _SKY[time_of_day]
	if day_night:
		day_night.color = _TINT[time_of_day]
	if moon:
		moon.visible = time_of_day == TimeOfDay.NIGHT
		# Cancel the night tint so the disc stays bright white.
		var tint: Color = _TINT[time_of_day]
		moon.modulate = Color(
			1.05 / maxf(tint.r, 0.05),
			1.02 / maxf(tint.g, 0.05),
			0.98 / maxf(tint.b, 0.05),
			1.0
		)
	_refresh_time_button()
	match time_of_day:
		TimeOfDay.DAY:
			_play_music(DAY_MUSIC)
		TimeOfDay.NIGHT:
			_play_music(NIGHT_MUSIC)
		_:
			_play_music(null)


func _play_music(stream: AudioStream) -> void:
	if music == null:
		return
	if stream == null:
		music.stop()
		return
	if music.stream == stream and music.playing:
		return
	music.stream = stream
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		var frames := int(wav.get_length() * wav.mix_rate)
		wav.loop_begin = 0
		if frames > 1:
			wav.loop_end = frames
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	music.play()


func _fade_from_color(color: Color, duration: float) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var tween := create_tween()
	tween.tween_property(rect, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	layer.queue_free()


func _opening() -> void:
	_chase = false
	_listen_for_chase = false
	prompt.visible = false
	# Start running immediately so she is already mid-chase while the white fade clears.
	if peppermint.has_method("start_run"):
		peppermint.start_run()


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
