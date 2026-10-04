extends Node

const LEVELS: Array[PackedScene] = [
	preload("res://scenes/level_1.tscn"),
	preload("res://scenes/level_2.tscn"),
	preload("res://scenes/level_3.tscn"),
]
const TITLE_SCENE := "res://scenes/title.tscn"
const FINAL_SCENE := "res://final.tscn"
const LOGO := preload("res://Assets/images/tanpopo_test.png")
const LOGO_WAVE := preload("res://drift.gdshader")
const LOGO_SCALE := 0.5
## Texture pixel where the Japanese subtitle starts, so the lines share that left edge.
const LOGO_INK_LEFT := 148.0
const CREDIT_LINES: Array[Dictionary] = [
	{"text": "Daniel", "size": 40, "gap": 14.0, "name": true},
	{"text": "Official Soundtrack + SFX", "size": 26, "gap": 6.0},
	{"text": "Programming", "size": 26, "gap": 6.0},
	{"text": "Environmental Art", "size": 26, "gap": 6.0},
	{"text": "Cutscene Coloring/Shading", "size": 26, "gap": 48.0},
	{"text": "Edy", "size": 40, "gap": 14.0, "name": true},
	{"text": "Character Sprites", "size": 26, "gap": 6.0},
	{"text": "Cutscene Animations", "size": 26, "gap": 6.0},
	{"text": "Programming", "size": 26, "gap": 48.0},
	{"text": "Matthew", "size": 40, "gap": 14.0, "name": true},
	{"text": "Programming", "size": 26, "gap": 6.0},
	{"text": "Level Design", "size": 26, "gap": 6.0},
	{"text": "Mechanic Implementation", "size": 26, "gap": 6.0},
	{"text": "Game Physics", "size": 26, "gap": 64.0},
	{"text": "Thank you so much for playing!", "size": 34, "gap": 0.0},
]
const InputSetup = preload("res://scripts/input_setup.gd")
const MEMORY_FRAME := preload("res://shaders/memory_frame.gdshader")
const SEED_GLOW := preload("res://shaders/seed_glow.gdshader")
const WHITE_KEY := preload("res://shaders/white_key.gdshader")
const SEED_TEX := preload("res://Assets/images/seed_rough.png")
const SeedScript = preload("res://scripts/drifting_object.gd")
const POOF_SFX := preload("res://Assets/sfx/freesound_community-poof-of-smoke-87381.mp3")

## How long the black between stages takes to arrive and clear.
const FADE_OUT_TIME := 1.9
const FADE_IN_TIME := 1.6
## Extra black after the fade-out, before the memories flash, and after they finish, before the next stage fades in.
const MEMORY_PAUSE_BEFORE := 0.9
const MEMORY_PAUSE_AFTER := 1.2
## Day cliff reveal, then the fade back to the title after the credits clear.
const ENDING_FADE_IN := 3.4
const ENDING_FADE_OUT := 2.8
const CREDITS_ROLL_SPEED := 42.0

const MEMORIES_PER_STAGE := 3
## One memory per seed, in play order: level 1 is 1–3, level 2 is 4–6, level 3 is 7–9.
const STAGE_MEMORIES: Array[Texture2D] = [
	preload("res://Assets/images/memories/memory 1.png"),
	preload("res://Assets/images/memories/memory 2.png"),
	preload("res://Assets/images/memories/memory 3.png"),
	preload("res://Assets/images/memories/memory 4.png"),
	preload("res://Assets/images/memories/memory 5.png"),
	preload("res://Assets/images/memories/memory 6.png"),
	preload("res://Assets/images/memories/memory 7.png"),
	preload("res://Assets/images/memories/memory 8.png"),
	preload("res://Assets/images/memories/memory 9.png"),
]

@onready var world: Node = $World
@onready var fade: ColorRect = $UI/Fade
@onready var line_box: Control = $UI/LineBox

var _fade_tween: Tween
var _credits_tween: Tween
var _poof: AudioStreamPlayer
var _current_room: Node
var _level := 0
var _play_token := 0


func _ready() -> void:
	InputSetup.ensure()
	_poof = AudioStreamPlayer.new()
	_poof.name = "MemoryPoof"
	_poof.stream = POOF_SFX
	_poof.volume_db = 6.0
	add_child(_poof)
	line_box.visible = false
	if get_tree().has_meta("drift_play_credits"):
		get_tree().remove_meta("drift_play_credits")
		fade.color = Color.WHITE
		fade.modulate.a = 1.0
		_play_ending(_play_token)
		return
	fade.color = Color.BLACK
	var from_black := get_tree().has_meta("fade_from_black")
	if from_black:
		get_tree().remove_meta("fade_from_black")
	fade.modulate.a = 1.0 if from_black else 0.0
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


## Over the black fade between stages, flash the memories one by one, blurred and
## framed by an inky organic border.
func _flash_memories(token: int) -> void:
	if STAGE_MEMORIES.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.name = "MemoryFlash"
	layer.layer = 11
	add_child(layer)
	# Picture on the left, the matching seed in a gutter on the right.
	var vp := get_viewport().get_visible_rect().size
	var inset := minf(vp.x, vp.y) * 0.06
	var art := SEED_TEX.get_size()
	var seed_h := vp.y * 0.5
	var seed_w := seed_h * art.x / maxf(art.y, 1.0)
	var gutter := seed_w + inset
	var flash := Control.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.modulate.a = 0.0
	layer.add_child(flash)
	var rect := TextureRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.offset_left = inset
	rect.offset_top = inset
	rect.offset_right = -(gutter + inset * 0.35)
	rect.offset_bottom = -inset
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = MEMORY_FRAME
	mat.set_shader_parameter("blur_amount", 0.26)
	mat.set_shader_parameter("saturation", 0.06)
	var frame_size := Vector2(vp.x - inset - gutter - inset * 0.35, vp.y - inset * 2.0)
	mat.set_shader_parameter("rect_size", frame_size)
	rect.material = mat
	flash.add_child(rect)
	var seed_pos := Vector2(vp.x - inset - seed_w, (vp.y - seed_h) * 0.5)
	var puff := seed_pos + Vector2(seed_w * 0.5, seed_h * 0.22)
	var glow_px := seed_w * 1.35
	var glow := TextureRect.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.texture = SeedScript.glow_texture()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.position = puff - Vector2(glow_px, glow_px) * 0.5
	glow.size = Vector2(glow_px, glow_px)
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = SEED_GLOW
	glow.material = glow_mat
	flash.add_child(glow)
	var seed := TextureRect.new()
	seed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seed.texture = SEED_TEX
	seed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seed.stretch_mode = TextureRect.STRETCH_SCALE
	seed.position = seed_pos
	seed.size = Vector2(seed_w, seed_h)
	var seed_mat := ShaderMaterial.new()
	seed_mat.shader = WHITE_KEY
	seed_mat.set_shader_parameter("cutoff", 0.988)
	seed.material = seed_mat
	flash.add_child(seed)
	var stage_start := _level * MEMORIES_PER_STAGE
	var stage_count := mini(MEMORIES_PER_STAGE, maxi(STAGE_MEMORIES.size() - stage_start, 0))
	for i in stage_count:
		if token != _play_token or not is_inside_tree():
			break
		var slot := stage_start + i
		rect.texture = STAGE_MEMORIES[slot]
		# Vary the border noise so each memory frame looks a little different.
		mat.set_shader_parameter("seed", float(slot) * 7.3)
		var color: Color = SeedScript.rainbow_color(slot)
		var halo := color
		halo.a = 0.16
		glow_mat.set_shader_parameter("glow_color", halo)
		seed.self_modulate = color.lerp(Color.WHITE, 0.78)
		flash.modulate.a = 0.0
		if _poof:
			_poof.play()
		# Fade this memory in, hold, then fade it fully out to black before the next.
		var tween := create_tween()
		tween.tween_property(flash, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_interval(0.75)
		tween.tween_property(flash, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_interval(0.25)
		await tween.finished
	if is_instance_valid(layer):
		layer.queue_free()


func _play_level(from_black: bool) -> void:
	var token := _play_token
	# Tell the next room to bring its music/ambience up from silence as it loads.
	if from_black:
		get_tree().set_meta("drift_fade_audio_in", FADE_IN_TIME)
	var scene := _swap(LEVELS[_level])
	_current_room = scene
	if from_black:
		await _fade_to(0.0, FADE_IN_TIME)
	if token != _play_token or not is_instance_valid(scene):
		return
	scene.returned.connect(_on_level_returned, CONNECT_ONE_SHOT)


func _on_level_returned() -> void:
	_advance.call_deferred(_play_token)


func _advance(token: int) -> void:
	if token != _play_token:
		return
	if is_instance_valid(_current_room) and _current_room.has_method("fade_audio_out"):
		_current_room.fade_audio_out(FADE_OUT_TIME)
	await _fade_to(1.0, FADE_OUT_TIME)
	if token != _play_token or not is_inside_tree():
		return
	await get_tree().create_timer(MEMORY_PAUSE_BEFORE).timeout
	if token != _play_token or not is_inside_tree():
		return
	await _flash_memories(token)
	if token != _play_token or not is_inside_tree():
		return
	await get_tree().create_timer(MEMORY_PAUSE_AFTER).timeout
	if token != _play_token or not is_inside_tree():
		return
	_level += 1
	if _level >= LEVELS.size():
		await _fade_to_white(FADE_IN_TIME)
		if token != _play_token or not is_inside_tree():
			return
		get_tree().set_meta("fade_from_white", true)
		get_tree().change_scene_to_file(FINAL_SCENE)
		return
	await _play_level(true)


## After the last stage: day cliff, camera held on the opening frame, credits rising
## from behind the rock, then a fade out to the title.
func _play_ending(token: int) -> void:
	get_tree().set_meta("drift_hold_start", true)
	get_tree().set_meta("drift_fade_audio_in", ENDING_FADE_IN)
	var scene := _swap(LEVELS[0])
	_current_room = scene
	if is_instance_valid(scene):
		scene.set("time_of_day", 0)
		_show_credits_pose(scene)
	if token != _play_token or not is_inside_tree():
		return
	var credits := _build_credits(scene)
	if not await _fade_unless(0.0, ENDING_FADE_IN, token):
		return
	await get_tree().create_timer(0.7).timeout
	if token != _play_token or not is_inside_tree():
		return
	if not await _roll_credits(credits, token):
		return
	await get_tree().create_timer(0.8).timeout
	if token != _play_token or not is_inside_tree():
		return
	if is_instance_valid(scene) and scene.has_method("fade_audio_out"):
		scene.fade_audio_out(ENDING_FADE_OUT)
	if not await _fade_unless(1.0, ENDING_FADE_OUT, token):
		return
	get_tree().set_meta("fade_from_black", true)
	get_tree().change_scene_to_file(TITLE_SCENE)


## Credits use the bench pose. The running girl stays hidden, and the bench sprite stays hidden in play.
func _show_credits_pose(room: Node) -> void:
	var peppermint := room.get_node_or_null("Peppermint")
	if peppermint:
		var visual := peppermint.get_node_or_null("Visual")
		if visual:
			visual.visible = false
		var seeds := peppermint.get_node_or_null("SeedParti")
		if seeds:
			seeds.visible = false
	var sitting := room.get_node_or_null("SittingOnBench")
	if sitting:
		sitting.visible = true


func _build_credits(room: Node) -> Node2D:
	var platform := room.get_node("Platform") as Node2D
	var camera := room.get_node("Peppermint/Camera2D") as Camera2D
	var cliff := platform.get_node("Cliff") as Sprite2D
	var center := camera.get_screen_center_position()
	var half_view := get_viewport().get_visible_rect().size * 0.5 / camera.zoom
	var cliff_scale := absf(cliff.global_scale.y)
	var cliff_top := cliff.global_position.y - cliff.texture.get_height() * cliff_scale * 0.5
	var root := Node2D.new()
	root.name = "Credits"
	# Behind the cliff (z 1) and the traveler, in front of the distant clouds.
	root.z_index = -6
	platform.add_child(root)
	var width := 880.0
	var logo_h := LOGO.get_height() * LOGO_SCALE
	var logo_w := LOGO.get_width() * LOGO_SCALE
	var logo_left := -logo_w * 0.5 + LOGO_INK_LEFT * LOGO_SCALE
	var logo := Sprite2D.new()
	logo.texture = LOGO
	logo.centered = true
	logo.scale = Vector2(LOGO_SCALE, LOGO_SCALE)
	logo.position = Vector2(0, logo_h * 0.5)
	var wave := ShaderMaterial.new()
	wave.shader = LOGO_WAVE
	wave.set_shader_parameter("wave_speed", 1.5)
	wave.set_shader_parameter("wave_freq", 10.0)
	wave.set_shader_parameter("wave_width", 0.2)
	logo.material = wave
	root.add_child(logo)
	var y := logo_h + 56.0
	for line: Dictionary in CREDIT_LINES:
		var label := Label.new()
		var size := int(line["size"])
		label.text = str(line["text"])
		label.position = Vector2(logo_left, y)
		label.size = Vector2(width, float(size) + 18.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", size)
		var is_name := bool(line.get("name", false))
		if is_name:
			label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.78))
		else:
			label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color(0.18, 0.2, 0.24, 0.55))
		label.add_theme_constant_override("outline_size", 10)
		label.add_theme_constant_override("font_spacing_glyph", 4)
		root.add_child(label)
		y += float(size) + float(line["gap"])
	# First line starts under the grass lip, so the roll climbs out from behind the cliff.
	# Shifted right so the column sits in the open sky beside her.
	root.global_position = Vector2(center.x + 200.0, cliff_top + 36.0)
	root.set_meta("end_top", center.y - half_view.y - y - 36.0)
	return root


func _roll_credits(root: Node2D, token: int) -> bool:
	if not is_instance_valid(root):
		return false
	var end_top := float(root.get_meta("end_top"))
	var distance := root.global_position.y - end_top
	if distance < 1.0:
		return token == _play_token
	if _credits_tween and _credits_tween.is_valid():
		_credits_tween.kill()
	_credits_tween = create_tween()
	_credits_tween.tween_property(root, "global_position:y", end_top, distance / CREDITS_ROLL_SPEED).set_trans(Tween.TRANS_LINEAR)
	while _credits_tween.is_valid() and _credits_tween.is_running():
		if token != _play_token or not is_inside_tree():
			_credits_tween.kill()
			return false
		await get_tree().process_frame
	return token == _play_token and is_inside_tree()


func _fade_unless(target: float, duration: float, token: int) -> bool:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade, "modulate:a", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	while _fade_tween.is_valid() and _fade_tween.is_running():
		if token != _play_token or not is_inside_tree():
			_fade_tween.kill()
			return false
		await get_tree().process_frame
	return token == _play_token and is_inside_tree()


func _debug_select(index: int) -> void:
	_play_token += 1
	_level = clampi(index, 0, LEVELS.size() - 1)
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	if _credits_tween and _credits_tween.is_valid():
		_credits_tween.kill()
	if get_tree().has_meta("drift_fade_audio_in"):
		get_tree().remove_meta("drift_fade_audio_in")
	if get_tree().has_meta("drift_hold_start"):
		get_tree().remove_meta("drift_hold_start")
	fade.modulate.a = 0.0
	line_box.visible = false
	var scene := _swap(LEVELS[_level])
	_current_room = scene
	if is_instance_valid(scene):
		scene.returned.connect(_on_level_returned, CONNECT_ONE_SHOT)


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


## The screen is already black after the last memories. Ease that black into white.
func _fade_to_white(duration: float) -> void:
	fade.modulate.a = 1.0
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade, "color", Color.WHITE, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _fade_tween.finished
