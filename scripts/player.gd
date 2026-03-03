extends CharacterBody2D

# ── Movement Constants ──────────────────────────────────────────────
## Tuned for 512×512 art assets; adjust multipliers to taste.
const TILE_UNIT := 512.0

const MOVE_SPEED       := TILE_UNIT * 2.2        # 1126 px/s horizontal
const JUMP_VELOCITY    := -TILE_UNIT * 3.2        # upward burst
const FAST_FALL_SPEED  := TILE_UNIT * 5.5         # dive / fast-fall
const GRAVITY          := TILE_UNIT * 7.5         # baseline gravity
const MAX_FALL_SPEED   := TILE_UNIT * 6.5         # terminal velocity
const WALL_SLIDE_SPEED := TILE_UNIT * 1.5         # slower fall on walls

# Coyote time & jump buffering (seconds)
const COYOTE_TIME      := 0.12
const JUMP_BUFFER_TIME := 0.10

# Wall-jump tuning
const WALL_JUMP_VELOCITY   := Vector2(TILE_UNIT * 2.2, -TILE_UNIT * 3.0)
const WALL_JUMP_LOCK_TIME  := 0.15   # seconds player can't steer after wall-jump

# Dash (unlockable ability – set can_dash = true when acquired)
const DASH_SPEED     := TILE_UNIT * 6.5
const DASH_DURATION  := 0.2
const DASH_COOLDOWN  := 0.4           # seconds before dash is available again

# Ground-pound / dive (thematic: going *beneath the surface*)
const GROUND_POUND_SPEED := TILE_UNIT * 7.5

# ── Screen Shake / Vibration Constants ──────────────────────────────
const SHAKE_INTENSITY    := 24.0    # max pixel offset (scales with 512px assets)
const SHAKE_DURATION     := 0.35    # seconds
const SHAKE_DECAY_RATE   := 5.0     # how fast the shake fades (higher = faster)
const SHAKE_FREQUENCY    := 30.0    # oscillations per second

# Gamepad rumble
const RUMBLE_STRONG      := 0.7     # strong motor intensity (0.0 – 1.0)
const RUMBLE_WEAK        := 0.4     # weak motor intensity  (0.0 – 1.0)
const RUMBLE_DURATION    := 0.3     # seconds

# ── Unlockable Ability Flags and Developer Mode ─────────────────────
## Toggle admin_mode in the inspector to unlock all abilities for testing.
@export var admin_mode       : bool = false
@export var can_double_jump  : bool = false
@export var can_dash         : bool = false
@export var can_wall_jump    : bool = false
@export var can_ground_pound : bool = false

# ── State ─────────���─────────────────────────────────────────────────
var coyote_timer        : float = 0.0
var jump_buffer_timer   : float = 0.0
var wall_jump_lock      : float = 0.0
var dash_timer          : float = 0.0
var dash_cooldown_timer : float = 0.0
var has_double_jumped   : bool  = false
var has_air_dash        : bool  = true
var is_dashing          : bool  = false
var is_ground_pounding  : bool  = false
var is_jumping          : bool  = false
var dash_direction      : Vector2 = Vector2.ZERO
var facing_direction    : float = 1.0   # 1 = right, -1 = left

# Shake state
var shake_timer        : float = 0.0
var shake_intensity    : float = 0.0
var shake_rng          : RandomNumberGenerator = RandomNumberGenerator.new()

# Camera reference – assigned automatically or manually
var _camera : Camera2D = null

# Optional node references – wire these up in the editor or via code
@onready var animated_sprite : AnimatedSprite2D = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null
@onready var collision_shape : CollisionShape2D = $CollisionShape2D if has_node("CollisionShape2D") else null

# ── Signals (hook into these from other systems) ────────────────────
signal jumped
signal double_jumped
signal wall_jumped
signal dashed
signal ground_pounded
signal ground_pound_landed
signal landed

# ════════════════════════════════════════════════════════════════════
#  READY
# ════════════════════════════════════════════════════════════════════
func _ready() -> void:
	shake_rng.randomize()
	_camera = _find_camera()

	# Admin mode: unlock all abilities for testing
	if admin_mode:
		can_double_jump  = true
		can_dash         = true
		can_wall_jump    = true
		can_ground_pound = true

# ════════════════════════════════════════════════════════════════════
#  PHYSICS PROCESS
# ════════════════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:
	_update_timers(delta)

	if is_dashing:
		_process_dash(delta)
	elif is_ground_pounding:
		_process_ground_pound(delta)
	else:
		_apply_gravity(delta)
		_handle_horizontal_movement(delta)
		_handle_jump()
		_handle_wall_slide(delta)
		_handle_dash_input()
		_handle_ground_pound_input()

	move_and_slide()

	_check_landing()
	_process_screen_shake(delta)
	_update_animation()

# ── Timers ──────────────────────────────────────────────────────────
func _update_timers(delta: float) -> void:
	# Coyote time – keep a small grace window after leaving a ledge
	if is_on_floor():
		coyote_timer = COYOTE_TIME
		has_double_jumped = false
		has_air_dash = true
	else:
		coyote_timer = max(coyote_timer - delta, 0.0)

	# Reset dash when touching a wall (wall sliding)
	if can_wall_jump and is_on_wall_only():
		has_air_dash = true

	jump_buffer_timer   = max(jump_buffer_timer   - delta, 0.0)
	wall_jump_lock      = max(wall_jump_lock      - delta, 0.0)
	dash_cooldown_timer = max(dash_cooldown_timer  - delta, 0.0)

# ── Gravity ─────────────────────────────────────────────────────────
func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return

	var current_gravity := GRAVITY

	# Fast-fall when holding down
	if Input.is_action_pressed("move_down"):
		current_gravity *= 1.6

	velocity.y = min(velocity.y + current_gravity * delta, MAX_FALL_SPEED)

# ── Horizontal Movement ────────────────────────────────────────────
func _handle_horizontal_movement(_delta: float) -> void:
	if wall_jump_lock > 0.0:
		return  # brief lock after wall-jumping

	var input_x := Input.get_axis("move_left", "move_right")

	if input_x != 0.0:
		facing_direction = sign(input_x)

	velocity.x = input_x * MOVE_SPEED

# ── Jumping ─────────────────────────────────────────────────────────
func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = JUMP_BUFFER_TIME

	# Grounded / coyote jump
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		_do_jump(JUMP_VELOCITY)
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		is_jumping = true
		emit_signal("jumped")
		return

	# Double jump (unlockable)
	if can_double_jump and not has_double_jumped and not is_on_floor() \
			and Input.is_action_just_pressed("jump"):
		_do_jump(JUMP_VELOCITY * 0.85)
		has_double_jumped = true
		is_jumping = true
		_restart_animation("jump")
		emit_signal("double_jumped")
		return

	# Variable jump height – cut velocity when button released
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= 0.45

func _do_jump(jump_vel: float) -> void:
	velocity.y = jump_vel
	is_ground_pounding = false

# ── Wall Slide & Wall Jump ──────────────────────────────────────────
func _handle_wall_slide(_delta: float) -> void:
	if not can_wall_jump:
		return

	var on_wall := is_on_wall_only()
	if on_wall and velocity.y > 0.0:
		velocity.y = min(velocity.y, WALL_SLIDE_SPEED)

	if on_wall and Input.is_action_just_pressed("jump"):
		var wall_normal := get_wall_normal()
		velocity = Vector2(wall_normal.x * WALL_JUMP_VELOCITY.x, WALL_JUMP_VELOCITY.y)
		facing_direction = sign(wall_normal.x)
		wall_jump_lock = WALL_JUMP_LOCK_TIME
		has_double_jumped = false
		is_jumping = true
		emit_signal("wall_jumped")

# ── Dash ────────────────────────────────────────────────────────────
func _handle_dash_input() -> void:
	if not can_dash:
		return
	if not has_air_dash:
		return
	if dash_cooldown_timer > 0.0:
		return
	if not Input.is_action_just_pressed("dash"):
		return

	var input_x := Input.get_axis("move_left", "move_right")
	dash_direction = Vector2(input_x, 0.0).normalized() if input_x != 0.0 else Vector2(facing_direction, 0.0)
	dash_timer = DASH_DURATION
	is_dashing = true
	has_air_dash = false
	dash_cooldown_timer = DASH_COOLDOWN
	emit_signal("dashed")

func _process_dash(_delta: float) -> void:
	velocity = dash_direction * DASH_SPEED
	dash_timer -= _delta
	if dash_timer <= 0.0:
		is_dashing = false
		# Preserve some momentum after dash
		velocity *= 0.3

# ── Ground Pound (themed: descend *beneath the surface*) ───────────
func _handle_ground_pound_input() -> void:
	if not can_ground_pound:
		return
	if is_on_floor():
		return
	if Input.is_action_just_pressed("ground_pound"):
		velocity = Vector2.ZERO          # brief hang in the air
		is_ground_pounding = true
		emit_signal("ground_pounded")

func _process_ground_pound(_delta: float) -> void:
	velocity.y = GROUND_POUND_SPEED
	velocity.x = 0.0

# ── Landing Detection ──────────────────────────────────────────────
var _was_on_floor := false

func _check_landing() -> void:
	if is_on_floor() and not _was_on_floor:
		if is_ground_pounding:
			_on_ground_pound_impact()
			is_ground_pounding = false
		is_jumping = false
		emit_signal("landed")
	_was_on_floor = is_on_floor()

# ════════════════════════════════════════════════════════════════════
#  SCREEN SHAKE / VIBRATION SYSTEM
# ══════════════════════════════════════════════════════��═════════════

## Called when the ground-pound hits the floor.
func _on_ground_pound_impact() -> void:
	start_screen_shake(SHAKE_INTENSITY, SHAKE_DURATION)
	_trigger_gamepad_rumble()
	emit_signal("ground_pound_landed")

## Public — other systems can call this for explosions, boss slams, etc.
func start_screen_shake(intensity: float, duration: float) -> void:
	shake_intensity = intensity
	shake_timer = duration

func _process_screen_shake(delta: float) -> void:
	if _camera == null:
		_camera = _find_camera()
	if _camera == null:
		return

	if shake_timer > 0.0:
		shake_timer -= delta

		# Exponential decay so the shake feels punchy then fades
		var decay   := exp(-SHAKE_DECAY_RATE * (SHAKE_DURATION - shake_timer))
		var current := shake_intensity * decay

		# High-frequency noise offset
		var offset_x := shake_rng.randf_range(-current, current)
		var offset_y := shake_rng.randf_range(-current, current)
		_camera.offset = Vector2(offset_x, offset_y)
	else:
		# Smoothly return to zero so there's no hard snap
		_camera.offset = _camera.offset.lerp(Vector2.ZERO, 15.0 * delta)

## Trigger haptic feedback on all connected gamepads.
func _trigger_gamepad_rumble() -> void:
	for pad_id in Input.get_connected_joypads():
		Input.start_joy_vibration(pad_id, RUMBLE_WEAK, RUMBLE_STRONG, RUMBLE_DURATION)

# ── Camera helper ───────────────────────────────────────────────────
## Finds the camera: first checks children, then the current viewport camera.
func _find_camera() -> Camera2D:
	# Prefer a Camera2D that's a direct child of the player
	for child in get_children():
		if child is Camera2D:
			return child
	# Fall back to the active camera
	return get_viewport().get_camera_2d()

# ── Animation ──────────────────────────────────────────────────────
func _update_animation() -> void:
	if animated_sprite == null:
		return

	# Flip sprite to face movement direction
	animated_sprite.flip_h = (facing_direction < 0.0)

	if is_ground_pounding:
		_play_if_not("ground_pound")
	elif is_dashing:
		_play_if_not("dash")
	elif is_jumping:
		_play_if_not("jump")
	elif abs(velocity.x) > 10.0:
		_play_if_not("run")
	else:
		_play_if_not("idle")

func _play_if_not(anim_name: String) -> void:
	if animated_sprite.animation != anim_name:
		animated_sprite.play(anim_name)

## Force-restarts an animation even if it's already playing.
func _restart_animation(anim_name: String) -> void:
	if animated_sprite == null:
		return
	animated_sprite.stop()
	animated_sprite.play(anim_name)
