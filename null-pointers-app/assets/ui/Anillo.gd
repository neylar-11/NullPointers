# res://assets/ui/Anillo.gd
# Anillo de porcentaje (pantalla de resultados CU-03). Dibujado por código.
@tool
extends Control
class_name Anillo

@export_range(0, 100) var porcentaje: float = 0.0:
	set(v):
		porcentaje = v
		queue_redraw()
@export var color: Color = Color("#178A4C"):
	set(v):
		color = v
		queue_redraw()
@export var color_fondo: Color = Color("#E3E6EE"):
	set(v):
		color_fondo = v
		queue_redraw()
@export var grosor: float = 12.0:
	set(v):
		grosor = v
		queue_redraw()

func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - grosor / 2.0
	draw_arc(c, r, 0, TAU, 64, color_fondo, grosor, true)
	if porcentaje > 0:
		var fin := -PI / 2 + TAU * clampf(porcentaje, 0, 100) / 100.0
		draw_arc(c, r, -PI / 2, fin, 64, color, grosor, true)
		# puntas redondeadas
		draw_circle(c + Vector2(0, -r), grosor / 2.0, color, true, -1.0, true)
		draw_circle(c + Vector2(cos(fin), sin(fin)) * r, grosor / 2.0, color, true, -1.0, true)
