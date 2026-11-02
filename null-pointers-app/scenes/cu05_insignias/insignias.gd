# res://scenes/cu05_insignias/insignias.gd
# CU-05: Ver insignias.
#
# Flujo (SRS 1.1 / diagrama de actividad CU-5):
#   1-2. "Insignias" en el menú → se carga el catálogo con el estado de cada una → _construir_catalogo()
#   3-4. Toca una insignia → tarjeta con título, descripción y condición       → _mostrar_detalle()
#   5.   Cierra la tarjeta                                                    → %PanelDetalle.hide
#   Alt. ninguna obtenida → catálogo completo + "Aún no tienes insignias"      → %AvisoVacio
#
# Postcondición: solo consulta, no se modifica ningún dato.
extends Control

const RUTA_MENU := "res://scenes/menu/Menu.tscn"
const RUTA_MAPA := "res://scenes/cu02_mapa/Mapa.tscn"

const COLOR_GRIS_FONDO := Color("#E6E8F0")
const COLOR_GRIS_ICONO := Color("#B8BDCF")
const COLOR_FONDO_GRIS := Color("#E3E6EE")

var icono_script := preload("res://assets/ui/Icono.gd")
var insignias: Array = []


func _ready() -> void:
	%BtnVolver.pressed.connect(func(): get_tree().change_scene_to_file(RUTA_MENU))
	%BtnCerrar.pressed.connect(%PanelDetalle.hide)
	%BtnCerrarFondo.pressed.connect(%PanelDetalle.hide)
	%BtnJugar.pressed.connect(func(): get_tree().change_scene_to_file(RUTA_MAPA))
	_construir_catalogo()


# ============================ PASO 2: CATÁLOGO ============================
func _construir_catalogo() -> void:
	insignias = JuegoRepository.obtener_insignias()
	var obtenidas := JuegoRepository.insignias_obtenidas()
	%LblContador.text = "%d / %d" % [obtenidas, insignias.size()]
	%Barra.max_value = insignias.size()
	%Barra.value = obtenidas

	# Flujo alternativo: ninguna obtenida
	var vacio := obtenidas == 0
	%AvisoVacio.visible = vacio
	%BtnJugar.visible = vacio
	%ChipContador.theme_type_variation = &"ChipGris" if vacio else &"Chip"

	for hijo in %Cuadricula.get_children():
		hijo.queue_free()
	for ins in insignias:
		%Cuadricula.add_child(_crear_tile(ins))


## Tile de una insignia: círculo con icono + nombre + estado. Se construye por código.
func _crear_tile(ins: Dictionary) -> Control:
	var obtenida: bool = ins["obtenida"]
	var color := Color(ins["color"])

	var tarjeta := PanelContainer.new()
	tarjeta.theme_type_variation = &"TileBlanco" if obtenida else &"Tile"
	tarjeta.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tarjeta.add_child(col)

	var centro := CenterContainer.new()
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(centro)

	var circulo := Control.new()
	circulo.custom_minimum_size = Vector2(84, 84)
	circulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circulo.set_script(icono_script)
	circulo.tipo = ins["icono"]
	circulo.grosor = 3.0
	if obtenida:
		circulo.fondo = color
		circulo.color = Color.WHITE
	else:
		circulo.fondo = COLOR_GRIS_FONDO
		circulo.color = COLOR_GRIS_ICONO
	centro.add_child(circulo)

	if not obtenida:
		# Candado pequeño en la esquina del círculo
		var candado := Control.new()
		candado.set_script(icono_script)
		candado.tipo = "candado"
		candado.color = Color("#5B6178")
		candado.fondo = Color.WHITE
		candado.grosor = 2.0
		candado.mouse_filter = Control.MOUSE_FILTER_IGNORE
		candado.position = Vector2(56, 56)
		candado.size = Vector2(30, 30)
		circulo.add_child(candado)

	var lbl := Label.new()
	lbl.text = ins["titulo"]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.theme_type_variation = &"Negrita" if obtenida else &"TextoSecundario"
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(lbl)

	var estado := Label.new()
	estado.text = "OBTENIDA" if obtenida else "BLOQUEADA"
	estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	estado.theme_type_variation = &"EtiquetaVerde" if obtenida else &"Etiqueta"
	if obtenida:
		estado.add_theme_color_override("font_color", color)
	estado.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(estado)

	# Botón invisible encima de todo el tile (paso 3: tocar una insignia)
	var btn := Button.new()
	btn.theme_type_variation = &"BotonInvisible"
	btn.pressed.connect(_mostrar_detalle.bind(ins))
	tarjeta.add_child(btn)
	return tarjeta


# ============================ PASO 4: DETALLE ============================
func _mostrar_detalle(ins: Dictionary) -> void:
	var obtenida: bool = ins["obtenida"]
	var color := Color(ins["color"])

	%IconoDetalle.tipo = ins["icono"]
	if obtenida:
		%IconoDetalle.fondo = color
		%IconoDetalle.color = Color.WHITE
	else:
		%IconoDetalle.fondo = COLOR_GRIS_FONDO
		%IconoDetalle.color = COLOR_GRIS_ICONO

	if obtenida:
		%LblDetEstado.text = "OBTENIDA · %s" % _fecha_corta(ins["fecha_obtencion"])
		%LblDetEstado.theme_type_variation = &"EtiquetaVerde"
		%LblDetEstado.add_theme_color_override("font_color", color)
	else:
		%LblDetEstado.text = "BLOQUEADA"
		%LblDetEstado.theme_type_variation = &"Etiqueta"
		%LblDetEstado.remove_theme_color_override("font_color")

	%LblDetTitulo.text = ins["titulo"]
	%LblDetDescripcion.text = ins["descripcion"]
	%LblDetCondicion.text = ins["condicion"]
	%PanelDetalle.show()


## "2026-10-12T18:20:00" → "12 OCT 2026"
func _fecha_corta(iso: String) -> String:
	if iso.length() < 10:
		return ""
	var meses := ["ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"]
	var anio := iso.substr(0, 4)
	var mes := int(iso.substr(5, 2))
	var dia := int(iso.substr(8, 2))
	if mes < 1 or mes > 12:
		return iso.substr(0, 10)
	return "%d %s %s" % [dia, meses[mes - 1], anio]
