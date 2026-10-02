@tool
extends Node2D

@export var color: Color = Color(0.95, 0.62, 0.28, 1):
	set(value):
		color = value
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 14.0, color)
	draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 28, Color(1, 1, 1, 0.45), 1.5, true)
