extends Node2D

## A single ambient bird that flaps (bird1/2/3) and drifts across the view.

var speed := 60.0
var _target_x := 0.0

@onready var anim: AnimatedSprite2D = $Anim


## Called by the spawner right after instancing.
## move_speed: horizontal pixels/second. target_x: global x to despawn past.
func setup(move_speed: float, target_x: float, flap_fps := 8.0, sprite_scale := 0.45) -> void:
	speed = move_speed
	_target_x = target_x
	if anim == null:
		anim = get_node_or_null("Anim") as AnimatedSprite2D
	if anim != null:
		anim.scale = Vector2(sprite_scale, sprite_scale)
		# Frames are authored at 8 fps; scale to the requested flap rate.
		anim.speed_scale = flap_fps / 8.0
		# Desync so a flock does not flap in perfect lockstep.
		anim.frame = randi() % 3
		anim.play("fly")


func _process(delta: float) -> void:
	global_position.x += speed * delta
	if global_position.x > _target_x + 8.0:
		queue_free()
