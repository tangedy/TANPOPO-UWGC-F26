extends CharacterBody2D

const InputSetup = preload("res://scripts/input_setup.gd")
const FuzzLine := preload("res://scripts/fuzz_line.gd")
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
## After the run, that last pose holds, squashes, then eases into moving or reaching.
## The hop plays first. Squash starts once the rise has mostly crested, or after this long.
const LAUNCH_RISE := 0.42
const LAUNCH_HOLD := 0.08
const LAUNCH_SQUISH := 0.1
const LAUNCH_RELEASE := 0.1
const LAUNCH_SQUASH_X := 1.14
const LAUNCH_SQUASH_Y := 0.76
## Takeoff squash, separate from the squash into the flight pose.
const JUMP_SQUISH := 0.06
const JUMP_UNSQUISH := 0.09
## Lean used for the hop. Glide lean comes back once the hop crests.
const LEAP_LEAN := 4.0

## Drawn height of the idle sprite, in pixels. Flight frames share that scale. Anchors shift on top.
@export var sprite_height := 156.0
## Seconds each moving or reaching frame stays up.
@export var frame_time := 0.2
## How close a seed must be before she reaches for it, in pixels.
@export var reach_range := 360.0
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
@export var gravity := 100.0
## Fastest rise, in pixels per second. Wind and gusts cannot climb faster than this.
@export var max_up_speed := 320.0
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
@export var leap_speed := 340.0
## Downward acceleration during the hop, so it crests quickly.
@export var leap_gravity := 620.0
## Seconds of carried run speed before left/right control turns on.
@export var leap_drift_time := 1.0
## Distance between the traveler and each collected object.
@export var follow_spacing := 46.0
## Follow keepout radius around the body center, before adding the seed's own size.
@export var follow_keepout_radius := 40.0

var state := State.WAIT
var followers: Array[Node2D] = []
var _spawn_position := Vector2.ZERO

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
var _launch_blend := false
var _launch_time := 0.0
var _launch_rise := 0.0
var _launch_release := 0.0
var _jump_squish := 0.0
var _leap_hop := false
var _step_frame := -1
var _whoosh_level := 0.0
var _lifted := false
var _run_start_x := 0.0
## Matches the node's scale so speeds and distances stay in proportion to her size.
var _size_scale := 1.0

@onready var camera: Camera2D = $Camera2D
@onready var visual: Sprite2D = $Visual
@onready var seed_parti: GPUParticles2D = $SeedParti

var _fuzz_line: Node


func _enter_tree() -> void:
	add_to_group("player")


func _ready() -> void:
	InputSetup.ensure()
	collision_layer = 2
	collision_mask = 1
	_size_scale = maxf(absf(scale.x), 0.001)
	floor_snap_length = _sized(12.0)
	velocity = Vector2.ZERO
	_spawn_position = global_position
	camera.make_current()
	camera.zoom = Vector2(1.0, 1.0)
	_fit_camera_limits()
	_leap_point = get_parent().get_node_or_null("Platform/LeapPoint") as Node2D
	_apply_pose(Pose.STAND)
	_set_seed_parti(false)


func _fit_camera_limits() -> void:
	var platform := get_parent().get_node_or_null("Platform") as Node2D
	if platform == null:
		return
	var vertical: Array[Rect2] = []
	var horizontal: Array[Rect2] = []
	for child in platform.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null:
			continue
		var rect := shape_node.shape as RectangleShape2D
		if rect == null:
			continue
		var shape_bounds := _global_rect(shape_node, rect)
		if shape_bounds.size.y > shape_bounds.size.x:
			vertical.append(shape_bounds)
		else:
			horizontal.append(shape_bounds)
	if vertical.size() < 2:
		return
	vertical.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
	var left_wall: Rect2 = vertical[0]
	var right_wall: Rect2 = vertical[vertical.size() - 1]
	# Inner faces. Side walls stick past the ceiling, so a merged box opens the limits.
	var limit_left := left_wall.end.x
	var limit_right := right_wall.position.x
	var limit_top := maxf(left_wall.position.y, right_wall.position.y)
	var limit_bottom := minf(left_wall.end.y, right_wall.end.y)
	var mid_y := (limit_top + limit_bottom) * 0.5
	for bar in horizontal:
		if bar.get_center().y < mid_y:
			limit_top = maxf(limit_top, bar.end.y)
		else:
			limit_bottom = minf(limit_bottom, bar.position.y)
	# The side walls run well below the cliff. Keep the view from dropping that far.
	limit_bottom -= 1100.0
	if limit_right <= limit_left or limit_bottom <= limit_top:
		return
	camera.limit_left = int(floor(limit_left))
	camera.limit_top = int(floor(limit_top))
	camera.limit_right = int(ceil(limit_right))
	camera.limit_bottom = int(ceil(limit_bottom))


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
	_launch_blend = false
	_launch_time = 0.0
	_launch_rise = 0.0
	_launch_release = 0.0
	_jump_squish = 0.0
	_leap_hop = false
	_step_frame = -1
	_run_start_x = global_position.x
	_apply_pose(Pose.RUN)


## Debug: teleport to the cliff start while staying in the controllable glide
## (move/reach) state, so you can keep steering from there.
func teleport_to_start() -> void:
	global_position = _spawn_position
	velocity = Vector2.ZERO
	_air_push = Vector2.ZERO
	_has_lift = false
	_lift_accel = 0.0
	_gust_pending = false
	_control_timer = 0.0
	_trail.clear()
	if not is_in_group("off_the_edge"):
		add_to_group("off_the_edge")
	state = State.GLIDE
	motion_mode = MOTION_MODE_FLOATING
	floor_snap_length = 0.0
	_lifted = true
	_leap_hop = false
	camera.zoom = Vector2(0.5, 0.5)
	camera.make_current()
	_set_seed_parti(true)


func finish() -> void:
	state = State.FINISHED
	velocity = Vector2.ZERO
	# Freeze on her current move/reach pose while the screen fades; don't snap to idle.
	_set_seed_parti(false)


## Ending shot: stay on the cliff in the opening frame and do not follow her.
func hold_at_start() -> void:
	state = State.FINISHED
	velocity = Vector2.ZERO
	camera.zoom = Vector2.ONE
	camera.position_smoothing_enabled = false
	camera.make_current()
	var center := camera.get_screen_center_position()
	var half := get_viewport().get_visible_rect().size * 0.5 / camera.zoom
	camera.limit_left = int(floor(center.x - half.x))
	camera.limit_top = int(floor(center.y - half.y))
	camera.limit_right = int(ceil(center.x + half.x))
	camera.limit_bottom = int(ceil(center.y + half.y))
	# Camera stays locked; nudge her left so the credits have the sky beside her.
	global_position.x -= 80.0
	_apply_pose(Pose.STAND)
	_set_seed_parti(false)


func add_air_push(accel: Vector2, keep_up: bool = false) -> void:
	# A sideways gust's upward component is the pinch that launches her. Fold it downward.
	# Up-diagonals pass keep_up so their half-strength lift stays upward.
	if not keep_up and absf(accel.x) >= absf(accel.y):
		accel.y = absf(accel.y)
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
	_ensure_trail_length(_trail_need())
	node.global_position = _clear_follow_point(_follow_distance(followers.size() - 1), node)


func _physics_process(delta: float) -> void:
	if state == State.FINISHED:
		velocity = Vector2.ZERO
		# Leave the last flight pose in place; only let the wind sound settle.
		_update_wind_whoosh(delta)
		return
	if state == State.WAIT:
		motion_mode = MOTION_MODE_GROUNDED
		velocity.x = 0.0
		velocity.y = _sized(40.0)
		move_and_slide()
		_sync_pose(delta)
		_update_wind_whoosh(delta)
		return
	if state == State.RUN_OFF:
		_run_off(delta)
	else:
		_glide(delta)
	_debug_fast_x()
	var velocity_before_slide := velocity
	var position_before_slide := global_position
	_clear_forces()
	move_and_slide()
	if state == State.GLIDE:
		_sink_out_of_pinch(position_before_slide, velocity_before_slide, delta)
	_sync_pose(delta)
	_update_wind_whoosh(delta)
	_record_trail()
	_update_followers(delta)


func _run_off(delta: float) -> void:
	motion_mode = MOTION_MODE_GROUNDED
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
	add_to_group("off_the_edge")
	_lifted = true
	floor_snap_length = 0.0
	_control_timer = leap_drift_time
	velocity.y = -_sized(leap_speed)
	_leap_hop = true
	_jump_squish = 0.0001
	_play_sfx("Jump")
	camera.zoom = Vector2(0.5, 0.5)
	_set_seed_parti(true)


func _set_seed_parti(on: bool) -> void:
	if seed_parti == null:
		return
	seed_parti.preprocess = 0.0
	seed_parti.visible = on
	seed_parti.emitting = on
	if on:
		seed_parti.restart()
	_set_leaf_hint(on)


func _set_leaf_hint(on: bool) -> void:
	if on:
		if _fuzz_line == null or not is_instance_valid(_fuzz_line):
			_fuzz_line = FuzzLine.new()
			_fuzz_line.name = "FuzzLine"
			var room := get_parent()
			if room == null:
				return
			room.add_child(_fuzz_line)
		_fuzz_line.begin(self)
	elif is_instance_valid(_fuzz_line):
		_fuzz_line.end()


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
	motion_mode = MOTION_MODE_FLOATING
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
	velocity.x = clampf(velocity.x, _sized(-900.0), _sized(900.0))
	velocity.y = clampf(velocity.y, -_sized(max_up_speed), _sized(520.0))
	_ease_into_ceiling()
	_lean_with_speed()


## Near a ceiling cushion, the rise cap falls to zero as the head reaches the top.
func _ease_into_ceiling() -> void:
	if velocity.y >= 0.0:
		return
	var body := body_rect()
	var head := Vector2(body.get_center().x, body.position.y)
	var full := _sized(max_up_speed)
	var cap := full
	var inside := false
	for zone in get_tree().get_nodes_in_group("ceiling_cushion"):
		if not zone.has_method("rise_limit"):
			continue
		var limit: float = zone.rise_limit(head, full)
		if limit < 0.0:
			continue
		inside = true
		cap = minf(cap, limit)
	if inside:
		velocity.y = maxf(velocity.y, -cap)


## A sideways slide into a corner can convert that speed into a rise. Put the same speed downward.
func _sink_out_of_pinch(before_pos: Vector2, before_vel: Vector2, delta: float) -> void:
	if get_slide_collision_count() == 0 or absf(before_vel.x) < _sized(40.0):
		return
	var actual_dy := global_position.y - before_pos.y
	var expected_dy := before_vel.y * delta
	var extra_up := minf(expected_dy, 0.0) - actual_dy
	var velocity_up := minf(before_vel.y, 0.0) - velocity.y
	if extra_up < 1.5 and velocity_up < _sized(30.0):
		return
	if extra_up >= 1.5:
		global_position.y += extra_up * 2.0
	var kick := extra_up / maxf(delta, 0.001) if extra_up >= 1.5 else 0.0
	velocity.y = maxf(before_vel.y, 0.0) + maxf(kick, velocity_up)


func _apply_vertical(delta: float, allow_dive: bool) -> void:
	var dive := allow_dive and Input.is_action_pressed("down")
	if velocity.y < 0.0:
		var pull := leap_gravity if _leap_hop else gravity
		velocity.y += _sized(pull) * delta
		if _leap_hop and velocity.y >= 0.0:
			_leap_hop = false
		return
	_leap_hop = false
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
		_play_run_step()
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
	var flight := pose == Pose.MOVE or pose == Pose.REACH
	if _launch_blend and state != State.GLIDE:
		_launch_blend = false
		_launch_release = 0.0
	if _launch_blend:
		_launch_time += delta
		if _launch_time >= LAUNCH_HOLD + LAUNCH_SQUISH:
			_launch_blend = false
			_launch_release = LAUNCH_RELEASE
			_play_flight_sfx()
		else:
			pose = Pose.RUN
	elif flight and _pose == Pose.RUN and state == State.GLIDE:
		_launch_rise += delta
		var still_rising := velocity.y < -_sized(30.0) and _launch_rise < LAUNCH_RISE
		if still_rising:
			pose = Pose.RUN
		else:
			_launch_blend = true
			_launch_time = 0.0
			pose = Pose.RUN
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
	_apply_launch_squish(delta)


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


func _smooth(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


func _apply_launch_squish(delta: float) -> void:
	var amount := 0.0
	if _launch_blend:
		var into := _launch_time - LAUNCH_HOLD
		if into > 0.0:
			amount = _smooth(clampf(into / LAUNCH_SQUISH, 0.0, 1.0))
	elif _launch_release > 0.0:
		amount = _smooth(clampf(_launch_release / LAUNCH_RELEASE, 0.0, 1.0))
		_launch_release = maxf(_launch_release - delta, 0.0)
	amount = maxf(amount, _jump_squish_amount(delta))
	if amount <= 0.0 or visual.texture == null:
		return
	var prev_h := visual.texture.get_height() * visual.scale.y
	visual.scale = Vector2(
		visual.scale.x * lerpf(1.0, LAUNCH_SQUASH_X, amount),
		visual.scale.y * lerpf(1.0, LAUNCH_SQUASH_Y, amount)
	)
	var new_h := visual.texture.get_height() * visual.scale.y
	visual.position.y += (prev_h - new_h) * 0.5


func _jump_squish_amount(delta: float) -> float:
	if _jump_squish <= 0.0:
		return 0.0
	_jump_squish += delta
	var total := JUMP_SQUISH + JUMP_UNSQUISH
	if _jump_squish >= total:
		_jump_squish = 0.0
		return 0.0
	if _jump_squish <= JUMP_SQUISH:
		return _smooth(_jump_squish / JUMP_SQUISH)
	var u := 1.0 - (_jump_squish - JUMP_SQUISH) / JUMP_UNSQUISH
	return _smooth(clampf(u, 0.0, 1.0))


func _lean_with_speed() -> void:
	var speed_ref := maxf(_sized(glide_speed), 1.0)
	var amount := clampf(velocity.x / speed_ref, -1.0, 1.0)
	var lean := LEAP_LEAN if _leap_hop else max_lean
	visual.rotation = amount * deg_to_rad(lean)


func _play_run_step() -> void:
	if _run_frame == _step_frame:
		return
	_step_frame = _run_frame
	# run_3 and run_6 are the airborne frames of the cycle.
	if _run_frame == 2 or _run_frame == 5:
		return
	_play_sfx("Walk", randf_range(1.5, 2.0))


func _update_wind_whoosh(delta: float) -> void:
	var player := _sfx_player("WindWhoosh")
	if player == null:
		return
	var flying := state == State.GLIDE and (_pose == Pose.MOVE or _pose == Pose.REACH)
	var target := 0.0
	if flying:
		var cap := Vector2(_sized(900.0), _sized(520.0)).length()
		target = clampf(velocity.length() / maxf(cap, 1.0), 0.0, 1.0)
	var blend := 1.0 - exp(-3.5 * delta)
	_whoosh_level = lerpf(_whoosh_level, target, blend)
	if _whoosh_level <= 0.001 and not flying:
		_whoosh_level = 0.0
		if player.playing:
			player.stop()
		return
	player.global_position = global_position
	player.pitch_scale = lerpf(0.75, 1.0, _whoosh_level)
	if _whoosh_level <= 0.0001:
		player.volume_db = -80.0
	else:
		player.volume_db = linear_to_db(_whoosh_level) + 18.0
	if not player.playing:
		player.play()


func _play_flight_sfx() -> void:
	_play_sfx("Fluff")
	_play_sfx("Poof")


func _play_sfx(node_name: String, pitch: float = -1.0) -> void:
	var player := _sfx_player(node_name)
	if player == null:
		return
	player.global_position = global_position
	if pitch >= 0.0:
		player.pitch_scale = pitch
	player.play()


func _sfx_player(node_name: String) -> AudioStreamPlayer2D:
	var room := get_parent()
	if room == null:
		return null
	return room.get_node_or_null("Music/" + node_name) as AudioStreamPlayer2D


func _clear_forces() -> void:
	_air_push = Vector2.ZERO
	_has_lift = false
	_lift_accel = 0.0


func _body_center() -> Vector2:
	# Local offset so character scale is included. Feet sit on the origin; this is the back of the head.
	return to_global(Vector2(0, -sprite_height * 0.82))


func _follow_keepout_center() -> Vector2:
	return body_rect().get_center()


func _sized(amount: float) -> float:
	return amount * _size_scale


func _follow_distance(index: int) -> float:
	return _sized(22.0 + follow_spacing * float(index))


func _trail_need() -> float:
	var radius := _sized(follow_keepout_radius)
	if not followers.is_empty() and is_instance_valid(followers[0]):
		radius = _follow_keepout_radius(followers[0])
	return _follow_distance(maxi(followers.size(), 1)) + _sized(follow_spacing + 40.0) + radius * 2.0


func _follower_shape(follower: Node2D) -> CollisionShape2D:
	for child in follower.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node != null:
			return shape_node
	return null


func _follower_half_extents(follower: Node2D) -> Vector2:
	var shape_node := _follower_shape(follower)
	if shape_node == null:
		return Vector2(_sized(16.0), _sized(20.0))
	var rect := shape_node.shape as RectangleShape2D
	if rect == null:
		return Vector2(_sized(16.0), _sized(20.0))
	var xf := shape_node.global_transform
	var half := rect.size * 0.5
	return Vector2(
		absf(xf.x.x) * half.x + absf(xf.y.x) * half.y,
		absf(xf.x.y) * half.x + absf(xf.y.y) * half.y
	)


func _follower_collision_offset(follower: Node2D) -> Vector2:
	var shape_node := _follower_shape(follower)
	if shape_node == null:
		return Vector2.ZERO
	return shape_node.global_position - follower.global_position


func _follow_keepout_radius(follower: Node2D) -> float:
	var half := _follower_half_extents(follower)
	var seed_r := maxf(half.x, half.y)
	return _sized(follow_keepout_radius) + seed_r + _follower_collision_offset(follower).length()


func _push_out_of_circle(point: Vector2, center: Vector2, radius: float) -> Vector2:
	var offset := point - center
	var dist := offset.length()
	if dist >= radius:
		return point
	if dist < 0.0001:
		return center + Vector2.LEFT * radius
	return center + offset * (radius / dist)


func _segment_cuts_circle(from: Vector2, to: Vector2, center: Vector2, radius: float) -> bool:
	var ab := to - from
	var ac := center - from
	var ab_len_sq := ab.length_squared()
	if ab_len_sq < 0.0001:
		return from.distance_to(center) < radius
	var t := clampf(ac.dot(ab) / ab_len_sq, 0.0, 1.0)
	return (from + ab * t).distance_to(center) < radius - 0.5


func _move_around_keepout(from: Vector2, to: Vector2, center: Vector2, radius: float, max_step: float, blend: float) -> Vector2:
	from = _push_out_of_circle(from, center, radius)
	to = _push_out_of_circle(to, center, radius)
	if not _segment_cuts_circle(from, to, center, radius):
		var desired := from.lerp(to, blend)
		var delta := desired - from
		if delta.length() > max_step:
			desired = from + delta.normalized() * max_step
		return desired
	var v0 := from - center
	var v1 := to - center
	var r0 := maxf(v0.length(), radius)
	var r1 := maxf(v1.length(), radius)
	var a0 := v0.angle() if v0.length_squared() > 0.0001 else 0.0
	var a1 := v1.angle() if v1.length_squared() > 0.0001 else 0.0
	var ang := wrapf(a1 - a0, -PI, PI)
	var path_len := absf(ang) * (r0 + r1) * 0.5 + absf(r1 - r0)
	if path_len <= 0.0001:
		return to
	var t := clampf(minf(path_len * blend, max_step) / path_len, 0.0, 1.0)
	return center + Vector2.from_angle(a0 + ang * t) * lerpf(r0, r1, t)


func _clear_follow_point(distance: float, follower: Node2D) -> Vector2:
	var center := _follow_keepout_center()
	var radius := _follow_keepout_radius(follower)
	_ensure_trail_length(distance + radius * 2.0)
	var point := _point_behind(distance)
	var extra := 0.0
	var step := _sized(4.0)
	var guard := 0
	while point.distance_to(center) < radius and guard < 200:
		extra += step
		point = _point_behind(distance + extra)
		guard += 1
	return _push_out_of_circle(point, center, radius)


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
	_trim_trail(_trail_need())


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
	var max_step := maxf(velocity.length(), _sized(80.0)) * delta
	var occupied := 0.0
	var center := _follow_keepout_center()
	for i in followers.size():
		var follower := followers[i]
		if not is_instance_valid(follower):
			continue
		var dist := maxf(_follow_distance(i), occupied)
		var target := _clear_follow_point(dist, follower)
		var used := dist
		var behind := _point_behind(dist)
		if target.distance_squared_to(behind) > 0.01:
			used = dist + target.distance_to(behind)
		occupied = used + _sized(follow_spacing)
		follower.global_position = _move_around_keepout(
			follower.global_position,
			target,
			center,
			_follow_keepout_radius(follower),
			max_step,
			blend
		)
