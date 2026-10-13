# res://assets/ui/Avatar.gd
# Avatar circular dibujado por código (sin imágenes). Catálogo de 6 avatares
# predefinidos (CU-01, campo avatar_id = "avatar_01" ... "avatar_06").
@tool
extends Control
class_name Avatar

const CATALOGO := ["avatar_01", "avatar_02", "avatar_03", "avatar_04", "avatar_05", "avatar_06"]
const COLORES := {
	"avatar_01": Color("#2F55E6"),   # persona (azul)
	"avatar_02": Color("#178A4C"),   # lentes (verde)
	"avatar_03": Color("#E8862B"),   # gato (naranja)
	"avatar_04": Color("#7C3AED"),   # robot (morado)
	"avatar_05": Color("#2563EB"),   # estrella (azul)
	"avatar_06": Color("#D9480F"),   # zorro (rojo)
}

@export var avatar_id: String = "avatar_01":
	set(v):
		avatar_id = v
		queue_redraw()
@export var con_borde: bool = true:
	set(v):
		con_borde = v
		queue_redraw()

func _draw() -> void:
	var r := minf(size.x, size.y) / 2.0
	var c := size / 2.0
	var color: Color = COLORES.get(avatar_id, COLORES["avatar_01"])
	if con_borde:
		draw_circle(c, r, Color.WHITE)
		draw_circle(c, r, Color("#E3E6EE"), false, 2.0, true)
		r -= r * 0.09
	draw_circle(c, r, color, true, -1.0, true)
	var w := Color.WHITE
	match avatar_id:
		"avatar_02":   # lentes + sonrisa
			var ojo := r * 0.26
			draw_circle(c + Vector2(-r * 0.36, -r * 0.12), ojo, w, false, r * 0.09, true)
			draw_circle(c + Vector2(r * 0.36, -r * 0.12), ojo, w, false, r * 0.09, true)
			draw_line(c + Vector2(-r * 0.10, -r * 0.12), c + Vector2(r * 0.10, -r * 0.12), w, r * 0.09, true)
			draw_arc(c + Vector2(0, r * 0.18), r * 0.42, deg_to_rad(20), deg_to_rad(160), 24, w, r * 0.09, true)
		"avatar_03":   # gato
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.75, -r * 0.35), c + Vector2(-r * 0.55, -r * 0.95), c + Vector2(-r * 0.25, -r * 0.55)]), w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.75, -r * 0.35), c + Vector2(r * 0.55, -r * 0.95), c + Vector2(r * 0.25, -r * 0.55)]), w)
			draw_circle(c + Vector2(-r * 0.30, -r * 0.08), r * 0.10, w, true, -1.0, true)
			draw_circle(c + Vector2(r * 0.30, -r * 0.08), r * 0.10, w, true, -1.0, true)
			draw_circle(c + Vector2(0, r * 0.22), r * 0.07, w, true, -1.0, true)
			draw_arc(c + Vector2(-r * 0.14, r * 0.22), r * 0.14, deg_to_rad(10), deg_to_rad(170), 12, w, r * 0.07, true)
			draw_arc(c + Vector2(r * 0.14, r * 0.22), r * 0.14, deg_to_rad(10), deg_to_rad(170), 12, w, r * 0.07, true)
		"avatar_04":   # robot
			draw_line(c + Vector2(0, -r * 0.55), c + Vector2(0, -r * 0.9), w, r * 0.08, true)
			draw_circle(c + Vector2(0, -r * 0.92), r * 0.1, w, true, -1.0, true)
			draw_rect(Rect2(c + Vector2(-r * 0.55, -r * 0.45), Vector2(r * 1.1, r * 0.95)), w, false, r * 0.08, true)
			draw_rect(Rect2(c + Vector2(-r * 0.36, -r * 0.22), Vector2(r * 0.2, r * 0.2)), w)
			draw_rect(Rect2(c + Vector2(r * 0.16, -r * 0.22), Vector2(r * 0.2, r * 0.2)), w)
			draw_line(c + Vector2(-r * 0.25, r * 0.22), c + Vector2(r * 0.25, r * 0.22), w, r * 0.08, true)
		"avatar_05":   # estrella
			var pts := PackedVector2Array()
			for i in 10:
				var ang := -PI / 2 + i * PI / 5
				var rr := r * 0.62 if i % 2 == 0 else r * 0.27
				pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
			draw_colored_polygon(pts, w)
		"avatar_06":   # zorro
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.8, -r * 0.5), c + Vector2(-r * 0.5, -r * 1.0), c + Vector2(-r * 0.2, -r * 0.45)]), w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.8, -r * 0.5), c + Vector2(r * 0.5, -r * 1.0), c + Vector2(r * 0.2, -r * 0.45)]), w)
			draw_circle(c + Vector2(-r * 0.3, -r * 0.1), r * 0.11, w, true, -1.0, true)
			draw_circle(c + Vector2(r * 0.3, -r * 0.1), r * 0.11, w, true, -1.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.3, r * 0.2), c + Vector2(r * 0.3, r * 0.2), c + Vector2(0, r * 0.55)]), w)
		_:             # persona (silueta)
			draw_circle(c + Vector2(0, -r * 0.25), r * 0.3, w, true, -1.0, true)
			# cuerpo: círculo recortado dentro del avatar
			var cb := c + Vector2(0, r * 0.85)
			var pts := PackedVector2Array()
			for i in 48:
				var p := cb + Vector2(cos(i * TAU / 48), sin(i * TAU / 48)) * r * 0.58
				if p.distance_to(c) > r * 0.98:
					p = c + (p - c).normalized() * r * 0.98
				pts.append(p)
			draw_colored_polygon(pts, w)
