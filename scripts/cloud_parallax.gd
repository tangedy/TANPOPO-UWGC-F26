extends Node2D

## 1 matches the world. Lower sits farther back, higher rushes past in front.
@export var scroll_scale := Vector2(0.4, 0.4)

var _origin := Vector2.ZERO
var _cam_origin := Vector2.ZERO


func _ready() -> void:
	_origin = position
	var cam := get_viewport().get_camera_2d()
	if cam:
		_cam_origin = cam.get_screen_center_position()


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var delta := cam.get_screen_center_position() - _cam_origin
	position = _origin + delta * (Vector2.ONE - scroll_scale)
