extends Node2D

## Hint fluff. G releases a thin cloud over one second. Each bit walks toward the
## nearest drifting seed, sweeps away, and fades out on its own lifetime.

const FLUFF := preload("res://Assets/images/drift_seed_parti.png")
const KEY := preload("res://shaders/white_key.gdshader")
const TINT := Color(0.35, 0.32, 0.28, 1)

const COUNT := 12
const SPAWN_WINDOW := 1.0
const FOLLOW_SPEED := 200.0
const ARRIVE_DISTANCE := 72.0
const LIFE := 2.0
const FADE_IN := 0.12
const FADE_OUT := 0.4

var _player: Node2D
var _bursts: Array[Burst] = []
var _material: ShaderMaterial


func play(player: Node2D) -> void:
	_player = player
	_launch()


func _ready() -> void:
	z_index = 2
	_material = ShaderMaterial.new()
	_material.shader = KEY
	_material.set_shader_parameter("cutoff", 0.96)


func _process(delta: float) -> void:
	var i := _bursts.size() - 1
	while i >= 0:
		if _bursts[i].tick(delta, self):
			_bursts[i].free_wisps()
			_bursts.remove_at(i)
		i -= 1


func _launch() -> void:
	if not is_instance_valid(_player):
		return
	var origin := _origin()
	var target := _nearest_drifter(origin)
	if target == null:
		return
	var burst := Burst.new()
	burst.setup(self, target, _material)
	_bursts.append(burst)


func _origin() -> Vector2:
	var parti := _player.get_node_or_null("SeedParti") as Node2D
	if parti:
		return parti.global_position
	return _player.global_position


func _nearest_drifter(from: Vector2) -> Node2D:
	var best := INF
	var found: Node2D = null
	for node in get_tree().get_nodes_in_group("seed"):
		if not _is_live_seed(node):
			continue
		var dist := from.distance_squared_to(_seed_body(node))
		if found == null or dist < best:
			best = dist
			found = node
	return found


func _is_live_seed(node: Node) -> bool:
	return is_instance_valid(node) and node.has_method("is_drifting") and node.is_drifting()


func _seed_body(node: Node2D) -> Vector2:
	if node.has_method("seed_position"):
		return node.seed_position()
	return node.global_position


class Burst:
	var age := 0.0
	var target: Node2D
	var wisps: Array[Wisp] = []

	func setup(host: Node2D, seed: Node2D, material: Material) -> void:
		target = seed
		for i in COUNT:
			var wisp := Wisp.new()
			wisp.delay = randf() * SPAWN_WINDOW
			wisp.spin = randf() * TAU
			wisp.freq = randf_range(1.4, 2.8)
			wisp.base_rot = deg_to_rad(randf_range(-20.0, 20.0))
			wisp.scale = randf_range(0.46, 0.7)
			wisp.sprite = Sprite2D.new()
			wisp.sprite.texture = FLUFF
			wisp.sprite.material = material
			wisp.sprite.centered = true
			wisp.sprite.visible = false
			wisp.sprite.z_index = 2
			host.add_child(wisp.sprite)
			wisps.append(wisp)

	func tick(delta: float, host: Node2D) -> bool:
		age += delta
		var aim := _live_aim(host)
		var pending := false
		for wisp in wisps:
			if wisp.born < 0.0:
				if age < wisp.delay:
					pending = true
					continue
				_birth(wisp, host)
			var lived := age - wisp.born
			if lived >= wisp.life:
				wisp.sprite.visible = false
				continue
			pending = true
			if aim == Vector2.INF:
				_start_sweep(wisp)
			elif not wisp.sweeping:
				_follow(wisp, aim, delta, lived)
			if wisp.sweeping:
				_sweep(wisp, delta)
			_place(wisp, lived)
		return not pending

	func _birth(wisp: Wisp, host: Node2D) -> void:
		wisp.born = age
		wisp.life = LIFE
		var origin: Vector2 = host.call("_origin")
		wisp.pos = origin + Vector2.from_angle(randf() * TAU) * randf_range(8.0, 36.0)
		wisp.sprite.visible = true

	func _follow(wisp: Wisp, aim: Vector2, delta: float, lived: float) -> void:
		var launch := smoothstep(0.0, 0.2, lived)
		var sway := sin(lived * wisp.freq + wisp.spin) * 0.28
		var to_aim := aim - wisp.pos
		var dist := to_aim.length()
		if dist > 1.0:
			var step := to_aim / dist * FOLLOW_SPEED * launch * delta
			wisp.pos += step.rotated(sway)
		wisp.pos += Vector2(cos(lived * wisp.freq + wisp.spin), sin(lived * (wisp.freq * 0.7) + wisp.spin)) * 26.0 * delta
		if lived > 0.2 and dist <= ARRIVE_DISTANCE:
			_start_sweep(wisp)

	func _start_sweep(wisp: Wisp) -> void:
		if wisp.sweeping:
			return
		wisp.sweeping = true
		wisp.scatter = Vector2.from_angle(randf() * TAU) * randf_range(260.0, 900.0)

	func _sweep(wisp: Wisp, delta: float) -> void:
		wisp.pos += wisp.scatter * delta
		wisp.scatter *= exp(-1.6 * delta)

	func _live_aim(host: Node2D) -> Vector2:
		var from := _center()
		if not host.call("_is_live_seed", target):
			target = host.call("_nearest_drifter", from)
		if not is_instance_valid(target):
			return Vector2.INF
		return host.call("_seed_body", target)

	func _center() -> Vector2:
		var mid := Vector2.ZERO
		var count := 0
		for wisp in wisps:
			if wisp.born < 0.0:
				continue
			mid += wisp.pos
			count += 1
		if count == 0:
			return mid
		return mid / float(count)

	func _place(wisp: Wisp, lived: float) -> void:
		var fade := smoothstep(0.0, FADE_IN, lived)
		var fade_at := wisp.life - FADE_OUT
		if lived > fade_at:
			fade *= 1.0 - smoothstep(fade_at, wisp.life, lived)
		wisp.sprite.global_position = wisp.pos
		wisp.sprite.global_rotation = wisp.base_rot + sin(lived * wisp.freq) * 0.2
		wisp.sprite.scale = Vector2(wisp.scale, wisp.scale)
		var color := TINT
		color.a = fade
		wisp.sprite.modulate = color

	func free_wisps() -> void:
		for wisp in wisps:
			if is_instance_valid(wisp.sprite):
				wisp.sprite.queue_free()
		wisps.clear()


class Wisp:
	var sprite: Sprite2D
	var pos := Vector2.ZERO
	var scatter := Vector2.ZERO
	var delay := 0.0
	var born := -1.0
	var life := 2.0
	var sweeping := false
	var spin := 0.0
	var freq := 1.0
	var base_rot := 0.0
	var scale := 1.0
