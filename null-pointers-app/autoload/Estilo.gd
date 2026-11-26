# res://autoload/Estilo.gd
# CU-07: modo claro/oscuro y paleta de color (acento) de toda la aplicación.
#
# La app se diseñó en claro con el tema assets/tema.tres y colores fijos en
# escenas e íconos dibujados por código. En vez de duplicar todo, este autoload:
#   1. Genera a partir del tema base un tema con los colores transformados
#      (fondos claros → oscuros, tinta → clara, azul de acento → color de la paleta)
#      y lo pone en la ventana raíz, que tiene prioridad sobre el tema del proyecto.
#   2. Escucha node_added y transforma los colores fijos de cada nodo nuevo
#      (íconos, anillos, ColorRect y overrides) guardando el color original en
#      metadatos para poder cambiar de modo las veces que sea sin acumular error.
#
# La pantalla de inicio (splash) se queda siempre oscura y no se toca.
extends Node

const AZUL_BASE := Color("#2F55E6")
const ESCENAS_FIJAS := ["res://scenes/splash/Splash.tscn"]
const COLORES_TEXTO := ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
	"font_disabled_color", "font_hover_pressed_color", "default_color", "font_placeholder_color",
	"caret_color", "font_selected_color", "font_outline_color", "icon_normal_color"]
const ESTILOS := ["panel", "normal", "hover", "pressed", "disabled", "focus", "fill", "background", "read_only"]

var modo := "claro"
var paleta := "azul"
var hue_paleta := 0.0            # hue (ok_hsl, 0-1) del acento actual
var hue_base := 0.0              # hue del azul original
var _temas: Dictionary = {}      # "modo|paleta" -> Theme generado
var _tema_base: Theme = preload("res://assets/tema.tres")


func _ready() -> void:
	hue_base = AZUL_BASE.ok_hsl_h
	get_tree().node_added.connect(_on_node_added)
	JuegoRepository.configuracion_cambiada.connect(aplicar)
	aplicar(JuegoRepository.obtener_configuracion())


func es_oscuro() -> bool:
	return modo == "oscuro"


## Aplica una configuración {modo, paleta} a toda la app (tema + escena actual).
func aplicar(config: Dictionary) -> void:
	modo = str(config.get("modo", "claro"))
	paleta = str(config.get("paleta", "azul"))
	var info := JuegoRepository.info_paleta(paleta)
	hue_paleta = Color(str(info.get("color", "#2F55E6"))).ok_hsl_h
	get_tree().root.theme = _tema_actual()
	var escena := get_tree().current_scene
	if escena != null:
		_remapear_arbol(escena)


## Color de acento actual (para dibujar cosas nuevas con el color de la paleta).
func acento() -> Color:
	return transformar(AZUL_BASE, "texto")


# ============================ TRANSFORMACIÓN DE COLORES ============================
## rol = "fondo" (superficies) o "texto" (tinta, trazos de íconos, texto).
func transformar(c: Color, rol: String = "texto") -> Color:
	if c.a <= 0.001:
		return c
	var h := c.ok_hsl_h
	var s := c.ok_hsl_s
	var l := c.ok_hsl_l
	var a := c.a
	var croma := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))   # 0 = gris puro
	# Acento: todo lo que sea "azul SoftPlay" toma el hue de la paleta
	var es_acento := croma >= 0.25 and absf(_dist_hue(h, hue_base)) < 0.055
	if es_acento:
		h = hue_paleta
	if modo != "oscuro":
		return Color.from_ok_hsl(h, s, l, a)
	# ---- modo oscuro ----
	if croma < 0.1:
		# Grises y tinta: se invierte la luminosidad con un ligero tinte azul marino
		if rol == "texto":
			if l >= 0.85:
				return c                               # blanco sobre color: se queda blanco
			var nl := clampf(0.12 + (1.0 - l) * 0.84, 0.0, 0.95)
			return Color.from_ok_hsl(0.70, 0.08, nl, a)
		# fondos
		if a < 0.5:
			return Color(0, 0, 0, a * 1.6)             # sombras y velos: más oscuros
		if croma > 0.04 and l >= 0.9:
			return Color.from_ok_hsl(h, 0.35, 0.22, a)      # tintes pastel → tinte oscuro
		if l >= 0.985:
			return Color.from_ok_hsl(0.70, 0.18, 0.21, a)   # blanco (tarjetas) → superficie
		if l >= 0.94:
			return Color.from_ok_hsl(0.70, 0.22, 0.13, a)   # fondo de página / entradas
		if l >= 0.80:
			return Color.from_ok_hsl(0.70, 0.16, 0.28, a)   # grises claros (chips, barras vacías)
		var nl2 := clampf(0.12 + (1.0 - l) * 0.84, 0.0, 0.95)
		return Color.from_ok_hsl(0.70, 0.12, nl2, a)
	# Colores saturados
	if rol == "fondo" and croma < 0.22 and l >= 0.7:
		return Color.from_ok_hsl(h, 0.18, 0.30, a)        # grises azulados claros (botones deshabilitados)
	if l >= 0.82:
		return Color.from_ok_hsl(h, minf(s, 0.5), 0.24, a)   # pastel → versión oscura del mismo hue
	if rol == "texto":
		return Color.from_ok_hsl(h, s, clampf(l + 0.16, 0.0, 0.86), a)   # texto de color más legible
	return Color.from_ok_hsl(h, s, clampf(l + 0.05, 0.0, 0.8), a)


func _dist_hue(h1: float, h2: float) -> float:
	var d := fmod(absf(h1 - h2), 1.0)
	return minf(d, 1.0 - d)


# ============================ TEMA ============================
func _tema_actual() -> Theme:
	var clave := modo + "|" + paleta
	if not _temas.has(clave):
		_temas[clave] = _generar_tema()
	return _temas[clave]


func _generar_tema() -> Theme:
	var t: Theme = _tema_base.duplicate(true)
	var vistos := {}
	for tipo in t.get_type_list():
		for nombre in t.get_color_list(tipo):
			t.set_color(nombre, tipo, transformar(t.get_color(nombre, tipo), "texto"))
		for nombre in t.get_stylebox_list(tipo):
			var sb := t.get_stylebox(nombre, tipo)
			if sb is StyleBoxFlat and not vistos.has(sb.get_instance_id()):
				vistos[sb.get_instance_id()] = true
				_transformar_stylebox(sb)
	return t


func _transformar_stylebox(sb: StyleBoxFlat) -> void:
	sb.bg_color = transformar(sb.bg_color, "fondo")
	sb.border_color = transformar(sb.border_color, "fondo")
	if modo == "oscuro":
		sb.shadow_color = Color(0, 0, 0, sb.shadow_color.a * 1.5)


# ============================ NODOS ============================
func _on_node_added(n: Node) -> void:
	_remapear_nodo(n)


func _remapear_arbol(raiz: Node) -> void:
	_remapear_nodo(raiz)
	for h in raiz.get_children():
		_remapear_arbol(h)


func _escena_fija(n: Node) -> bool:
	var actual := n
	while actual != null:
		if actual.scene_file_path != "":
			return actual.scene_file_path in ESCENAS_FIJAS
		actual = actual.get_parent()
	return false


## Guarda el valor original en metadatos la primera vez y siempre transforma a partir de él.
func _original(n: Node, prop: String) -> Variant:
	var clave := "estilo_orig_" + prop
	if not n.has_meta(clave):
		n.set_meta(clave, n.get(prop))
	return n.get_meta(clave)


func _remapear_nodo(n: Node) -> void:
	if not (n is Control) or n.has_meta("estilo_fijo") or _escena_fija(n):
		return
	var script: Variant = n.get_script()
	if script != null and script is Script:
		match script.get_global_name():
			&"Icono":
				n.color = transformar(_original(n, "color"), "texto")
				n.fondo = transformar(_original(n, "fondo"), "texto")
			&"Anillo":
				n.color = transformar(_original(n, "color"), "texto")
				n.color_fondo = transformar(_original(n, "color_fondo"), "fondo")
			&"LogoSoftPlay":
				n.oscuro = modo == "oscuro"
	if n is ColorRect:
		n.color = transformar(_original(n, "color"), "fondo")
	# Overrides de color (font_color, etc.)
	for nombre in COLORES_TEXTO:
		if n.has_theme_color_override(nombre):
			var clave: String = "estilo_orig_color_" + nombre
			if not n.has_meta(clave):
				n.set_meta(clave, n.get_theme_color(nombre))
			n.add_theme_color_override(nombre, transformar(n.get_meta(clave), "texto"))
	# Overrides de StyleBox (paneles pintados por código)
	for nombre in ESTILOS:
		if n.has_theme_stylebox_override(nombre):
			var clave: String = "estilo_orig_sb_" + nombre
			if not n.has_meta(clave):
				n.set_meta(clave, n.get_theme_stylebox(nombre))
			var orig: StyleBox = n.get_meta(clave)
			if orig is StyleBoxFlat:
				var copia: StyleBoxFlat = orig.duplicate()
				_transformar_stylebox(copia)
				n.add_theme_stylebox_override(nombre, copia)
