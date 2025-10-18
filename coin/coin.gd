class_name Coin
extends Area2D

var taken = false


func _on_body_enter(body: Node2D) -> void:
	if not taken and body is Player:
		taken = true
		GameManager.collect_coin()
		($AnimationPlayer as AnimationPlayer).play("taken")
