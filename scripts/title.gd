extends Control

const DRIFT := "res://scenes/drift.tscn"

@onready var music: AudioStreamPlayer = $Music


func _ready() -> void:
	_loop_music()
	music.play()
	$Center/Buttons/Play.pressed.connect(_on_play)
	$Center/Buttons/Exit.pressed.connect(_on_exit)
	$Center/Buttons/Play.grab_focus()


func _loop_music() -> void:
	if music.stream is AudioStreamWAV:
		var wav := music.stream as AudioStreamWAV
		var frames := int(wav.get_length() * wav.mix_rate)
		wav.loop_begin = 0
		if frames > 1:
			wav.loop_end = frames
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD


func _on_play() -> void:
	get_tree().change_scene_to_file(DRIFT)


func _on_exit() -> void:
	get_tree().quit()
