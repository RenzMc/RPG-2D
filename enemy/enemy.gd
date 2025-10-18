class_name Enemy
extends RigidBody2D

enum State {
	WALKING,
	DYING,
}

const WALK_SPEED = 50
const MAX_HEALTH = 3  # Enemy needs 3 hits to die

# Use load instead of preload to avoid "Busy" errors
var COIN_SCENE: PackedScene = null

var direction := -1
var anim := ""
var _state := State.WALKING
var health := MAX_HEALTH  # Current health

@onready var rc_left := $RaycastLeft as RayCast2D
@onready var rc_right := $RaycastRight as RayCast2D
@onready var health_bar := $HealthBarContainer/HealthBarForeground as ColorRect


func _ready() -> void:
	# Load coin scene at runtime to avoid "Busy" errors
	COIN_SCENE = load("res://coin/coin.tscn")
	_update_health_bar()


func _update_health_bar() -> void:
	if health_bar:
		var health_percent = float(health) / float(MAX_HEALTH)
		health_bar.scale.x = health_percent
		# Change color based on health
		if health_percent > 0.6:
			health_bar.color = Color(0.2, 0.8, 0.2, 1)  # Green
		elif health_percent > 0.3:
			health_bar.color = Color(0.9, 0.9, 0.2, 1)  # Yellow
		else:
			health_bar.color = Color(0.8, 0.2, 0.2, 1)  # Red


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var velocity := state.get_linear_velocity()
	var new_anim := anim

	if _state == State.DYING:
		new_anim = "explode"
	elif _state == State.WALKING:
		new_anim = "walk"

		var wall_side := 0.0

		for collider_index in state.get_contact_count():
			var collider := state.get_contact_collider_object(collider_index)
			var collision_normal := state.get_contact_local_normal(collider_index)

			if collider is Bullet and not (collider as Bullet).disabled:
				_bullet_collider.call_deferred(collider, state, collision_normal)
				break

			if collision_normal.x > 0.9:
				wall_side = 1.0
			elif collision_normal.x < -0.9:
				wall_side = -1.0

		if wall_side != 0 and wall_side != direction:
			direction = -direction
			($Sprite2D as Sprite2D).scale.x = -direction
		if direction < 0 and not rc_left.is_colliding() and rc_right.is_colliding():
			direction = -direction
			($Sprite2D as Sprite2D).scale.x = -direction
		elif direction > 0 and not rc_right.is_colliding() and rc_left.is_colliding():
			direction = -direction
			($Sprite2D as Sprite2D).scale.x = -direction

		velocity.x = direction * WALK_SPEED

	if anim != new_anim:
		anim = new_anim
		($AnimationPlayer as AnimationPlayer).play(anim)

	state.set_linear_velocity(velocity)


func _die() -> void:
	queue_free()


func _pre_explode() -> void:
	# Make sure nothing collides against this.
	$Shape1.queue_free()
	$Shape2.queue_free()
	$Shape3.queue_free()

	($SoundExplode as AudioStreamPlayer2D).play()


func _bullet_collider(
	collider: Bullet, state: PhysicsDirectBodyState2D, collision_normal: Vector2
) -> void:
	_state = State.DYING

	state.set_angular_velocity(signf(collision_normal.x) * 33.0)
	physics_material_override.friction = 1
	collider.disable()
	($SoundHit as AudioStreamPlayer2D).play()


func _take_damage() -> void:
	if _state == State.DYING:
		return
	
	# Play hit sound
	($SoundHit as AudioStreamPlayer2D).play()
	
	# Reduce health
	health -= 1
	_update_health_bar()
	
	# Visual feedback - flash red
	var sprite := $Sprite2D as Sprite2D
	var original_modulate = sprite.modulate
	sprite.modulate = Color(1, 0.3, 0.3, 1)
	await get_tree().create_timer(0.1).timeout
	sprite.modulate = original_modulate
	
	# Check if enemy should die
	if health <= 0:
		_state = State.DYING
		physics_material_override.friction = 1
		
		# Disable collision shapes
		$Shape1.set_deferred("disabled", true)
		$Shape2.set_deferred("disabled", true)
		$Shape3.set_deferred("disabled", true)
		
		# Spawn coin at enemy position
		_spawn_coin()
		
		# Final death flash
		sprite.modulate = Color(1, 0.3, 0.3, 1)
		await get_tree().create_timer(0.1).timeout
		sprite.modulate = Color(1, 1, 1, 1)
		
		# Wait a bit then remove enemy
		await get_tree().create_timer(0.3).timeout
		queue_free()


func _spawn_coin() -> void:
	# Check if COIN_SCENE is loaded
	if not COIN_SCENE:
		push_error("COIN_SCENE not loaded")
		return
	
	# Verify the scene can be instantiated
	if not COIN_SCENE.can_instantiate():
		push_error("COIN_SCENE cannot be instantiated")
		return
	
	# Create coin instance
	var coin = COIN_SCENE.instantiate()
	
	# Verify instantiation succeeded
	if not coin:
		push_error("Failed to instantiate coin")
		return
	
	# Set coin position to enemy's current position
	coin.global_position = global_position
	
	# Add coin to the same parent as the enemy (the stage/level)
	# Using call_deferred to avoid physics conflicts during _integrate_forces
	if get_parent():
		get_parent().call_deferred("add_child", coin)
	else:
		push_error("Enemy has no parent to add coin to")