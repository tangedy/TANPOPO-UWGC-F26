@tool
extends Node2D

@export var body_color: Color = Color(0.93, 0.75, 0.5, 1):
	set(value):
		body_color = value
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-14, -48, 28, 48), body_color, true)
