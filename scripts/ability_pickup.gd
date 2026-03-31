extends Area2D

@export var ability_name: StringName

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body == null or not (body is CharacterBody2D):
		return

	match String(ability_name):
		"double_jump":
			body.set("can_double_jump", true)
		"dash":
			body.set("can_dash", true)
		"wall_jump":
			body.set("can_wall_jump", true)
		"ground_pound":
			body.set("can_ground_pound", true)
		_:
			return

	queue_free()
