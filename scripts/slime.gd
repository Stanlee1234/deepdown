extends CharacterBody2D

const MOVE_SPEED := 220.0
const GRAVITY := 1800.0

@export var player_path: NodePath

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D

var _player: Node2D = null

func _ready() -> void:
	_player = get_node_or_null(player_path) as Node2D
	navigation_agent.path_desired_distance = 24.0
	navigation_agent.target_desired_distance = 24.0
	if animated_sprite != null:
		animated_sprite.play()

func _physics_process(delta: float) -> void:
	if _player == null:
		_player = get_node_or_null(player_path) as Node2D
		if _player == null:
			return

	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

	navigation_agent.target_position = _player.global_position
	var next_path_position := navigation_agent.get_next_path_position()
	var move_dir := sign(next_path_position.x - global_position.x)

	if abs(next_path_position.x - global_position.x) < 6.0:
		move_dir = 0.0

	velocity.x = move_dir * MOVE_SPEED
	animated_sprite.flip_h = velocity.x < 0.0
	move_and_slide()
