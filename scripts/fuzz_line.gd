extends Node2D

## Leaf hint. Every 5 to 15 seconds a line of leaves appears just off-camera,
## on the side opposite the nearest seed, then crosses toward it. They speed up
## the longer they fly, pass through the seed, and vanish once they leave the screen.
## Once that seed is collected, the line fades out over 3 seconds.

const LEAVES: Array[Texture2D] = [
	preload("res://Assets/images/leaf_1.png"),
	preload("res://Assets/images/leaf_2.png"),
]
const WOOSH := preload("res://Assets/sfx/soundreality-wind-blowing-457954.mp3")
const TINT := Color(0.88, 0.96, 0.86, 1)

const COUNT := 18
const SPAWN_WINDOW := 1.5
const FOLLOW_SPEED := 460.0
## Extra speed gained each second a leaf has been flying.
const SPEED_GAIN := 320.0
const ARRIVE_DISTANCE := 80.0
const FADE_IN := 0.12
const COLLECT_FADE := 3.0
const INTERVAL_MIN := 5.0
const INTERVAL_MAX := 15.0
const EDGE_MARGIN := 120.0
const SPAWN_STAGGER := 80.0

var _player: Node2D
var _armed := false
var _wait := 0.0
var _bursts: Array[Burst] = []


func begin(player: Node2D) -> void:
	z_index = 2
	_player = player
	if _armed:
		return
	_armed = true
	_wait = randf_range(INTERVAL_MIN, INTERVAL_MAX)


func end() -> void:
	_armed = false


func _process(delta: float) -> void:
	if _armed and is_instance_valid(_player):
		_wait -= delta
		if _wait <= 0.0:
			if _launch():
				_wait = randf_range(INTERVAL_MIN, INTERVAL_MAX)
			else:
				_wait = 2.0
	var i := _bursts.size() - 1
	while i >= 0:
		if _bursts[i].tick(delta, self):
			_bursts[i].free_wisps()
			_bursts.remove_at(i)
		i -= 1


func _launch() -> bool:
	if not is_instance_valid(_player):
		return false
	var origin := _origin()
	var target := _nearest_drifter(origin)
	if target == null:
		return false
	var approach := _approach_dir(origin, _seed_body(target))
	var burst := Burst.new()
	burst.setup(self, target, approach)
	_bursts.append(burst)
	_play_woosh(origin)
	return true


func _play_woosh(at: Vector2) -> void:
	var voice := AudioStreamPlayer2D.new()
	voice.stream = WOOSH
	voice.volume_db = -6.0
	voice.pitch_scale = randf_range(1.25, 1.5)
	voice.attenuation = 0.0
	add_child(voice)
	voice.global_position = at
	voice.play()
	get_tree().create_timer(0.55).timeout.connect(func() -> void:
		if is_instance_valid(voice):
			voice.stop()
			voice.queue_free()
	)


## Outward from the seed, through the player, with a small angle so bursts do not stack.
func _approach_dir(player_pos: Vector2, seed_pos: Vector2) -> Vector2:
	var away := player_pos - seed_pos
	if away.length_squared() < 1.0:
		away = Vector2.LEFT
	return away.normalized().rotated(randf_range(-0.3, 0.3))


## Where a leaf should appear right now: just past the current view, trailing off-screen.
func _offscreen_point(dir: Vector2, delay: float, side: float) -> Vector2:
	var outward := dir
	if outward.length_squared() < 0.0001:
		outward = Vector2.LEFT
	else:
		outward = outward.normalized()
	var view := _view_rect()
	var center := view.position + view.size * 0.5
	var edge := _ray_exit(center, outward, view)
	var margin := EDGE_MARGIN + delay * SPAWN_STAGGER
	var perp := Vector2(-outward.y, outward.x)
	return edge + outward * margin + perp * side


func _ray_exit(center: Vector2, dir: Vector2, view: Rect2) -> Vector2:
	var t := INF
	var left := view.position.x
	var right := view.position.x + view.size.x
	var top := view.position.y
	var bottom := view.position.y + view.size.y
	if dir.x > 0.0001:
		t = minf(t, (right - center.x) / dir.x)
	elif dir.x < -0.0001:
		t = minf(t, (left - center.x) / dir.x)
	if dir.y > 0.0001:
		t = minf(t, (bottom - center.y) / dir.y)
	elif dir.y < -0.0001:
		t = minf(t, (top - center.y) / dir.y)
	if not is_finite(t) or t < 0.0:
		t = view.size.length() * 0.5
	return center + dir * t


func _view_rect() -> Rect2:
	var cam := _player.get_node_or_null("Camera2D") as Camera2D
	var view := get_viewport_rect().size
	if cam == null:
		var at := _origin()
		return Rect2(at - view * 0.5, view)
	var size := view / cam.zoom
	var center := cam.get_screen_center_position()
	return Rect2(center - size * 0.5, size)


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
	var approach := Vector2.LEFT
	var collected_at := -1.0
	var target: Node2D
	var wisps: Array[Wisp] = []

	func setup(host: Node2D, seed: Node2D, dir: Vector2) -> void:
		target = seed
		approach = dir
		for i in COUNT:
			var wisp := Wisp.new()
			wisp.delay = randf() * SPAWN_WINDOW
			wisp.side = randf_range(-32.0, 32.0)
			wisp.spin = randf() * TAU
			wisp.freq = randf_range(1.4, 2.8)
			wisp.base_rot = randf() * TAU
			wisp.spin_rate = randf_range(-1.4, 1.4)
			wisp.scale = randf_range(0.04, 0.1)
			wisp.sprite = Sprite2D.new()
			wisp.sprite.texture = LEAVES[randi() % LEAVES.size()]
			wisp.sprite.centered = true
			wisp.sprite.visible = false
			wisp.sprite.z_index = 2
			host.add_child(wisp.sprite)
			wisps.append(wisp)

	func tick(delta: float, host: Node2D) -> bool:
		age += delta
		if _mark_collected():
			if not _any_showing():
				return true
			if age - collected_at >= COLLECT_FADE:
				return true
			for wisp in wisps:
				if wisp.born < 0.0 or wisp.gone:
					continue
				_place(wisp, age - wisp.born)
			return false
		var aim := _live_aim(host)
		var view: Rect2 = host.call("_view_rect")
		var pending := false
		for wisp in wisps:
			if wisp.born < 0.0:
				if age < wisp.delay:
					pending = true
					continue
				_birth(wisp, host)
			if wisp.gone:
				continue
			var lived := age - wisp.born
			if wisp.passed:
				_coast(wisp, delta, lived)
				if _left_screen(wisp, view):
					wisp.gone = true
					wisp.sprite.visible = false
					continue
			elif aim == Vector2.INF:
				_begin_pass(wisp, -approach)
			else:
				_follow(wisp, aim, delta, lived)
			pending = true
			_place(wisp, lived)
		return not pending

	func _mark_collected() -> bool:
		if collected_at >= 0.0:
			return true
		if is_instance_valid(target) and target.get("collected") == true:
			collected_at = age
			return true
		return false

	func _any_showing() -> bool:
		for wisp in wisps:
			if wisp.born < 0.0 or wisp.gone or not is_instance_valid(wisp.sprite) or not wisp.sprite.visible:
				continue
			return true
		return false

	func _birth(wisp: Wisp, host: Node2D) -> void:
		wisp.born = age
		wisp.pos = host.call("_offscreen_point", approach, wisp.delay, wisp.side)
		wisp.sprite.visible = true

	func _speed(lived: float) -> float:
		return FOLLOW_SPEED + lived * SPEED_GAIN

	func _follow(wisp: Wisp, aim: Vector2, delta: float, lived: float) -> void:
		var launch := smoothstep(0.0, 0.2, lived)
		var sway := sin(lived * wisp.freq + wisp.spin) * 0.28
		var to_aim := aim - wisp.pos
		var dist := to_aim.length()
		var dir := -approach
		if dist > 1.0:
			dir = to_aim / dist
			wisp.pos += dir.rotated(sway) * _speed(lived) * launch * delta
		wisp.pos += Vector2(cos(lived * wisp.freq + wisp.spin), sin(lived * (wisp.freq * 0.7) + wisp.spin)) * 34.0 * delta
		if lived > 0.2 and dist <= ARRIVE_DISTANCE:
			_begin_pass(wisp, dir)

	func _begin_pass(wisp: Wisp, dir: Vector2) -> void:
		if wisp.passed:
			return
		wisp.passed = true
		wisp.pass_at = wisp.pos
		if dir.length_squared() < 0.0001:
			dir = -approach
		wisp.heading = dir.normalized()

	func _coast(wisp: Wisp, delta: float, lived: float) -> void:
		var sway := sin(lived * wisp.freq + wisp.spin) * 0.12
		wisp.pos += wisp.heading.rotated(sway) * _speed(lived) * delta

	func _left_screen(wisp: Wisp, view: Rect2) -> bool:
		var past := (wisp.pos - wisp.pass_at).dot(wisp.heading)
		if past < 60.0:
			return false
		return not view.grow(32.0).has_point(wisp.pos)

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
		if collected_at >= 0.0:
			fade *= 1.0 - smoothstep(0.0, COLLECT_FADE, age - collected_at)
		wisp.sprite.global_position = wisp.pos
		wisp.sprite.global_rotation = wisp.base_rot + wisp.spin_rate * lived
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
	var heading := Vector2.RIGHT
	var pass_at := Vector2.ZERO
	var delay := 0.0
	var side := 0.0
	var born := -1.0
	var passed := false
	var gone := false
	var spin := 0.0
	var freq := 1.0
	var base_rot := 0.0
	var spin_rate := 0.0
	var scale := 1.0
