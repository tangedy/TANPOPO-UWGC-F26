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
	if points[0].distance_to(points[points.size() - 1]) > 8.0:
		points = points.duplicate()
		points.append(points[0])
	draw_polyline(points, Color(1.0, 0.84, 0.35, 0.85), 2.0, true)
	for i in curve.point_count:
		draw_circle(curve.get_point_position(i), 5.0, Color(1.0, 0.92, 0.55, 0.95))
