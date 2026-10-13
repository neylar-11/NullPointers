# res://assets/ui/Lienzo.gd
# Control que dibuja líneas punteadas entre puntos (conectores del mapa CU-02).
extends Control
class_name Lienzo

## Cada segmento: {"a": Vector2, "b": Vector2, "color": Color}
var segmentos: Array = []

func limpiar() -> void:
	segmentos.clear()
	queue_redraw()

func agregar(a: Vector2, b: Vector2, color: Color) -> void:
	segmentos.append({"a": a, "b": b, "color": color})
	queue_redraw()

func _draw() -> void:
	for s in segmentos:
		draw_dashed_line(s["a"], s["b"], s["color"], 5.0, 14.0, true, true)
