extends CharacterBody2D

const InputSetup = preload("res://scripts/input_setup.gd")
const STAND_TEX := preload("res://Assets/images/peppermint_stand_rough.png")
const RUN_TEX := preload("res://Assets/images/peppermint_run_rough.png")
const MOVE_TEX := preload("res://Assets/images/peppermint_move_rough.png")

## Drawn height of each peppermint pose, in pixels.
const TARGET_HEIGHT := 156.0
const STAND_CONTENT := Rect2(59, 25, 317, 756)
const RUN_CONTENT := Rect2(76, 6, 758, 784)
const MOVE_CONTENT := Rect2(828, 324, 1494, 1560)

enum State { WAIT, RUN_OFF, GLIDE, FINISHED }
enum Pose { STAND, RUN, MOVE }

## Downward terminal with no sideways speed, in pixels per second.
@export var fall_speed := 140.0
## Downward terminal base while S is held. Sideways speed stacks on top of this.
@export var dive_speed := 360.0
## Extra downward speed for each pixel per second sideways. 0.25 is one down per four across.
@export var sink_per_horizontal := 0.25
## Downward acceleration while falling. Drag is solved from this so the terminal stays exact.
@export var fall_gravity := 280.0
## Downward acceleration while rising, so wind and gusts arc back down.
@export var gravity := 280.0
## Fastest rise, in pixels per second. Wind and gusts cannot climb faster than this.
@export var max_up_speed := 360.0
@export var glide_speed := 260.0
## Exponential steer rate while holding left or right. Higher reaches the target sooner.
@export var glide_accel := 4.0
## Exponential release rate when easing off or shedding extra sideways speed.
@export var glide_coast := 2.5
## How far the body leans at full glide speed, in degrees.
@export var max_lean := 12.0
@export var run_accel := 280.0
@export var run_max_speed := 360.0
## Small hop off the platform, in pixels per second upward.
@export var leap_speed := 80.0
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
var _pose_ready := false
var _lifted := false

@onready var camera: Camera2D = $Camera2D
@onready var visual: Sprite2D = $Visual


func _enter_tree() -> void:
	add_to_group("player")


func _ready() -> void:
	InputSetup.ensure()
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 12.0
	velocity = Vector2.ZERO
	camera.make_current()
	_leap_point = get_parent().get_node_or_null("Platform/LeapPoint") as Node2D
	_apply_pose(Pose.STAND)


func start_run() -> void:
	if state != State.WAIT:
		return
	state = State.RUN_OFF
	velocity.x = 40.0
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
	return 1.0


func body_rect() -> Rect2:
	return Rect2(global_position + Vector2(-14, -48), Vector2(28, 48))


func apply_gust(direction: Vector2, speed: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	_gust_pending = true
	_gust_dir = direction.normalized()
	_gust_speed = speed


func attach_follower(node: Node2D) -> void:
	if followers.has(node):
		return
	followers.append(node)
	node.z_index = 4
	_ensure_trail_length(follow_spacing * float(followers.size()) + 8.0)
	node.global_position = _point_behind(follow_spacing * float(followers.size()))


func _physics_process(delta: float) -> void:
	if state == State.FINISHED:
		velocity = Vector2.ZERO
		return
	if state == State.WAIT:
		velocity.x = 0.0
		velocity.y = 40.0
		move_and_slide()
		return
	if state == State.RUN_OFF:
		_run_off(delta)
	else:
		_glide(delta)
	_clear_forces()
	move_and_slide()
	_sync_pose()
	_record_trail()
	_update_followers()


func _run_off(delta: float) -> void:
	floor_snap_length = 12.0
	visual.rotation = 0.0
	if _leap_point and global_position.x >= _leap_point.global_position.x:
		_leap()
		return
	velocity.x = minf(velocity.x + run_accel * delta, run_max_speed)
	velocity.y = 240.0


func _leap() -> void:
	state = State.GLIDE
	_lifted = true
	floor_snap_length = 0.0
	_control_timer = leap_drift_time
	velocity.y = -leap_speed


func _glide(delta: float) -> void:
	floor_snap_length = 0.0
	var can_steer := _control_timer <= 0.0
	if _control_timer > 0.0:
		_control_timer = maxf(_control_timer - delta, 0.0)
	else:
		var axis := Input.get_axis("left", "right")
		var target_x := axis * glide_speed
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
	velocity.x = clampf(velocity.x, -1100.0, 1100.0)
	velocity.y = clampf(velocity.y, -max_up_speed, 520.0)
	_lean_with_speed()


func _apply_vertical(delta: float, allow_dive: bool) -> void:
	var dive := allow_dive and Input.is_action_pressed("down")
	if velocity.y < 0.0:
		velocity.y += gravity * delta
		return
	var base := dive_speed if dive else fall_speed
	var terminal := maxf(base + absf(velocity.x) * sink_per_horizontal, 1.0)
	var drag := fall_gravity / terminal
	var accel := fall_gravity - drag * velocity.y
	velocity.y += accel * delta


func _sync_pose() -> void:
	if state == State.FINISHED or state == State.WAIT:
		_apply_pose(Pose.STAND)
		return
	if state == State.RUN_OFF:
		_apply_pose(Pose.RUN)
		return
	if _lifted or velocity.y < 0.0:
		_lifted = true
		_apply_pose(Pose.MOVE)
	else:
		_apply_pose(Pose.RUN)


func _apply_pose(pose: Pose) -> void:
	if visual == null or (_pose_ready and _pose == pose):
		return
	_pose_ready = true
	_pose = pose
	var tex: Texture2D = STAND_TEX
	var content := STAND_CONTENT
	if pose == Pose.RUN:
		tex = RUN_TEX
		content = RUN_CONTENT
	elif pose == Pose.MOVE:
		tex = MOVE_TEX
		content = MOVE_CONTENT
	visual.texture = tex
	visual.centered = true
	var fitted := TARGET_HEIGHT / content.size.y
	visual.scale = Vector2(fitted, fitted)
	var foot := Vector2(content.position.x + content.size.x * 0.5, content.end.y)
	visual.position = (tex.get_size() * 0.5 - foot) * fitted


func _lean_with_speed() -> void:
	var speed_ref := maxf(glide_speed, 1.0)
	var amount := clampf(velocity.x / speed_ref, -1.0, 1.0)
	visual.rotation = amount * deg_to_rad(max_lean)


func _clear_forces() -> void:
	_air_push = Vector2.ZERO
	_has_lift = false
	_lift_accel = 0.0


func _body_center() -> Vector2:
	return global_position + Vector2(0, -24)


func _record_trail() -> void:
	var point := _body_center()
	if _trail.is_empty() or _trail[_trail.size() - 1].distance_to(point) >= 5.0:
		_trail.append(point)
	var keep := follow_spacing * float(followers.size() + 2) + 40.0
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
		cursor += dir * 6.0
		_trail.insert(0, cursor)
		have += 6.0
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


func _update_followers() -> void:
	for i in followers.size():
		var follower := followers[i]
		if not is_instance_valid(follower):
			continue
		follower.global_position = _point_behind(follow_spacing * float(i + 1))
