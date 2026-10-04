extends CanvasLayer

## Covers scene changes so the HTML export does not flash the window clear color while the next scene loads.

var _rect: ColorRect
var _tween: Tween


func _ready() -> void:
	layer = 120
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.BLACK
	_rect.modulate.a = 0.0
	add_child(_rect)
	RenderingServer.set_default_clear_color(Color.BLACK)


func hold(color: Color) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_rect.color = color
	_rect.modulate.a = 1.0
	RenderingServer.set_default_clear_color(color)


func fade_out(duration: float) -> void:
	if _rect.modulate.a <= 0.001:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished
	if _rect.modulate.a <= 0.001:
		RenderingServer.set_default_clear_color(Color.BLACK)


func change_scene(path: String, color: Color) -> void:
	hold(color)
	# Draw the cover once before the load, so the last presented frame is the fade.
	await get_tree().process_frame
	var packed := await load_packed(path)
	if not is_inside_tree():
		return
	if packed:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(path)


func load_packed(path: String) -> PackedScene:
	if ResourceLoader.has_cached(path):
		return ResourceLoader.load(path) as PackedScene
	var err := ResourceLoader.load_threaded_request(path)
	if err != OK and err != ERR_BUSY:
		return ResourceLoader.load(path) as PackedScene
	while true:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			return ResourceLoader.load_threaded_get(path) as PackedScene
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return null
		await get_tree().process_frame
	return null
