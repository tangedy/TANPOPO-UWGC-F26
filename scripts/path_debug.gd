@tool
extends Path2D

func _ready() -> void:
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if curve == null or curve.point_count < 2:
		return
	var points := curve.get_baked_points()
	if points.size() < 2:
		return
	var last := curve.point_count - 1
	var gap := curve.get_point_position(last).distance_to(curve.get_point_position(0))
	if gap > 1.0:
		var from := curve.get_point_position(last)
		var to := curve.get_point_position(0)
		var control_a := from + curve.get_point_out(last)
		var control_b := to + curve.get_point_in(0)
		for step in 12:
			var t := float(step + 1) / 12.0
			points.append(_bezier(from, control_a, control_b, to, t))
	draw_polyline(points, Color(1.0, 0.84, 0.35, 0.85), 2.0, true)
	for i in curve.point_count:
		draw_circle(curve.get_point_position(i), 5.0, Color(1.0, 0.92, 0.55, 0.95))


func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3
