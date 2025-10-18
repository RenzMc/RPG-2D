extends Node2D

@onready var coin_label: Label = $CoinUI/CoinCounter/CoinLabel


func _ready() -> void:
	GameManager.coin_collected.connect(_on_coin_collected)
	_update_coin_display()


func _on_coin_collected(_total_coins: int) -> void:
	_update_coin_display()


func _update_coin_display() -> void:
	coin_label.text = "x " + str(GameManager.coins_collected)
