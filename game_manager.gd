extends Node

signal coin_collected(total_coins)

var coins_collected: int = 0


func collect_coin() -> void:
	coins_collected += 1
	coin_collected.emit(coins_collected)


func reset_coins() -> void:
	coins_collected = 0
	coin_collected.emit(coins_collected)
