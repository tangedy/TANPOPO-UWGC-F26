extends Node2D

## A bright moon disc with a soft halo, drawn so it stays readable on the night sky.


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 260.0, Color(1.0, 0.97, 0.86, 0.05))
	draw_circle(Vector2.ZERO, 170.0, Color(1.0, 0.98, 0.9, 0.1))
	draw_circle(Vector2.ZERO, 96.0, Color(1.0, 0.985, 0.92, 0.22))
	draw_circle(Vector2.ZERO, 64.0, Color(1.0, 0.99, 0.94, 1.0))
	draw_circle(Vector2(-18, -10), 12.0, Color(0.9, 0.88, 0.8, 1.0))
	draw_circle(Vector2(16, 14), 8.0, Color(0.92, 0.9, 0.82, 1.0))
	draw_circle(Vector2(6, -22), 5.0, Color(0.94, 0.92, 0.85, 1.0))
