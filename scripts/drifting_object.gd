@tool
extends Node2D

## Cruising speed along the path, in pixels per second.
@export var speed := 80.0
## How much the cruising speed swells and eases. 0 is steady, 1 is a strong breath.
@export_range(0.0, 1.0, 0.01) var breathe_amount := 0.5
## Seconds for one relaxed-to-rushed cycle.
@export var breathe_period := 4.0
## Downward world speed while the path descends.
@export var fall_speed := 30.0
## Extra acceleration along the path while it climbs, like a quick upbreeze.
@export var upbreeze_acceleration := 220.0
@export var max_up_speed := 260.0
## Where on the path this object starts, from 0 to 1.
@export_range(0.0, 1.0, 0.01) var start_ratio := 0.0
@export var path_return := 36.0
@export var max_drift_offset := 140.0

var collected := false

var _along := 0.0
var _up_speed := 0.0
var _time := 0.0
var _air_velocity := Vector2.ZERO
var _offset := Vector2.ZERO
var _pending_push := Vector2.ZERO
var _has_lift := false
var _lift_dir := Vector2.UP
var _lift_speed := 0.0
var _lift_accel := 0.0
var _player: Node2D

@onready var path: Path2D = $Path2D
@onready var follow: PathFollow2D = $Path2D/PathFollow2D
@onready var hitbox: Area2D = $Body


func _enter_tree() -> void:
	add_to_group("seed")


func _ready() -> void:
	if Engine.is_editor_hint():
		_preview()
		update_configuration_warnings()
		return
	hitbox.collision_layer = 4
	hitbox.collision_mask = 2
	hitbox.monitoring = true
	hitbox.monitorable = true
	hitbox.body_entered.connect(_on_body_entered)
	follow.rotates = false
	follow.loop = true
	if path.curve and path.curve.point_count >= 2:
		follow.progress_ratio = start_ratio
	_along = speed


func add_air_push(accel: Vector2) -> void:
	if collected:
		return
	_pending_push += accel


func add_lift(direction: Vector2, speed: float, accel: float) -> void:
	if collected or direction.length_squared() < 0.0001:
		return
	_has_lift = true
	_lift_dir = direction.normalized()
	_lift_speed = speed
	_lift_accel = maxf(_lift_accel, accel)


func air_push_scale() -> float:
	return 0.5


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_preview()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or collected:
		return
	if path.curve == null or path.curve.point_count < 2:
		return
	_time += delta
	_advance_along_path(delta)
	_apply_air(delta)
	hitbox.global_position = follow.global_position + _offset


func _advance_along_path(delta: float) -> void:
	var tangent := _tangent()
	var breathe := 1.0
	if breathe_period > 0.01:
		breathe = 1.0 + breathe_amount * sin(TAU * _time / breathe_period)
	breathe = maxf(breathe, 0.2)

	var desired := speed * breathe
	if tangent.y > 0.3:
		desired = (fall_speed / tangent.y) * breathe
		_up_speed = move_toward(_up_speed, 0.0, upbreeze_acceleration * delta)
		_along = move_toward(_along, desired, 90.0 * delta)
	elif tangent.y < -0.3:
		if _up_speed < _along:
			_up_speed = _along
		_up_speed = minf(_up_speed + upbreeze_acceleration * delta, max_up_speed)
		_along = _up_speed
	else:
		_up_speed = move_toward(_up_speed, 0.0, upbreeze_acceleration * delta)
		_along = move_toward(_along, desired, 90.0 * delta)
	follow.progress += _along * delta


func _apply_air(delta: float) -> void:
	_air_velocity += _pending_push * delta
	_pending_push = Vector2.ZERO
	if _has_lift:
		var along := _air_velocity.dot(_lift_dir)
		var new_along := move_toward(along, _lift_speed, _lift_accel * delta)
		_air_velocity += _lift_dir * (new_along - along)
		_has_lift = false
		_lift_accel = 0.0
	var drag := 1.0 - exp(-1.2 * delta)
	_air_velocity = _air_velocity.lerp(Vector2.ZERO, drag)
	_offset += _air_velocity * delta
	_offset = _offset.move_toward(Vector2.ZERO, path_return * delta)
	_offset = _offset.limit_length(max_drift_offset)


func _tangent() -> Vector2:
	var curve := path.curve
	var length := curve.get_baked_length()
	if length <= 1.0:
		return Vector2.RIGHT
	var offset := fposmod(follow.progress, length)
	var xf := curve.sample_baked_with_rotation(offset)
	if xf.x.length_squared() < 0.0001:
		return Vector2.RIGHT
	return xf.x.normalized()


func _on_body_entered(body: Node2D) -> void:
	if collected or not body.is_in_group("player"):
		return
	collected = true
	hitbox.set_deferred("monitoring", false)
	hitbox.set_deferred("monitorable", false)
	hitbox.set_deferred("collision_layer", 0)
	hitbox.set_deferred("collision_mask", 0)
	_player = body
	_finish_capture.call_deferred()


func _finish_capture() -> void:
	if not is_inside_tree() or _player == null:
		return
	var room := get_tree().get_first_node_in_group("drift_room")
	hitbox.reparent(room)
	_player.attach_follower(hitbox)
	if room and room.has_method("note_collected"):
		room.note_collected()


func _preview() -> void:
	if hitbox == null or path == null or path.curve == null or path.curve.point_count < 2:
		return
	hitbox.global_position = path.to_global(path.curve.sample_baked(0))


func _get_configuration_warnings() -> PackedStringArray:
	var path_node := get_node_or_null("Path2D") as Path2D
	if path_node == null or path_node.curve == null or path_node.curve.point_count < 2:
		return PackedStringArray(["Add at least two points to the child Path2D."])
	return PackedStringArray()
