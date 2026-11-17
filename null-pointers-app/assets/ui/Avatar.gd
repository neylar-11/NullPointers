# res://assets/ui/Avatar.gd
# Avatar circular dibujado por código (sin imágenes).
# Catálogo de 14 avatares (CU-01, campo avatar_id = "avatar_01" ... "avatar_14"):
#   - 6 básicos disponibles desde el inicio.
#   - 8 que se desbloquean al avanzar en la app (JuegoRepository.avatar_disponible).
@tool
extends Control
class_name Avatar

## Catálogo con nombre, condición de desbloqueo (requisito) y texto para la pantalla de perfil.
## requisito = {"tipo": ..., "valor": n}; tipo "" = disponible desde el inicio.
##   temas_completos  : temas con sus 3 módulos completados
##   temas_dominados  : temas con la práctica de ingeniero aprobada
##   modulos_perfectos: módulos con 100 % como mejor puntaje
##   sin_pistas       : módulos completados sin usar pistas
##   oros             : medallas de tema en nivel oro
##   intentos         : retos terminados
const CATALOGO := [
	{"id": "avatar_01", "nombre": "Persona", "requisito": {"tipo": "", "valor": 0}, "condicion": "Disponible desde el inicio"},
	{"id": "avatar_02", "nombre": "Lentes", "requisito": {"tipo": "", "valor": 0}, "condicion": "Disponible desde el inicio"},
	{"id": "avatar_03", "nombre": "Gato", "requisito": {"tipo": "", "valor": 0}, "condicion": "Disponible desde el inicio"},
	{"id": "avatar_04", "nombre": "Robot", "requisito": {"tipo": "", "valor": 0}, "condicion": "Disponible desde el inicio"},
	{"id": "avatar_05", "nombre": "Estrella", "requisito": {"tipo": "", "valor": 0}, "condicion": "Disponible desde el inicio"},
	{"id": "avatar_06", "nombre": "Zorro", "requisito": {"tipo": "", "valor": 0}, "condicion": "Disponible desde el inicio"},
	{"id": "avatar_07", "nombre": "Búho", "requisito": {"tipo": "temas_completos", "valor": 1}, "condicion": "Completa los 3 módulos de un tema"},
	{"id": "avatar_08", "nombre": "Bombilla", "requisito": {"tipo": "intentos", "valor": 10}, "condicion": "Termina 10 retos"},
	{"id": "avatar_09", "nombre": "Ninja", "requisito": {"tipo": "sin_pistas", "valor": 3}, "condicion": "Completa 3 módulos sin usar pistas"},
	{"id": "avatar_10", "nombre": "Cohete", "requisito": {"tipo": "temas_completos", "valor": 3}, "condicion": "Completa 3 temas"},
	{"id": "avatar_11", "nombre": "Astronauta", "requisito": {"tipo": "temas_dominados", "valor": 1}, "condicion": "Domina un tema (aprueba su práctica de ingeniero)"},
	{"id": "avatar_12", "nombre": "Diamante", "requisito": {"tipo": "oros", "valor": 3}, "condicion": "Consigue 3 medallas de oro"},
	{"id": "avatar_13", "nombre": "Corona", "requisito": {"tipo": "temas_dominados", "valor": 6}, "condicion": "Domina 6 temas"},
	{"id": "avatar_14", "nombre": "Trofeo", "requisito": {"tipo": "temas_dominados", "valor": 12}, "condicion": "Domina los 12 temas"},
]

const COLORES := {
	"avatar_01": Color("#2F55E6"),   # persona (azul)
	"avatar_02": Color("#178A4C"),   # lentes (verde)
	"avatar_03": Color("#E8862B"),   # gato (naranja)
	"avatar_04": Color("#7C3AED"),   # robot (morado)
	"avatar_05": Color("#2563EB"),   # estrella (azul)
	"avatar_06": Color("#D9480F"),   # zorro (rojo)
	"avatar_07": Color("#0E7490"),   # búho (teal)
	"avatar_08": Color("#F59E0B"),   # bombilla (ámbar)
	"avatar_09": Color("#1F2937"),   # ninja (gris oscuro)
	"avatar_10": Color("#DC2626"),   # cohete (rojo)
	"avatar_11": Color("#1D4ED8"),   # astronauta (azul profundo)
	"avatar_12": Color("#0891B2"),   # diamante (cian)
	"avatar_13": Color("#7C2D12"),   # corona (vino)
	"avatar_14": Color("#B45309"),   # trofeo (dorado oscuro)
}

static func ids() -> Array:
	var lista: Array = []
	for a in CATALOGO:
		lista.append(a["id"])
	return lista

static func info(id: String) -> Dictionary:
	for a in CATALOGO:
		if a["id"] == id:
			return a
	return CATALOGO[0]

@export var avatar_id: String = "avatar_01":
	set(v):
		avatar_id = v
		queue_redraw()
@export var con_borde: bool = true:
	set(v):
		con_borde = v
		queue_redraw()
## Dibuja el avatar en gris (bloqueado en el catálogo del perfil).
@export var bloqueado: bool = false:
	set(v):
		bloqueado = v
		queue_redraw()

func _draw() -> void:
	var r := minf(size.x, size.y) / 2.0
	var c := size / 2.0
	var color: Color = COLORES.get(avatar_id, COLORES["avatar_01"])
	if bloqueado:
		color = Color("#C9CDD9")
	if con_borde:
		draw_circle(c, r, Color.WHITE)
		draw_circle(c, r, Color("#E3E6EE"), false, 2.0, true)
		r -= r * 0.09
	draw_circle(c, r, color, true, -1.0, true)
	var w := Color.WHITE if not bloqueado else Color("#F5F6FA")
	# Los avatares desbloqueables tienen un "brillo" (círculo claro arriba a la izquierda)
	if int(avatar_id.substr(7)) >= 7 and not bloqueado:
		draw_circle(c + Vector2(-r * 0.35, -r * 0.35), r * 0.42, Color(1, 1, 1, 0.14), true, -1.0, true)
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
			draw_colored_polygon(_estrella(c, r * 0.62, r * 0.27, 5), w)
		"avatar_06":   # zorro
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.8, -r * 0.5), c + Vector2(-r * 0.5, -r * 1.0), c + Vector2(-r * 0.2, -r * 0.45)]), w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.8, -r * 0.5), c + Vector2(r * 0.5, -r * 1.0), c + Vector2(r * 0.2, -r * 0.45)]), w)
			draw_circle(c + Vector2(-r * 0.3, -r * 0.1), r * 0.11, w, true, -1.0, true)
			draw_circle(c + Vector2(r * 0.3, -r * 0.1), r * 0.11, w, true, -1.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.3, r * 0.2), c + Vector2(r * 0.3, r * 0.2), c + Vector2(0, r * 0.55)]), w)
		"avatar_07":   # búho: orejas, ojos grandes con pupila, pico, pecho
			var oscuro := color.darkened(0.35) if not bloqueado else Color("#A8ADBD")
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.62, -r * 0.35), c + Vector2(-r * 0.52, -r * 0.9), c + Vector2(-r * 0.18, -r * 0.5)]), w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.62, -r * 0.35), c + Vector2(r * 0.52, -r * 0.9), c + Vector2(r * 0.18, -r * 0.5)]), w)
			draw_circle(c + Vector2(0, r * 0.35), r * 0.45, w.darkened(0.06), true, -1.0, true)   # pecho
			for lado in [-1, 1]:
				var ojo := c + Vector2(lado * r * 0.3, -r * 0.15)
				draw_circle(ojo, r * 0.28, w, true, -1.0, true)
				draw_circle(ojo, r * 0.28, oscuro, false, r * 0.05, true)
				draw_circle(ojo + Vector2(lado * r * 0.04, r * 0.02), r * 0.12, oscuro, true, -1.0, true)
				draw_circle(ojo + Vector2(lado * r * 0.0, -r * 0.04), r * 0.04, w, true, -1.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.1, r * 0.1), c + Vector2(r * 0.1, r * 0.1), c + Vector2(0, r * 0.3)]), Color("#F59E0B") if not bloqueado else oscuro)
		"avatar_08":   # bombilla: foco con rayos
			var claro := Color("#FDE68A") if not bloqueado else w
			for i in 8:
				var ang := i * TAU / 8
				draw_line(c + Vector2(cos(ang), sin(ang)) * r * 0.72, c + Vector2(cos(ang), sin(ang)) * r * 0.9, Color(1, 1, 1, 0.8), r * 0.06, true)
			draw_circle(c + Vector2(0, -r * 0.12), r * 0.4, claro, true, -1.0, true)
			draw_circle(c + Vector2(0, -r * 0.12), r * 0.4, w, false, r * 0.06, true)
			draw_rect(Rect2(c + Vector2(-r * 0.18, r * 0.24), Vector2(r * 0.36, r * 0.14)), w)
			draw_rect(Rect2(c + Vector2(-r * 0.14, r * 0.42), Vector2(r * 0.28, r * 0.1)), w)
			# filamento
			draw_line(c + Vector2(-r * 0.12, r * 0.2), c + Vector2(-r * 0.06, -r * 0.05), color.darkened(0.2) if not bloqueado else Color("#A8ADBD"), r * 0.05, true)
			draw_line(c + Vector2(-r * 0.06, -r * 0.05), c + Vector2(r * 0.06, -r * 0.05), color.darkened(0.2) if not bloqueado else Color("#A8ADBD"), r * 0.05, true)
			draw_line(c + Vector2(r * 0.06, -r * 0.05), c + Vector2(r * 0.12, r * 0.2), color.darkened(0.2) if not bloqueado else Color("#A8ADBD"), r * 0.05, true)
		"avatar_09":   # ninja: cabeza, banda roja y ojos
			var banda := Color("#DC2626") if not bloqueado else Color("#A8ADBD")
			draw_circle(c + Vector2(0, -r * 0.05), r * 0.62, w.darkened(0.08), true, -1.0, true)
			draw_rect(Rect2(c + Vector2(-r * 0.62, -r * 0.3), Vector2(r * 1.24, r * 0.3)), banda)
			draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.12), Vector2(r * 1.2, r * 0.42)), color)   # máscara
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.55, -r * 0.28), c + Vector2(r * 0.95, -r * 0.5), c + Vector2(r * 0.9, -r * 0.1)]), banda)
			for lado in [-1, 1]:
				var ojo := c + Vector2(lado * r * 0.26, r * 0.06)
				draw_arc(ojo, r * 0.12, deg_to_rad(200), deg_to_rad(340), 12, w, r * 0.07, true)
		"avatar_10":   # cohete: cuerpo, ventana, aletas y fuego
			var fuego := Color("#F59E0B") if not bloqueado else Color("#A8ADBD")
			var ventana := color.darkened(0.3) if not bloqueado else Color("#A8ADBD")
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.22, r * 0.45), c + Vector2(0, r * 0.95), c + Vector2(r * 0.22, r * 0.45)]), fuego)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.3, r * 0.1), c + Vector2(-r * 0.62, r * 0.55), c + Vector2(-r * 0.3, r * 0.5)]), w.darkened(0.12))
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.3, r * 0.1), c + Vector2(r * 0.62, r * 0.55), c + Vector2(r * 0.3, r * 0.5)]), w.darkened(0.12))
			var cuerpo := PackedVector2Array()
			cuerpo.append(c + Vector2(0, -r * 0.9))
			for i in 9:
				var ang := -PI / 2 + (i + 1) * (PI / 2) / 9
				cuerpo.append(c + Vector2(cos(ang) * r * 0.3, -r * 0.5 + sin(ang) * r * 0.4))
			cuerpo.append(c + Vector2(r * 0.3, r * 0.5))
			cuerpo.append(c + Vector2(-r * 0.3, r * 0.5))
			for i in 9:
				var ang := PI - (i) * (PI / 2) / 9
				cuerpo.append(c + Vector2(cos(ang) * r * 0.3, -r * 0.5 + sin(ang) * r * 0.4))
			draw_colored_polygon(cuerpo, w)
			draw_circle(c + Vector2(0, -r * 0.25), r * 0.16, ventana, true, -1.0, true)
			draw_circle(c + Vector2(0, -r * 0.25), r * 0.16, w.darkened(0.2), false, r * 0.04, true)
		"avatar_11":   # astronauta: casco con visor y reflejo
			var visor := color.darkened(0.45) if not bloqueado else Color("#A8ADBD")
			draw_circle(c + Vector2(0, -r * 0.08), r * 0.62, w, true, -1.0, true)
			draw_rect(Rect2(c + Vector2(-r * 0.5, r * 0.45), Vector2(r * 1.0, r * 0.3)), w.darkened(0.1))
			draw_circle(c + Vector2(0, -r * 0.08), r * 0.46, visor, true, -1.0, true)
			draw_arc(c + Vector2(0, -r * 0.08), r * 0.33, deg_to_rad(200), deg_to_rad(260), 10, Color(1, 1, 1, 0.8), r * 0.07, true)
			draw_circle(c + Vector2(r * 0.52, r * 0.12), r * 0.1, w.darkened(0.12), true, -1.0, true)
		"avatar_12":   # diamante con facetas
			var claro := Color("#A5F3FC") if not bloqueado else w
			var top := c + Vector2(0, -r * 0.45)
			var mid_y := -r * 0.1
			var pts := PackedVector2Array([top + Vector2(-r * 0.3, 0), top + Vector2(r * 0.3, 0), c + Vector2(r * 0.62, mid_y), c + Vector2(0, r * 0.68), c + Vector2(-r * 0.62, mid_y)])
			draw_colored_polygon(pts, w)
			draw_colored_polygon(PackedVector2Array([top + Vector2(-r * 0.3, 0), top + Vector2(r * 0.3, 0), c + Vector2(0, mid_y)]), claro)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.62, mid_y), c + Vector2(0, mid_y), c + Vector2(0, r * 0.68)]), claro.darkened(0.08))
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.62, mid_y), c + Vector2(r * 0.62, mid_y)]), color.darkened(0.2) if not bloqueado else Color("#A8ADBD"), r * 0.04, true)
		"avatar_13":   # corona con joyas
			var oro := Color("#FBBF24") if not bloqueado else w
			var joya := Color("#DC2626") if not bloqueado else Color("#A8ADBD")
			var base_y := r * 0.45
			var pts := PackedVector2Array([c + Vector2(-r * 0.65, base_y), c + Vector2(-r * 0.65, -r * 0.35), c + Vector2(-r * 0.3, -r * 0.05),
				c + Vector2(0, -r * 0.6), c + Vector2(r * 0.3, -r * 0.05), c + Vector2(r * 0.65, -r * 0.35), c + Vector2(r * 0.65, base_y)])
			draw_colored_polygon(pts, oro)
			draw_rect(Rect2(c + Vector2(-r * 0.65, base_y - r * 0.12), Vector2(r * 1.3, r * 0.12)), oro.darkened(0.15))
			draw_circle(c + Vector2(0, -r * 0.6), r * 0.09, joya, true, -1.0, true)
			draw_circle(c + Vector2(-r * 0.65, -r * 0.35), r * 0.07, joya, true, -1.0, true)
			draw_circle(c + Vector2(r * 0.65, -r * 0.35), r * 0.07, joya, true, -1.0, true)
			draw_circle(c + Vector2(0, r * 0.2), r * 0.09, Color("#2563EB") if not bloqueado else Color("#A8ADBD"), true, -1.0, true)
		"avatar_14":   # trofeo
			var oro := Color("#FBBF24") if not bloqueado else w
			var copa := PackedVector2Array([c + Vector2(-r * 0.42, -r * 0.6), c + Vector2(r * 0.42, -r * 0.6), c + Vector2(r * 0.3, r * 0.05), c + Vector2(-r * 0.3, r * 0.05)])
			draw_colored_polygon(copa, oro)
			draw_arc(c + Vector2(-r * 0.5, -r * 0.4), r * 0.18, deg_to_rad(90), deg_to_rad(270), 10, oro, r * 0.07, true)
			draw_arc(c + Vector2(r * 0.5, -r * 0.4), r * 0.18, deg_to_rad(-90), deg_to_rad(90), 10, oro, r * 0.07, true)
			draw_rect(Rect2(c + Vector2(-r * 0.06, r * 0.05), Vector2(r * 0.12, r * 0.25)), oro.darkened(0.15))
			draw_rect(Rect2(c + Vector2(-r * 0.32, r * 0.3), Vector2(r * 0.64, r * 0.14)), oro.darkened(0.2))
			draw_colored_polygon(_estrella(c + Vector2(0, -r * 0.3), r * 0.16, r * 0.07, 5), w)
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


static func _estrella(centro: Vector2, r_ext: float, r_int: float, puntas: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in puntas * 2:
		var ang := -PI / 2 + i * PI / puntas
		var rr := r_ext if i % 2 == 0 else r_int
		pts.append(centro + Vector2(cos(ang), sin(ang)) * rr)
	return pts
