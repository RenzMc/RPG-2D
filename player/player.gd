class_name Player
extends RigidBody2D

const WALK_ACCEL = 1000.0
const WALK_DEACCEL = 1000.0
const WALK_MAX_VELOCITY = 200.0
const AIR_ACCEL = 250.0
const AIR_DEACCEL = 250.0
const JUMP_VELOCITY = 380.0
const STOP_JUMP_FORCE = 450.0
const SLIDE_SPEED = 300.0
const SLIDE_DURATION = 0.5
const CLIMB_SPEED = 100.0
const GLIDE_GRAVITY_SCALE = 0.3
const MAX_FLOOR_AIRBORNE_TIME = 0.15
const MAX_PENETRATION_DEPTH = 2.0  # Maximum allowed penetration before correction
const GLIDE_MIN_HEIGHT = 150.0
const MAX_JUMPS = 2

const BULLET_SCENE = preload("res://player/bullet.tscn")
const ENEMY_SCENE = preload("res://enemy/enemy.tscn")

var siding_left := false
var jumping := false
var stopping_jump := false
var throwing := false
var sliding := false
var climbing := false
var gliding := false
var attacking := false
var is_dead := false
var jump_count := 0
var can_glide := false
var highest_jump_point := 0.0
var glide_start_height := 0.0

var slide_timer: float = 0.0
var attack_timer: float = 0.0
var throw_timer: float = 0.0

var floor_h_velocity: float = 0.0
var airborne_time: float = 1e20

var can_climb := false
var climb_wall_normal := Vector2.ZERO

@onready var sound_jump := $SoundJump as AudioStreamPlayer2D
@onready var sound_shoot := $SoundShoot as AudioStreamPlayer2D
@onready var animated_sprite := $AnimatedSprite2D as AnimatedSprite2D
@onready var sprite_smoke := animated_sprite.get_node(^"Smoke") as CPUParticles2D
@onready var bullet_shoot := $BulletShoot as Marker2D
@onready var attack_area := $AttackArea as Area2D
@onready var attack_shape := $AttackArea/AttackShape as CollisionShape2D


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if is_dead:
		return

	var velocity := state.get_linear_velocity()
	var step := state.get_step()

	var new_siding_left := siding_left

	# Get player input
	var move_left := Input.is_action_pressed(&"move_left")
	var move_right := Input.is_action_pressed(&"move_right")
	var jump := Input.is_action_just_pressed(&"jump")
	var throw := Input.is_action_just_pressed(&"shoot")
	var attack := Input.is_action_just_pressed(&"attack")
	var slide := Input.is_action_just_pressed(&"slide")
	var climb_input := Input.is_action_pressed(&"climb")
	var spawn := Input.is_action_just_pressed(&"spawn")

	if spawn:
		_spawn_enemy_above.call_deferred()

	# Update timers
	if slide_timer > 0:
		slide_timer -= step
		if slide_timer <= 0:
			sliding = false

	if attack_timer > 0:
		attack_timer -= step
		if attack_timer <= 0:
			attacking = false

	if throw_timer > 0:
		throw_timer -= step
		if throw_timer <= 0:
			throwing = false

	# Deapply prev floor velocity
	velocity.x -= floor_h_velocity
	floor_h_velocity = 0.0

	# Find the floor and check for climbable walls
	var found_floor := false
	var floor_index := -1
	can_climb = false

	for contact_index in state.get_contact_count():
		var collision_normal = state.get_contact_local_normal(contact_index)

		# Check for floor
		if collision_normal.dot(Vector2(0, -1)) > 0.6:
			found_floor = true
			floor_index = contact_index

		# Check for climbable walls (vertical surfaces)
		if abs(collision_normal.x) > 0.9 and abs(collision_normal.y) < 0.3:
			can_climb = true
			climb_wall_normal = collision_normal

	if found_floor:
		airborne_time = 0.0
		gliding = false
		climbing = false
		jump_count = 0
		can_glide = false
		highest_jump_point = position.y
		glide_start_height = position.y
	else:
		airborne_time += step
		# Set glide start height when first leaving ground
		if airborne_time == step:
			glide_start_height = position.y

	var on_floor := airborne_time < MAX_FLOOR_AIRBORNE_TIME

	# Handle climbing
	if can_climb and climb_input and not on_floor and not sliding:
		climbing = true
		velocity.y = -CLIMB_SPEED
		velocity.x = 0
		gliding = false
	elif climbing and (not can_climb or not climb_input or on_floor):
		climbing = false

	# Handle throwing (ranged attack)
	if throw and not throwing and not attacking and throw_timer <= 0:
		_shot_bullet.call_deferred()
		throwing = true
		throw_timer = 0.5

	# Handle melee attack (close range)
	if attack and on_floor and not attacking and not sliding and not throwing:
		attacking = true
		attack_timer = 0.6
		_play_animation("attack")
		_perform_attack.call_deferred()

	# Handle slide
	if slide and on_floor and not sliding and not attacking:
		sliding = true
		slide_timer = SLIDE_DURATION
		_play_animation("slide")

	# Handle gliding (height-based activation) - IMPROVED LOGIC
	if not on_floor and velocity.y > 0 and not climbing:
		# Calculate how far we've fallen from the glide start point
		# In Godot, positive Y is DOWN, so falling means position.y increases
		var height_fallen = position.y - glide_start_height
		
		# Glide activates when:
		# 1. We're falling (velocity.y > 0)
		# 2. We've fallen enough distance (height_fallen > GLIDE_MIN_HEIGHT)
		# 3. Climb button is held
		if height_fallen > GLIDE_MIN_HEIGHT and climb_input:
			gliding = true
		elif not climb_input:
			gliding = false
	else:
		# Stop gliding when on floor, climbing, or moving upward
		gliding = false
		if on_floor:
			glide_start_height = position.y

	# Process jump
	if jumping:
		if velocity.y > 0:
			jumping = false
		elif not jump:
			stopping_jump = true

		if stopping_jump:
			velocity.y += STOP_JUMP_FORCE * step

	# Handle movement based on state
	if climbing:
		# Climbing movement handled above
		pass
	elif sliding:
		# Sliding movement
		var slide_direction = -1.0 if siding_left else 1.0
		velocity.x = slide_direction * SLIDE_SPEED
	elif on_floor:
		# Ground movement
		if move_left and not move_right and not attacking:
			if velocity.x > -WALK_MAX_VELOCITY:
				velocity.x -= WALK_ACCEL * step
		elif move_right and not move_left and not attacking:
			if velocity.x < WALK_MAX_VELOCITY:
				velocity.x += WALK_ACCEL * step
		else:
			var xv := absf(velocity.x)
			xv -= WALK_DEACCEL * step
			if xv < 0:
				xv = 0
			velocity.x = signf(velocity.x) * xv

		# Check jump
		if not jumping and jump and not attacking and not sliding:
			velocity.y = -JUMP_VELOCITY
			jumping = true
			stopping_jump = false
			jump_count = 1
			highest_jump_point = position.y
			sound_jump.play()

		# Check siding
		if velocity.x < 0 and move_left:
			new_siding_left = true
		elif velocity.x > 0 and move_right:
			new_siding_left = false
	else:
		# Air movement
		if move_left and not move_right:
			if velocity.x > -WALK_MAX_VELOCITY:
				velocity.x -= AIR_ACCEL * step
		elif move_right and not move_left:
			if velocity.x < WALK_MAX_VELOCITY:
				velocity.x += AIR_ACCEL * step
		else:
			var xv := absf(velocity.x)
			xv -= AIR_DEACCEL * step

			if xv < 0:
				xv = 0
			velocity.x = signf(velocity.x) * xv

		# Check for double jump
		if jump and not jumping and jump_count < MAX_JUMPS and not attacking and not sliding:
			velocity.y = -JUMP_VELOCITY
			jumping = true
			stopping_jump = false
			jump_count += 1
			if jump_count >= MAX_JUMPS:
				can_glide = true
			if position.y < highest_jump_point:
				highest_jump_point = position.y
			sound_jump.play()

	# Update siding
	if new_siding_left != siding_left:
		if new_siding_left:
			animated_sprite.flip_h = true
		else:
			animated_sprite.flip_h = false

		siding_left = new_siding_left

	# Update animation based on state
	if not attacking and not sliding:
		_update_animation(on_floor, velocity)

	# Apply floor velocity
	if found_floor:
		floor_h_velocity = state.get_contact_collider_velocity_at_position(floor_index).x
		velocity.x += floor_h_velocity

	# Apply gravity (reduced for gliding, none for climbing)
	var gravity = state.get_total_gravity()
	if climbing:
		gravity = Vector2.ZERO
	elif gliding:
		gravity *= GLIDE_GRAVITY_SCALE

	velocity += gravity * step
	state.set_linear_velocity(velocity)


func _update_animation(on_floor: bool, velocity: Vector2) -> void:
	if climbing:
		_play_animation("climb")
	elif on_floor:
		if absf(velocity.x) < 0.1:
			if throwing:
				_play_animation("throw")
			else:
				_play_animation("idle")
		else:
			if throwing:
				_play_animation("throw")
			else:
				_play_animation("run")
	else:
		if gliding:
			_play_animation("glide")
		elif velocity.y < 0:
			if throwing:
				_play_animation("jump_throw")
			elif attacking:
				_play_animation("jump_attack")
			else:
				_play_animation("jump")
		else:
			if throwing:
				_play_animation("jump_throw")
			elif attacking:
				_play_animation("jump_attack")
			else:
				_play_animation("jump")


func _play_animation(anim_name: String) -> void:
	if animated_sprite.animation != anim_name:
		animated_sprite.play(anim_name)


func _shot_bullet() -> void:
	var bullet := BULLET_SCENE.instantiate() as RigidBody2D
	var speed_scale: float
	if siding_left:
		speed_scale = -1.0
	else:
		speed_scale = 1.0

	bullet.position = position + bullet_shoot.position * Vector2(speed_scale, 1.0)
	get_parent().add_child(bullet)

	bullet.linear_velocity = Vector2(400.0 * speed_scale, -40)

	sprite_smoke.restart()
	sound_shoot.play()

	add_collision_exception_with(bullet)


func _spawn_enemy_above() -> void:
	var enemy := ENEMY_SCENE.instantiate() as RigidBody2D
	enemy.position = position + 50 * Vector2.UP
	get_parent().add_child(enemy)


func die() -> void:
	if not is_dead:
		is_dead = true
		_play_animation("dead")


func _perform_attack() -> void:
	# Enable attack hitbox temporarily
	attack_shape.disabled = false

	# Position attack hitbox based on facing direction
	if siding_left:
		attack_shape.position.x = -12
	else:
		attack_shape.position.x = 12

	# Wait a frame for physics to update
	await get_tree().process_frame

	# Check for enemies in attack range multiple times during attack animation
	for i in range(3):
		var bodies := attack_area.get_overlapping_bodies()
		for body in bodies:
			if body is Enemy:
				body._take_damage()
		await get_tree().create_timer(0.1).timeout

	# Disable attack hitbox
	attack_shape.disabled = true