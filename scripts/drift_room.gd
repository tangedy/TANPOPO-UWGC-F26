extends Node2D

signal returned

const InputSetup = preload("res://scripts/input_setup.gd")
const PathTrail = preload("res://scripts/path_debug.gd")
const DAY_MUSIC := preload("res://Assets/music/drift_day.wav")
const AFTERNOON_MUSIC := preload("res://Assets/music/drift_afternoon.wav")
const NIGHT_MUSIC := preload("res://Assets/music/drift_night.wav")

enum TimeOfDay { DAY, AFTERNOON, SUNSET, NIGHT }

@export var required_collectibles := 3
@export var time_of_day: TimeOfDay = TimeOfDay.DAY:
	set(value):
		time_of_day = value
		if is_inside_tree():
			_apply_time_of_day()

const _SKY := {
	TimeOfDay.DAY: Color(0.690196, 0.878431, 0.917647, 1),
	TimeOfDay.AFTERNOON: Color(0.96, 0.74, 0.48, 1),
	TimeOfDay.SUNSET: Color(0.93, 0.48, 0.36, 1),
	TimeOfDay.NIGHT: Color(0.05, 0.07, 0.16, 1),
}
const _TINT := {
	TimeOfDay.DAY: Color(1, 1, 1, 1),
	TimeOfDay.AFTERNOON: Color(1.0, 0.86, 0.66, 1),
	TimeOfDay.SUNSET: Color(1.0, 0.72, 0.52, 1),
	TimeOfDay.NIGHT: Color(0.38, 0.42, 0.68, 1),
}
var collected := 0

const _AUDIO_SILENT_DB := -80.0
var _ending := false
var _chase := false
var _listen_for_chase := false
var _music_base_db := 0.0
var _ambience_base_db := 0.0
var _pending_fade_in := -1.0
var _audio_tween: Tween
var _exit_trails: Array[Path2D] = []
var _exit_clocks: Array[float] = []
var _exit_live: Array[bool] = []
const _EXIT_STREAK_COUNT := 3
const _EXIT_STREAK_TIME := 5.2
## How far right of the cliff lip still counts. She can finish before her body touches the edge.
const _EXIT_LIP_REACH := 640.0
const _EXIT_LIP_PAST := 180.0

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
	# Capture authored volumes and, if the director is fading us in, pre-mute the
	# music/ambience here (before their autoplay) so there's no full-volume blip.
	var music_node := get_node_or_null("Music")
	if music_node:
		_music_base_db = music_node.volume_db
	var ambience_node := get_node_or_null("Music/Ambience")
	if ambience_node:
		_ambience_base_db = ambience_node.volume_db
	var tree := get_tree()
	if tree and tree.has_meta("drift_fade_audio_in"):
		_pending_fade_in = float(tree.get_meta("drift_fade_audio_in"))
		tree.remove_meta("drift_fade_audio_in")
		if music_node:
			music_node.volume_db = _AUDIO_SILENT_DB
		if ambience_node:
			ambience_node.volume_db = _AUDIO_SILENT_DB


func _ready() -> void:
	_apply_time_of_day()
	if _pending_fade_in >= 0.0:
		fade_audio_in(_pending_fade_in)
		_pending_fade_in = -1.0
	InputSetup.ensure()
	glow.visible = false
	completion_area.monitoring = false
	completion_area.monitorable = false
	prompt.visible = false
	set_process_unhandled_input(true)
	if get_tree().has_meta("fade_from_white"):
		get_tree().remove_meta("fade_from_white")
		_fade_from_color(Color.WHITE, 0.9)
	elif get_tree().has_meta("fade_from_black"):
		get_tree().remove_meta("fade_from_black")
		_fade_from_color(Color.BLACK, 0.55)
	_opening()


func _process(delta: float) -> void:
	_advance_exit_streak(delta)
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
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		if key.physical_keycode == KEY_K:
			debug_collect_all()
			get_viewport().set_input_as_handled()
		elif key.physical_keycode == KEY_R:
			debug_teleport_start()
			get_viewport().set_input_as_handled()


## Debug: send Peppermint back to the cliff start so you can retry a stage.
func debug_teleport_start() -> void:
	if peppermint and peppermint.has_method("teleport_to_start"):
		peppermint.teleport_to_start()


## Debug: instantly fill the stage's seed meter so you can skip collecting and head to the box.
func debug_collect_all() -> void:
	if _ending:
		return
	# Clear any seeds still drifting so they don't linger once the meter is filled.
	for seed_node in get_tree().get_nodes_in_group("seed"):
		if is_instance_valid(seed_node) and seed_node.get("collected") != true:
			seed_node.set("collected", true)
			seed_node.visible = false
	while collected < required_collectibles:
		note_collected()


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
	match time_of_day:
		TimeOfDay.DAY:
			_play_music(DAY_MUSIC)
		TimeOfDay.AFTERNOON:
			_play_music(AFTERNOON_MUSIC if name == "Level 2" else DAY_MUSIC)
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


## Ease this room's music and ambience up from silence (called as the stage loads).
func fade_audio_in(duration: float) -> void:
	_tween_audio(_music_base_db, _ambience_base_db, duration)


## Ease this room's music and ambience down to silence (called as the stage exits).
func fade_audio_out(duration: float) -> void:
	_tween_audio(_AUDIO_SILENT_DB, _AUDIO_SILENT_DB, duration)


func _tween_audio(music_db: float, ambience_db: float, duration: float) -> void:
	if _audio_tween and _audio_tween.is_valid():
		_audio_tween.kill()
	_audio_tween = create_tween().set_parallel(true)
	if music:
		_audio_tween.tween_property(music, "volume_db", music_db, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var ambience_node := get_node_or_null("Music/Ambience")
	if ambience_node:
		_audio_tween.tween_property(ambience_node, "volume_db", ambience_db, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _fade_from_color(color: Color, duration: float) -> void:
	SceneCurtain.fade_out(duration)
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
	# Credits ending: stay on the cliff instead of running off it.
	if get_tree().has_meta("drift_hold_start"):
		get_tree().remove_meta("drift_hold_start")
		set_process_unhandled_input(false)
		for child in $UI.get_children():
			child.visible = false
		if peppermint and peppermint.has_method("hold_at_start"):
			peppermint.hold_at_start()
		return
	# Start running immediately so she is already mid-chase while the white fade clears.
	if peppermint.has_method("start_run"):
		peppermint.start_run()


func note_collected() -> void:
	collected += 1
	if collected < required_collectibles:
		return
	_begin_exit_trail()
func _physics_process(_delta: float) -> void:
	if _ending or collected < required_collectibles:
		return
	var body := peppermint as Node2D
	var lip := _cliff_lip()
	if body == null or lip == Vector2.INF:
		return
	var pos := body.global_position
	var on_the_left := pos.x <= lip.x + _EXIT_LIP_REACH and pos.x >= lip.x - _EXIT_LIP_PAST
	var dy := pos.y - lip.y
	var at_the_grass := dy >= -280.0 and dy <= 80.0
	if not on_the_left or not at_the_grass:
		return
	_ending = true
	_open_left_edge()
	if body.has_method("begin_exit_walk"):
		body.begin_exit_walk(lip.y)
	returned.emit()


## Once every seed is collected, curved wind streaks drift off screen toward the exit.
func _begin_exit_trail() -> void:
	if not _exit_trails.is_empty():
		return
	if _cliff_lip() == Vector2.INF:
		return
	var stagger := 0.35
	for i in _EXIT_STREAK_COUNT:
		var trail := Path2D.new()
		trail.name = "ExitWind%d" % i
		# She is z -5. Keep the gusts just behind her, above the distant clouds.
		trail.z_index = -6
		trail.set_script(PathTrail)
		trail.set("close_loop", false)
		trail.set("trail_alpha", 0.62)
		trail.set("trail_count", 1)
		trail.set("trail_length", 720.0)
		trail.set("flow_speed", 180.0)
		trail.set("line_width", 16.0)
		trail.set("tail_soft", 0.42)
		trail.set("manual_head", 2.0)
		add_child(trail)
		_exit_trails.append(trail)
		_exit_clocks.append(-stagger * float(i))
		_exit_live.append(false)


## Each gust starts at the girl, then travels on its own. The next one starts wherever she is then.
func _advance_exit_streak(delta: float) -> void:
	if _exit_trails.is_empty() or _ending:
		return
	for i in _exit_trails.size():
		var trail := _exit_trails[i]
		_exit_clocks[i] += delta
		if not _exit_live[i]:
			if _exit_clocks[i] < 0.0:
				continue
			_exit_live[i] = true
			_exit_clocks[i] = 0.0
			_launch_exit_streak(trail, i)
		elif _exit_clocks[i] >= _EXIT_STREAK_TIME:
			_exit_clocks[i] = 0.0
			_launch_exit_streak(trail, i)
		trail.set("manual_head", clampf(_exit_clocks[i] / _EXIT_STREAK_TIME, 0.0, 1.0))


func _launch_exit_streak(trail: Path2D, index: int) -> void:
	var body := peppermint as Node2D
	var lip := _cliff_lip()
	if body == null or lip == Vector2.INF:
		return
	var cam := body.get_node_or_null("Camera2D") as Camera2D
	var zoom := cam.zoom.x if cam != null else 0.5
	var view := get_viewport().get_visible_rect().size / maxf(zoom, 0.05)
	var visual := body.get_node_or_null("Visual") as Node2D
	var start := visual.global_position if visual != null else body.global_position
	var end := Vector2(lip.x - view.x * 0.55, lip.y - view.y * 0.28)
	var span := absf(start.x - end.x)
	var handle := Vector2(-span * 0.16, 0.0)
	var sway := view.y * 0.07
	var curve := Curve2D.new()
	for n in 4:
		var t := float(n) / 3.0
		var point := start.lerp(end, t)
		if n != 0:
			point.y += sin(t * PI * 1.5 + float(index) * 1.4) * sway
		curve.add_point(point, -handle, handle)
	trail.global_position = Vector2.ZERO
	trail.curve = curve
	trail.set("manual_head", 0.0)


## Left end of the cliff top, in world space. The return is this lip, not the yellow box.
func _cliff_lip() -> Vector2:
	var platform := get_node_or_null("Platform") as Node2D
	if platform == null:
		return Vector2.INF
	var poly := platform.get_node_or_null("FloorCollider") as CollisionPolygon2D
	if poly == null or poly.polygon.is_empty():
		return Vector2.INF
	var top_y := poly.polygon[0].y
	for point in poly.polygon:
		top_y = minf(top_y, point.y)
	var left := Vector2(INF, top_y)
	for point in poly.polygon:
		if absf(point.y - top_y) <= 30.0 and point.x < left.x:
			left = point
	return platform.to_global(left)


## The side wall sits on the lip. Drop it so she can run off the grass.
func _open_left_edge() -> void:
	var platform := get_node_or_null("Platform") as Node2D
	if platform == null:
		return
	var left_shape: CollisionShape2D = null
	var left_x := INF
	for child in platform.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null:
			continue
		var rect := shape_node.shape as RectangleShape2D
		if rect == null or rect.size.y <= rect.size.x:
			continue
		if shape_node.position.x < left_x:
			left_x = shape_node.position.x
			left_shape = shape_node
	if left_shape:
		left_shape.disabled = true
