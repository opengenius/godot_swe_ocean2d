extends Sprite2D

var tween: Tween
const SPEED = 4.0

func _ready():
	var spos := self.position
	
	tween = get_tree().create_tween()
	tween.tween_property(self, "position", spos + Vector2(-50, 0), 8.0)
	tween.tween_property(self, "position", spos + Vector2(0, 0), 8.0)
	tween.set_loops()

func move_to(target_pos: Vector2):
	if tween != null:
		tween.kill()
		
	var time := (target_pos - position).length() / SPEED
		
	tween = get_tree().create_tween()
	tween.tween_property(self, "position", target_pos, time)
