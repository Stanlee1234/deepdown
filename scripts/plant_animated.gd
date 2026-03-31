extends AnimatedSprite2D

@export_dir var frames_folder := "res://images/Plant Animations/BlueFlower1"
@export var animation_name := "default"
@export var animation_fps := 12.0

func _ready() -> void:
	var dir := DirAccess.open(frames_folder)
	if dir == null:
		return

	var files: PackedStringArray = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".png"):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	files.sort()
	if files.is_empty():
		return

	var generated := SpriteFrames.new()
	generated.add_animation(animation_name)
	generated.set_animation_speed(animation_name, animation_fps)
	generated.set_animation_loop(animation_name, true)

	for file in files:
		generated.add_frame(animation_name, load("%s/%s" % [frames_folder, file]))

	sprite_frames = generated
	play(animation_name)
	if files.size() > 0:
		frame = randi() % files.size()
