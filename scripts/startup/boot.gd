extends Node
## Entry point. The only thing this does is start SceneFlow's sequence --
## everything else lives in the scenes it chains through.


func _ready() -> void:
	SceneFlow.start()
