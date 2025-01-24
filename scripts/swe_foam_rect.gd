extends TextureRect

@export var swe: SWESimulation

# Called when the node enters the scene tree for the first time.
func _ready():
	texture = swe.foam_texture


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
