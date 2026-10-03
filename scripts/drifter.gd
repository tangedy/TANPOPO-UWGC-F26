extends CharacterBody2D

const InputSetup = preload("res://scripts/input_setup.gd")
const STAND_TEX := preload("res://Assets/images/peppermint/standing_idle.png")
const RUN_FRAMES: Array[Texture2D] = [
	preload("res://Assets/images/peppermint/run_1.png"),
	preload("res://Assets/images/peppermint/run_2.png"),
	preload("res://Assets/images/peppermint/run_3.png"),
	preload("res://Assets/images/peppermint/run_4.png"),
	preload("res://Assets/images/peppermint/run_5.png"),
	preload("res://Assets/images/peppermint/run_6.png"),
]
const MOVE_A_TEX := preload("res://Assets/images/peppermint/moving_A_right.png")
const MOVE_B_TEX := preload("res://Assets/images/peppermint/moving_B_right.png")
const REACH_A_TEX := preload("res://Assets/images/peppermint/reaching_A_right.png")
const REACH_B_TEX := preload("res://Assets/images/peppermint/reaching_B_right.png")

## Run-cycle playback eases from this rate to the fast rate over the first loop.
const RUN_FPS_START := 4.0
const RUN_FPS_END := 7.0
## How many times the run cycle plays on the way to the ledge.
const RUN_CYCLES := 2.5

## Drawn height of the idle sprite, in pixels. Flight frames share that scale. Anchors shift on top.
@export var sprite_height := 156.0
## Seconds each moving or reaching frame stays up.
@export var frame_time := 0.2
## How close a seed must be before she reaches for it, in pixels.
@export var reach_range := 240.0
## Sideways speed required before a nearby seed counts as one she is moving toward.
@export var reach_speed := 20.0

@export_group("Anchors")
## Extra shift for this image after it is centered and stood on the origin. X is mirrored when she faces left.
@export var standing_anchor := Vector2.ZERO
@export var run_1_anchor := Vector2.ZERO
@export var run_2_anchor := Vector2.ZERO
@export var run_3_anchor := Vector2.ZERO
@export var run_4_anchor := Vector2.ZERO
@export var run_5_anchor := Vector2.ZERO
@export var run_6_anchor := Vector2.ZERO
@export var moving_a_anchor := Vector2.ZERO
@export var moving_b_anchor := Vector2.ZERO
@export var reaching_a_anchor := Vector2.ZERO
@export var reaching_b_anchor := Vector2.ZERO

enum State { WAIT, RUN_OFF, GLIDE, FINISHED }
enum Pose { STAND, RUN, MOVE, REACH }

@export_group("Movement")
## Downward terminal with no sideways speed, in pixels per second.
@export var fall_speed := 140.0
## Downward terminal base while S is held. Sideways speed stacks on top of this.
@export var dive_speed := 140.0
## Extra downward speed for each pixel per second sideways. 0.25 is one down per four across.
@export var sink_per_horizontal := 0.25
## Downward acceleration while falling. Drag is solved from this so the terminal stays exact.
@export var fall_gravity := 280.0
## Downward acceleration while rising, so wind and gusts arc back down.
@export var gravity := 50.0
## Fastest rise, in pixels per second. Wind and gusts cannot climb faster than this.
@export var max_up_speed := 1000.0
@export var glide_speed := 260.0
## Exponential steer rate while holding left or right. Higher reaches the target sooner.
@export var glide_accel := 4.0
## Exponential release rate when easing off or shedding extra sideways speed.
@export var glide_coast := 2.5
## How far the body leans at full glide speed, in degrees.
@export var max_lean := 12.0
## Initial run acceleration, in pixels per second squared. It eases out as she nears run speed.
@export var run_accel := 1800.0
@export var run_max_speed := 430.0
## Small hop off the platform, in pixels per second upward.
@export var leap_speed := 120.0
## Seconds of carried run speed before left/right control turns on.
@export var leap_drift_time := 1.0
## Distance between the traveler and each collected object.
@export var follow_spacing := 46.0

var state := State.WAIT
var followers: Array[Node2D] = []

var _air_push := Vector2.ZERO
var _has_lift := false
var _lift_dir := Vector2.UP
var _lift_speed := 0.0
var _lift_accel := 0.0
var _trail: Array[Vector2] = []
var _leap_point: Node2D
var _control_timer := 0.0
var _gust_pending := false
var _gust_dir := Vector2.UP
var _gust_speed := 0.0
var _pose := Pose.STAND
var _facing := 1
var _frame := 0
var _frame_clock := 0.0
var _run_cursor := 0.0
var _run_frame := 0
var _lifted := false
var _run_start_x := 0.0
## Matches the node's scale so speeds and distances stay in proportion to her size.
var _size_scale := 1.0

@onready var camera: Camera2D = $Camera2D
@onready var visual: Sprite2D = $Visual


func _enter_tree() -> void:
	add_to_group("player")


func _ready() -> void:
	InputSetup.ensure()
	collision_layer = 2
	collision_mask = 1
	_size_scale = maxf(absf(scale.x), 0.001)
	floor_snap_length = _sized(12.0)
	velocity = Vector2.ZERO
	camera.make_current()
	camera.zoom = Vector2(1.0, 1.0)
	_fit_camera_limits()
	_leap_point = get_parent().get_node_or_null("Platform/LeapPoint") as Node2D
	_apply_pose(Pose.STAND)


func _fit_camera_limits() -> void:
	var platform := get_parent().get_node_or_null("Platform") as Node2D
	if platform == null:
		return
	var found := false
	var bounds := Rect2()
	for child in platform.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null:
			continue
		var rect := shape_node.shape as RectangleShape2D
		if rect == null:
			continue
		var shape_bounds := _global_rect(shape_node, rect)
		if not found:
			bounds = shape_bounds
			found = true
		else:
			bounds = bounds.merge(shape_bounds)
	if not found:
		return
	camera.limit_left = int(floor(bounds.position.x))
	camera.limit_top = int(floor(bounds.position.y))
	camera.limit_right = int(ceil(bounds.end.x))
	camera.limit_bottom = int(ceil(bounds.end.y))


func _global_rect(shape_node: CollisionShape2D, rect: RectangleShape2D) -> Rect2:
	var xf := shape_node.global_transform
	var half := rect.size * 0.5
	var extents := Vector2(
		absf(xf.x.x) * half.x + absf(xf.y.x) * half.y,
		absf(xf.x.y) * half.x + absf(xf.y.y) * half.y
	)
	return Rect2(xf.origin - extents, extents * 2.0)


func start_run() -> void:
	if state != State.WAIT:
		return
	state = State.RUN_OFF
	velocity.x = _sized(40.0)
	_run_cursor = 0.0
	_run_frame = 0
	_run_start_x = global_position.x
	_apply_pose(Pose.RUN)


func finish() -> void:
	state = State.FINISHED
	velocity = Vector2.ZERO
	visual.rotation = 0.0
	_apply_pose(Pose.STAND)


func add_air_push(accel: Vector2) -> void:
	_air_push += accel


func add_lift(direction: Vector2, speed: float, accel: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	if not _has_lift or accel >= _lift_accel:
		_has_lift = true
		_lift_dir = direction.normalized()
		_lift_speed = speed
		_lift_accel = accel


func air_push_scale() -> float:
	return _size_scale


func body_rect() -> Rect2:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var rect_shape: RectangleShape2D = null
	if shape_node != null:
		rect_shape = shape_node.shape as RectangleShape2D
	if rect_shape == null:
		var fallback := Vector2(28, 48) * _size_scale
		return Rect2(global_position + Vector2(-14, -48) * _size_scale, fallback)
	var xf := shape_node.global_transform
	var half := rect_shape.size * 0.5
	var extents := Vector2(
		absf(xf.x.x) * half.x + absf(xf.y.x) * half.y,
		absf(xf.x.y) * half.x + absf(xf.y.y) * half.y
	)
	return Rect2(xf.origin - extents, extents * 2.0)


func apply_gust(direction: Vector2, speed: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	_gust_pending = true
	_gust_dir = direction.normalized()
	_gust_speed = _sized(speed)


func attach_follower(node: Node2D) -> void:
	if followers.has(node):
		return
	followers.append(node)
	node.z_index = 4
	_ensure_trail_length(_follow_distance(followers.size() - 1) + 8.0)
	node.global_position = _point_behind(_follow_distance(followers.size() - 1))


func _physics_process(delta: float) -> void:
	if state == State.FINISHED:
		velocity = Vector2.ZERO
		_sync_pose(delta)
		return
	if state == State.WAIT:
		velocity.x = 0.0
		velocity.y = _sized(40.0)
		move_and_slide()
		_sync_pose(delta)
		return
	if state == State.RUN_OFF:
		_run_off(delta)
	else:
		_glide(delta)
	_debug_fast_x()
	_clear_forces()
	move_and_slide()
	_sync_pose(delta)
	_record_trail()
	_update_followers(delta)


func _run_off(delta: float) -> void:
	floor_snap_length = _sized(12.0)
	visual.rotation = 0.0
	_zoom_through_run()
	if _leap_point and global_position.x >= _leap_point.global_position.x:
		_leap()
		return
	var top_speed := _sized(run_max_speed)
	var gap := top_speed - velocity.x
	if gap > 0.0:
		var rate := run_accel / maxf(run_max_speed - 40.0, 1.0)
		velocity.x += gap * (1.0 - exp(-rate * delta))
	velocity.y = _sized(240.0)


func _leap() -> void:
	state = State.GLIDE
	_lifted = true
	floor_snap_length = 0.0
	_control_timer = leap_drift_time
	velocity.y = -_sized(leap_speed)
	camera.zoom = Vector2(0.5, 0.5)


func _zoom_through_run() -> void:
	if _leap_point == null:
		return
	var span := _leap_point.global_position.x - _run_start_x
	var t := 1.0
	if span > 1.0:
		t = clampf((global_position.x - _run_start_x) / span, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	var zoom := lerpf(1.0, 0.5, eased)
	camera.zoom = Vector2(zoom, zoom)


func _debug_fast_x() -> void:
	if not Input.is_physical_key_pressed(KEY_O):
		return
	var dir := Input.get_axis("left", "right")
	if dir == 0.0:
		dir = signf(velocity.x)
	if dir == 0.0:
		dir = 1.0
	velocity.x = dir * 4000.0


func _glide(delta: float) -> void:
	floor_snap_length = 0.0
	var can_steer := _control_timer <= 0.0
	if _control_timer > 0.0:
		_control_timer = maxf(_control_timer - delta, 0.0)
	else:
		var axis := Input.get_axis("left", "right")
		var target_x := axis * _sized(glide_speed)
		var rate := glide_accel
		if axis == 0.0 or absf(target_x) < absf(velocity.x):
			rate = glide_coast
		var blend := 1.0 - exp(-rate * delta)
		velocity.x = lerpf(velocity.x, target_x, blend)
		if _has_lift:
			var along := velocity.dot(_lift_dir)
			var new_along := move_toward(along, _lift_speed, _lift_accel * delta)
			velocity += _lift_dir * (new_along - along)

	if _gust_pending:
		var gust_along := velocity.dot(_gust_dir)
		velocity += _gust_dir * (_gust_speed - gust_along)
		_gust_pending = false

	velocity += _air_push * delta
	_apply_vertical(delta, can_steer)
	velocity.x = clampf(velocity.x, _sized(-1100.0), _sized(1100.0))
	velocity.y = clampf(velocity.y, -_sized(max_up_speed), _sized(520.0))
	_lean_with_speed()


func _apply_vertical(delta: float, allow_dive: bool) -> void:
	var dive := allow_dive and Input.is_action_pressed("down")
	if velocity.y < 0.0:
		velocity.y += _sized(gravity) * delta
		return
	var base := _sized(dive_speed if dive else fall_speed)
	var terminal := maxf(base + absf(velocity.x) * sink_per_horizontal, 1.0)
	var drag := _sized(fall_gravity) / terminal
	var accel := _sized(fall_gravity) - drag * velocity.y
	velocity.y += accel * delta


func _sync_pose(delta: float) -> void:
	var pose := Pose.STAND
	var facing := 0
	if state == State.RUN_OFF:
		pose = Pose.RUN
		facing = 1
		var limit := float(_run_steps())
		if _run_cursor < limit:
			_run_cursor = minf(_run_cursor + _run_fps() * delta, limit)
		var shown := mini(int(_run_cursor), _run_steps() - 1)
		_run_frame = shown % RUN_FRAMES.size()
	elif state == State.GLIDE:
		if _lifted or velocity.y < 0.0:
			_lifted = true
		var reach := _reach_facing()
		if reach != 0:
			pose = Pose.REACH
			facing = reach
		elif _lifted:
			pose = Pose.MOVE
			if absf(velocity.x) >= _sized(reach_speed):
				facing = 1 if velocity.x > 0.0 else -1
			else:
				facing = _facing
		else:
			pose = Pose.RUN
			facing = 1
	if pose == Pose.MOVE or pose == Pose.REACH:
		_frame_clock += delta
		if _frame_clock >= frame_time:
			_frame_clock = fmod(_frame_clock, frame_time)
			_frame = 1 - _frame
	else:
		_frame_clock = 0.0
		_frame = 0
	if facing != 0:
		_facing = facing
	_apply_pose(pose)


func _run_fps() -> float:
	var through := clampf(_run_cursor / float(RUN_FRAMES.size()), 0.0, 1.0)
	var eased := through * through * (3.0 - 2.0 * through)
	return lerpf(RUN_FPS_START, RUN_FPS_END, eased)


func _run_steps() -> int:
	return int(round(RUN_CYCLES * float(RUN_FRAMES.size())))


func _run_anchor(index: int) -> Vector2:
	var anchors := [
		run_1_anchor, run_2_anchor, run_3_anchor,
		run_4_anchor, run_5_anchor, run_6_anchor,
	]
	if index < 0 or index >= anchors.size():
		return Vector2.ZERO
	return anchors[index]


func _reach_facing() -> int:
	var best := _sized(reach_range) + 1.0
	var facing := 0
	for node in get_tree().get_nodes_in_group("seed"):
		if not is_instance_valid(node) or node.get("collected") == true:
			continue
		if not node.has_method("seed_position"):
			continue
		var to_seed: Vector2 = node.seed_position() - _body_center()
		var dist := to_seed.length()
		if dist > _sized(reach_range) or dist >= best or absf(to_seed.x) < _sized(4.0):
			continue
		var toward := 1 if to_seed.x > 0.0 else -1
		if absf(velocity.x) < _sized(reach_speed) or signf(velocity.x) != float(toward):
			continue
		best = dist
		facing = toward
	return facing


func _apply_pose(pose: Pose) -> void:
	if visual == null:
		return
	_pose = pose
	var tex: Texture2D = STAND_TEX
	var anchor := standing_anchor
	if pose == Pose.RUN:
		var run_index := clampi(_run_frame, 0, RUN_FRAMES.size() - 1)
		tex = RUN_FRAMES[run_index]
		anchor = _run_anchor(run_index)
	elif pose == Pose.MOVE:
		if _frame == 0:
			tex = MOVE_A_TEX
			anchor = moving_a_anchor
		else:
			tex = MOVE_B_TEX
			anchor = moving_b_anchor
	elif pose == Pose.REACH:
		if _frame == 0:
			tex = REACH_A_TEX
			anchor = reaching_a_anchor
		else:
			tex = REACH_B_TEX
			anchor = reaching_b_anchor
	visual.texture = tex
	visual.centered = true
	visual.material = null
	# Fit every pose to the idle canvas height so taller flight frames stay the same size.
	var fitted := sprite_height / maxf(STAND_TEX.get_height(), 1.0)
	if pose == Pose.MOVE or pose == Pose.REACH:
		fitted *= 0.92
	visual.scale = Vector2(fitted, fitted)
	var facing_left := pose != Pose.STAND and _facing < 0
	visual.flip_h = facing_left
	var drawn_h := tex.get_height() * fitted
	var pos := Vector2(0, -drawn_h * 0.5) + anchor
	if facing_left:
		pos.x = -pos.x
	visual.position = pos


func _lean_with_speed() -> void:
	var speed_ref := maxf(_sized(glide_speed), 1.0)
	var amount := clampf(velocity.x / speed_ref, -1.0, 1.0)
	visual.rotation = amount * deg_to_rad(max_lean)


func _clear_forces() -> void:
	_air_push = Vector2.ZERO
	_has_lift = false
	_lift_accel = 0.0


func _body_center() -> Vector2:
	# Local offset so character scale is included. Feet sit on the origin; this is the back of the head.
	return to_global(Vector2(0, -sprite_height * 0.82))


func _sized(amount: float) -> float:
	return amount * _size_scale


func _follow_distance(index: int) -> float:
	return _sized(22.0 + follow_spacing * float(index))


func _record_trail() -> void:
	var point := _body_center()
	if _trail.is_empty():
		_trail.append(point)
		return
	# The last point stays on the body so followers move every frame.
	# A new point is kept once the body is a couple of pixels past the previous one.
	if _trail.size() == 1:
		if _trail[0].distance_to(point) >= _sized(2.0):
			_trail.append(point)
		else:
			_trail[0] = point
	else:
		var committed: Vector2 = _trail[_trail.size() - 2]
		_trail[_trail.size() - 1] = point
		if committed.distance_to(point) >= _sized(2.0):
			_trail.append(point)
	var keep := _follow_distance(maxi(followers.size(), 1)) + _sized(follow_spacing + 40.0)
	_trim_trail(keep)


func _trim_trail(max_distance: float) -> void:
	if _trail.size() < 2:
		return
	var acc := 0.0
	var keep_from := 0
	for i in range(_trail.size() - 1, 0, -1):
		acc += _trail[i].distance_to(_trail[i - 1])
		keep_from = i - 1
		if acc >= max_distance:
			break
	if keep_from <= 0:
		return
	var trimmed: Array[Vector2] = []
	for i in range(keep_from, _trail.size()):
		trimmed.append(_trail[i])
	_trail = trimmed


func _ensure_trail_length(need: float) -> void:
	if _trail.is_empty():
		_trail.append(_body_center())
	var have := _trail_length()
	if have >= need:
		return
	var dir := Vector2.LEFT
	if velocity.length() > 8.0:
		dir = -velocity.normalized()
	elif _trail.size() >= 2:
		var step_dir := _trail[0] - _trail[1]
		if step_dir.length_squared() > 0.01:
			dir = step_dir.normalized()
	var cursor := _trail[0]
	var guard := 0
	while have < need and guard < 400:
		var step := _sized(6.0)
		cursor += dir * step
		_trail.insert(0, cursor)
		have += step
		guard += 1


func _trail_length() -> float:
	var total := 0.0
	for i in range(1, _trail.size()):
		total += _trail[i - 1].distance_to(_trail[i])
	return total


func _point_behind(distance: float) -> Vector2:
	if _trail.is_empty():
		return _body_center()
	var remaining := distance
	for i in range(_trail.size() - 1, 0, -1):
		var a: Vector2 = _trail[i]
		var b: Vector2 = _trail[i - 1]
		var seg := a.distance_to(b)
		if seg >= remaining:
			if seg <= 0.001:
				return a
			return a.lerp(b, remaining / seg)
		remaining -= seg
	return _trail[0]


func _update_followers(delta: float) -> void:
	var blend := 1.0 - exp(-14.0 * delta)
	for i in followers.size():
		var follower := followers[i]
		if not is_instance_valid(follower):
			continue
		var target := _point_behind(_follow_distance(i))
		follower.global_position = follower.global_position.lerp(target, blend)
