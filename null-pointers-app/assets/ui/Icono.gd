# res://assets/ui/Icono.gd
# Iconos sencillos dibujados por código (sin imágenes ni fuentes extra).
# Uso: nodo Control con este script, propiedad `tipo` y `color`.
@tool
extends Control
class_name Icono

const TIPOS := ["check", "candado", "play", "cerrar", "alerta", "estrella", "info", "grafica",
	"flecha_izq", "flecha_der", "camara", "lapiz", "mapa", "libro", "reiniciar", "ojo", "puzzle", "quiz", "progreso"]

@export var tipo: String = "check":
	set(v):
		tipo = v
		queue_redraw()
@export var color: Color = Color("#15192B"):
	set(v):
		color = v
		queue_redraw()
@export var grosor: float = 2.5:
	set(v):
		grosor = v
		queue_redraw()
## Fondo circular opcional (ej. palomita verde con círculo)
@export var fondo: Color = Color(0, 0, 0, 0):
	set(v):
		fondo = v
		queue_redraw()

func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size / 2.0
	if fondo.a > 0:
		draw_circle(c, s / 2.0, fondo, true, -1.0, true)
	var u := s * (0.5 if fondo.a > 0 else 0.7)   # radio útil
	var g := grosor
	match tipo:
		"radio":
			draw_circle(c, u * 0.5, color, false, g, true)
		"radio_sel":
			draw_circle(c, u * 0.5, color, false, g, true)
			draw_circle(c, u * 0.26, color, true, -1.0, true)
		"guardar":
			draw_rect(Rect2(c + Vector2(-u * 0.55, -u * 0.55), Vector2(u * 1.1, u * 1.1)), color, false, g, true)
			draw_rect(Rect2(c + Vector2(-u * 0.3, -u * 0.55), Vector2(u * 0.6, u * 0.35)), color, false, g, true)
			draw_rect(Rect2(c + Vector2(-u * 0.3, u * 0.1), Vector2(u * 0.6, u * 0.45)), color, true)
		"check":
			draw_polyline(PackedVector2Array([c + Vector2(-u * 0.55, 0.02 * u), c + Vector2(-u * 0.15, u * 0.42), c + Vector2(u * 0.6, -u * 0.42)]), color, g, true)
		"cerrar":
			draw_line(c + Vector2(-u * 0.45, -u * 0.45), c + Vector2(u * 0.45, u * 0.45), color, g, true)
			draw_line(c + Vector2(-u * 0.45, u * 0.45), c + Vector2(u * 0.45, -u * 0.45), color, g, true)
		"candado":
			draw_arc(c + Vector2(0, -u * 0.25), u * 0.32, PI, TAU, 16, color, g, true)
			draw_line(c + Vector2(-u * 0.32, -u * 0.25), c + Vector2(-u * 0.32, 0), color, g, true)
			draw_line(c + Vector2(u * 0.32, -u * 0.25), c + Vector2(u * 0.32, 0), color, g, true)
			draw_rect(Rect2(c + Vector2(-u * 0.52, 0), Vector2(u * 1.04, u * 0.72)), color, true)
		"play":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.35, -u * 0.5), c + Vector2(u * 0.55, 0), c + Vector2(-u * 0.35, u * 0.5)]), color)
		"alerta":
			var tri := PackedVector2Array([c + Vector2(0, -u * 0.6), c + Vector2(u * 0.68, u * 0.5), c + Vector2(-u * 0.68, u * 0.5), c + Vector2(0, -u * 0.6)])
			draw_polyline(tri, color, g, true)
			draw_line(c + Vector2(0, -u * 0.15), c + Vector2(0, u * 0.15), color, g, true)
			draw_circle(c + Vector2(0, u * 0.33), g * 0.6, color)
		"estrella":
			var pts := PackedVector2Array()
			for i in 10:
				var ang := -PI / 2 + i * PI / 5
				var rr := u * 0.68 if i % 2 == 0 else u * 0.3
				pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
			pts.append(pts[0])
			draw_polyline(pts, color, g, true)
		"info":
			draw_circle(c, u * 0.62, color, false, g, true)
			draw_line(c + Vector2(0, -u * 0.05), c + Vector2(0, u * 0.3), color, g, true)
			draw_circle(c + Vector2(0, -u * 0.3), g * 0.55, color)
		"grafica", "progreso":
			draw_line(c + Vector2(-u * 0.6, u * 0.55), c + Vector2(u * 0.6, u * 0.55), color, g, true)
			draw_line(c + Vector2(-u * 0.35, u * 0.4), c + Vector2(-u * 0.35, -u * 0.05), color, g * 1.6, true)
			draw_line(c + Vector2(0, u * 0.4), c + Vector2(0, -u * 0.5), color, g * 1.6, true)
			draw_line(c + Vector2(u * 0.35, u * 0.4), c + Vector2(u * 0.35, -u * 0.25), color, g * 1.6, true)
		"flecha_izq":
			draw_polyline(PackedVector2Array([c + Vector2(u * 0.25, -u * 0.5), c + Vector2(-u * 0.25, 0), c + Vector2(u * 0.25, u * 0.5)]), color, g, true)
		"flecha_der":
			draw_polyline(PackedVector2Array([c + Vector2(-u * 0.25, -u * 0.5), c + Vector2(u * 0.25, 0), c + Vector2(-u * 0.25, u * 0.5)]), color, g, true)
		"camara":
			draw_rect(Rect2(c + Vector2(-u * 0.65, -u * 0.35), Vector2(u * 1.3, u * 0.9)), color, false, g, true)
			draw_circle(c + Vector2(0, u * 0.1), u * 0.25, color, false, g, true)
			draw_line(c + Vector2(-u * 0.25, -u * 0.35), c + Vector2(-u * 0.15, -u * 0.55), color, g, true)
			draw_line(c + Vector2(-u * 0.15, -u * 0.55), c + Vector2(u * 0.15, -u * 0.55), color, g, true)
			draw_line(c + Vector2(u * 0.15, -u * 0.55), c + Vector2(u * 0.25, -u * 0.35), color, g, true)
		"lapiz":
			draw_line(c + Vector2(-u * 0.5, u * 0.5), c + Vector2(u * 0.35, -u * 0.35), color, g * 2.2, true)
			draw_line(c + Vector2(u * 0.35, -u * 0.35), c + Vector2(u * 0.55, -u * 0.55), color, g * 2.2, true)
			draw_line(c + Vector2(-u * 0.6, u * 0.6), c + Vector2(-u * 0.5, u * 0.5), color, g, true)
		"mapa":
			draw_polyline(PackedVector2Array([c + Vector2(-u * 0.6, -u * 0.4), c + Vector2(-u * 0.2, -u * 0.55), c + Vector2(u * 0.2, -u * 0.4), c + Vector2(u * 0.6, -u * 0.55), c + Vector2(u * 0.6, u * 0.4), c + Vector2(u * 0.2, u * 0.55), c + Vector2(-u * 0.2, u * 0.4), c + Vector2(-u * 0.6, u * 0.55), c + Vector2(-u * 0.6, -u * 0.4)]), color, g, true)
			draw_line(c + Vector2(-u * 0.2, -u * 0.55), c + Vector2(-u * 0.2, u * 0.4), color, g, true)
			draw_line(c + Vector2(u * 0.2, -u * 0.4), c + Vector2(u * 0.2, u * 0.55), color, g, true)
		"libro":
			draw_rect(Rect2(c + Vector2(-u * 0.6, -u * 0.5), Vector2(u * 1.2, u * 1.0)), color, false, g, true)
			draw_line(c + Vector2(0, -u * 0.5), c + Vector2(0, u * 0.5), color, g, true)
			draw_line(c + Vector2(-u * 0.42, -u * 0.2), c + Vector2(-u * 0.18, -u * 0.2), color, g, true)
			draw_line(c + Vector2(-u * 0.42, 0), c + Vector2(-u * 0.18, 0), color, g, true)
		"reiniciar":
			draw_arc(c, u * 0.55, deg_to_rad(-60), deg_to_rad(240), 24, color, g, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(u * 0.1, -u * 0.75), c + Vector2(u * 0.45, -u * 0.45), c + Vector2(u * 0.05, -u * 0.3)]), color)
		"ojo":
			draw_arc(c + Vector2(0, u * 0.35), u * 0.75, deg_to_rad(215), deg_to_rad(325), 20, color, g, true)
			draw_arc(c + Vector2(0, -u * 0.35), u * 0.75, deg_to_rad(35), deg_to_rad(145), 20, color, g, true)
			draw_circle(c, u * 0.2, color, true, -1.0, true)
		"puzzle":
			draw_rect(Rect2(c + Vector2(-u * 0.6, -u * 0.6), Vector2(u * 0.5, u * 0.5)), color, false, g, true)
			draw_rect(Rect2(c + Vector2(u * 0.1, -u * 0.6), Vector2(u * 0.5, u * 0.5)), color, false, g, true)
			draw_rect(Rect2(c + Vector2(-u * 0.6, u * 0.1), Vector2(u * 0.5, u * 0.5)), color, false, g, true)
			draw_rect(Rect2(c + Vector2(u * 0.1, u * 0.1), Vector2(u * 0.5, u * 0.5)), color, true)
		"quiz":
			draw_rect(Rect2(c + Vector2(-u * 0.5, -u * 0.6), Vector2(u * 1.0, u * 1.2)), color, false, g, true)
			draw_polyline(PackedVector2Array([c + Vector2(-u * 0.25, 0), c + Vector2(-u * 0.05, u * 0.2), c + Vector2(u * 0.3, -u * 0.2)]), color, g, true)
			draw_line(c + Vector2(-u * 0.2, -u * 0.6), c + Vector2(u * 0.2, -u * 0.6), color, g * 2.0, true)
