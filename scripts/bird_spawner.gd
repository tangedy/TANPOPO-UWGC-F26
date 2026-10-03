@tool
extends Node2D

## Spawns small background birds in flocks that drift left-to-right across a wide
## area (the whole level), flapping bird1/2/3. The spawn band is centered on this
## node; its outline is drawn in the editor so you can line it up with the scene.

const BIRD_SCENE = preload("res://scenes/Bird.tscn")

## Width x height of the spawn band, centered on this node.
@export var area_size := Vector2(3400, 2200):
	set(value):
		area_size = value
		queue_redraw()
## Parallax factor, matched to the BG clouds (cloud_parallax scroll_scale).
## 1 tracks the world; lower sits farther back.
@export var scroll_scale := Vector2(0.35, 0.35)
@export var spawn_interval_min := 0.7
@export var spawn_interval_max := 1.8
@export var move_speed_min := 26.0
@export var move_speed_max := 55.0
## Extra room past the band edges where birds enter/leave off-screen.
@export var edge_margin := 160.0
@export var flap_fps_min := 5.0
@export var flap_fps_max := 8.0
## Birds per flock. Kept small so the sky fills with many little groups.
@export var flock_size_min := 2
@export var flock_size_max := 4
## How loosely birds are scattered around their flock center.
@export var flock_spread := Vector2(120, 60)
## Per-bird size range (small = further in the background).
@export var scale_min := 0.28
@export var scale_max := 0.5
## Draw order for spawned birds. Background sits just in front of the far clouds.
@export var bird_z := -9
@export var tint := Color(0.88, 0.92, 1, 0.8)
## How many flocks to scatter across the band at startup.
@export_range(0, 40) var initial_flocks := 18

var _timer := 0.0
var _next_spawn := 0.0
var _origin := Vector2.ZERO
var _cam_origin := Vector2.ZERO


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	randomize()
	_origin = position
	var cam := get_viewport().get_camera_2d()
	if cam:
		_cam_origin = cam.get_screen_center_position()
	for i in initial_flocks:
		_spawn_flock(true)
	_schedule_next()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# Parallax: slide the whole spawner (and its birds) with the BG clouds.
	var cam := get_viewport().get_camera_2d()
	if cam:
		var cam_delta := cam.get_screen_center_position() - _cam_origin
		position = _origin + cam_delta * (Vector2.ONE - scroll_scale)
	_timer += delta
	if _timer >= _next_spawn:
		_spawn_flock(false)
		_schedule_next()


func _schedule_next() -> void:
	_timer = 0.0
	_next_spawn = randf_range(spawn_interval_min, spawn_interval_max)


## scattered: place the flock somewhere already inside the band (used to prefill
## the sky); otherwise the flock enters fresh from the left edge.
func _spawn_flock(scattered: bool) -> void:
	var half := area_size * 0.5
	var left_x := global_position.x - half.x
	var right_x := global_position.x + half.x

	var base_x := left_x - edge_margin
	if scattered:
		base_x = randf_range(left_x - edge_margin, right_x)
	var base_y := global_position.y + randf_range(-half.y, half.y)
	var base_speed := randf_range(move_speed_min, move_speed_max)
	var base_flap := randf_range(flap_fps_min, flap_fps_max)

	var count := randi_range(flock_size_min, flock_size_max)
	for i in count:
		var bird := BIRD_SCENE.instantiate()
		bird.z_index = bird_z
		add_child(bird)
		var offset := Vector2(
			randf_range(-flock_spread.x, flock_spread.x),
			randf_range(-flock_spread.y, flock_spread.y)
		)
		bird.global_position = Vector2(base_x, base_y) + offset
		bird.setup(
			base_speed + randf_range(-6.0, 6.0),
			right_x + edge_margin,
			base_flap + randf_range(-0.5, 0.5),
			randf_range(scale_min, scale_max)
		)
		var anim := bird.get_node_or_null("Anim") as CanvasItem
		if anim:
			anim.modulate = tint


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var half := area_size * 0.5
	draw_rect(Rect2(-half, area_size), Color(0.3, 0.7, 1.0, 0.8), false, 2.0)
