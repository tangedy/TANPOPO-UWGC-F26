@tool
extends Path2D

const TRAIL_SHADER := preload("res://shaders/path_trail.gdshader")

## How see-through the moving streak is.
@export_range(0.05, 1.0, 0.01) var trail_alpha := 0.55
## Length of the streak, in pixels. The rest of the path stays hidden.
@export var trail_length := 1100.0
## How fast the streaks travel along the path, in pixels per second.
@export var flow_speed := 240.0
## Streaks placed evenly around the loop.
@export_range(1, 6, 1) var trail_count := 3
## Seed paths close the gap between the last point and the first. A guide trail stays open.
@export var close_loop := true
@export var line_width := 12.0

const DISPERSE_TIME := 2.6

var _bound_curve: Curve2D
var _line: Line2D
var _material: ShaderMaterial
var _length := 0.0
var _white: Texture2D
var _dispersing := false
var _disperse_time := 0.0


func _enter_tree() -> void:
	if close_loop:
		z_index = -1
	_bind_curve()


func _process(delta: float) -> void:
	if curve != _bound_curve:
		_bind_curve()
	if _dispersing:
		_tick_disperse(delta)
	_apply_uniforms()


## The collected seed's wind simply fades away, from the end back to the start.
func disperse() -> void:
	if _dispersing or Engine.is_editor_hint():
		return
	_dispersing = true
	_disperse_time = 0.0


func _tick_disperse(delta: float) -> void:
	_disperse_time += delta
	var t := clampf(_disperse_time / DISPERSE_TIME, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	if _material:
		_material.set_shader_parameter("wipe", eased)
	if t >= 1.0 and _line:
		_line.visible = false


func _bind_curve() -> void:
	if _bound_curve != null and _bound_curve.changed.is_connected(_rebuild):
		_bound_curve.changed.disconnect(_rebuild)
	_bound_curve = curve
	if _bound_curve != null and not _bound_curve.changed.is_connected(_rebuild):
		_bound_curve.changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	var line := _ensure_line()
	var points := _trail_points()
	_length = 0.0
	for i in range(1, points.size()):
		_length += points[i - 1].distance_to(points[i])
	line.points = points
	line.visible = points.size() >= 2 and _length >= 8.0
	_apply_uniforms()


func _apply_uniforms() -> void:
	if _material == null or _length < 8.0:
		return
	var count := maxi(trail_count, 1)
	var spacing := _length / float(count)
	var span := minf(trail_length, spacing * 0.82)
	_material.set_shader_parameter("trail_count", float(count))
	_material.set_shader_parameter("portion", span / _length)
	_material.set_shader_parameter("flow", flow_speed / _length)
	_material.set_shader_parameter("trail_alpha", trail_alpha)
	if not _dispersing:
		_material.set_shader_parameter("wipe", 0.0)


func _ensure_line() -> Line2D:
	if is_instance_valid(_line):
		return _line
	_line = Line2D.new()
	_line.name = "Trail"
	_material = ShaderMaterial.new()
	_material.shader = TRAIL_SHADER
	_line.material = _material
	_line.texture = _white_texture()
	_line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	_line.width = line_width
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_NONE
	_line.end_cap_mode = Line2D.LINE_CAP_NONE
	_line.antialiased = true
	add_child(_line, false, INTERNAL_MODE_BACK)
	return _line


func _white_texture() -> Texture2D:
	if _white:
		return _white
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color.WHITE)
	_white = ImageTexture.create_from_image(image)
	return _white


func _trail_points() -> PackedVector2Array:
	if curve == null or curve.point_count < 2:
		return PackedVector2Array()
	var points := curve.get_baked_points()
	if points.size() < 2:
		return PackedVector2Array()
	var last := curve.point_count - 1
	var gap := curve.get_point_position(last).distance_to(curve.get_point_position(0))
	if close_loop and gap > 1.0:
		var from := curve.get_point_position(last)
		var to := curve.get_point_position(0)
		var control_a := from + curve.get_point_out(last)
		var control_b := to + curve.get_point_in(0)
		for step in 16:
			var t := float(step + 1) / 16.0
			points.append(_bezier(from, control_a, control_b, to, t))
	return points


func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3
