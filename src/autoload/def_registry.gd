extends Node
## Global read-only content catalog.

var catalog: DefCatalog = DefCatalog.new()


func _init() -> void:
	catalog.load_all()
