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
## Dos secciones: medallas por tema (bronce / plata / oro según el promedio del tema)
## y logros generales (suben de nivel al alcanzar cada umbral).
func _construir_catalogo() -> void:
	insignias = JuegoRepository.obtener_insignias()
	var obtenidas := JuegoRepository.insignias_obtenidas()
	var oros := JuegoRepository.medallas_en_nivel(3)
	%LblContador.text = "%d / %d" % [obtenidas, insignias.size()]
	%Barra.max_value = insignias.size()
	%Barra.value = obtenidas

	# Flujo alternativo: ninguna obtenida
	var vacio := obtenidas == 0
	%AvisoVacio.visible = vacio
	%BtnJugar.visible = vacio
	%ChipContador.theme_type_variation = &"ChipGris" if vacio else &"Chip"

	for hijo in %Secciones.get_children():
		hijo.queue_free()
	_agregar_seccion("MEDALLAS POR TEMA · %d de oro" % oros if oros > 0 else "MEDALLAS POR TEMA",
		"Bronce con promedio ≥ 70 %, plata ≥ 85 %, oro con 100 % en los tres módulos del tema.",
		JuegoRepository.obtener_insignias_tipo("tema"))
	_agregar_seccion("LOGROS", "Cada logro sube de bronce a plata y a oro conforme avanzas.",
		JuegoRepository.obtener_insignias_tipo("logro"))


func _agregar_seccion(titulo: String, ayuda: String, lista: Array) -> void:
	var etq := Label.new()
	etq.text = titulo
	etq.theme_type_variation = &"EtiquetaAzul"
	%Secciones.add_child(etq)
	var sub := Label.new()
	sub.text = ayuda
	sub.theme_type_variation = &"Pequeno"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%Secciones.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for ins in lista:
		grid.add_child(_crear_tile(ins))
	%Secciones.add_child(grid)
	var esp := Control.new()
	esp.custom_minimum_size = Vector2(0, 8)
	%Secciones.add_child(esp)


## Tile de una insignia: medalla (color del nivel) con icono + nombre + nivel. Se construye por código.
func _crear_tile(ins: Dictionary) -> Control:
	var nivel: int = int(ins.get("nivel", 0))
	var obtenida := nivel > 0
	var color_medalla := JuegoRepository.color_nivel(nivel)
	var color_tema := Color(ins["color"])

	var tarjeta := PanelContainer.new()
	tarjeta.theme_type_variation = &"TileBlanco" if obtenida else &"Tile"
	tarjeta.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tarjeta.add_child(col)

	var centro := CenterContainer.new()
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(centro)

	# Medalla: anillo del metal + círculo interior con el icono
	var medalla := Control.new()
	medalla.custom_minimum_size = Vector2(84, 84)
	medalla.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medalla.set_script(icono_script)
	medalla.tipo = ins["icono"]
	medalla.grosor = 3.0
	if obtenida:
		medalla.fondo = color_medalla
		medalla.color = Color.WHITE
	else:
		medalla.fondo = COLOR_GRIS_FONDO
		medalla.color = COLOR_GRIS_ICONO
	centro.add_child(medalla)

	if obtenida:
		# Anillo exterior del metal (más claro) para distinguir bronce / plata / oro
		var anillo := Control.new()
		anillo.set_script(icono_script)
		anillo.tipo = "check"
		anillo.color = Color(0, 0, 0, 0)
		anillo.grosor = 0.1
		anillo.fondo = color_medalla.lightened(0.35)
		anillo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		anillo.position = Vector2(-6, -6)
		anillo.size = Vector2(96, 96)
		anillo.show_behind_parent = true
		medalla.add_child(anillo)
		# Estrellas del nivel (1, 2 o 3) en la esquina
		var estrellas := Label.new()
		estrellas.text = "★".repeat(nivel)
		estrellas.add_theme_color_override("font_color", color_medalla.darkened(0.2))
		estrellas.add_theme_font_size_override("font_size", 16)
		estrellas.position = Vector2(50, 58)
		estrellas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		medalla.add_child(estrellas)
	else:
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
		medalla.add_child(candado)

	var lbl := Label.new()
	lbl.text = ins["titulo"].replace("Medalla · ", "")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.theme_type_variation = &"Negrita" if obtenida else &"TextoSecundario"
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(lbl)

	var estado := Label.new()
	estado.text = JuegoRepository.nombre_nivel(nivel).to_upper()
	estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	estado.theme_type_variation = &"EtiquetaVerde" if obtenida else &"Etiqueta"
	if obtenida:
		estado.add_theme_color_override("font_color", color_medalla.darkened(0.15))
	estado.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(estado)

	# Barra de avance al siguiente nivel
	if nivel < 3:
		var barra := ProgressBar.new()
		barra.custom_minimum_size = Vector2(0, 6)
		barra.show_percentage = false
		var meta := int(ins["niveles"][nivel])
		barra.max_value = meta
		barra.value = mini(int(ins.get("progreso", 0)), meta)
		barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var relleno := StyleBoxFlat.new()
		relleno.bg_color = color_tema if obtenida else Color("#B8BDCF")
		relleno.set_corner_radius_all(999)
		barra.add_theme_stylebox_override("fill", relleno)
		col.add_child(barra)

	# Botón invisible encima de todo el tile (paso 3: tocar una insignia)
	var btn := Button.new()
	btn.theme_type_variation = &"BotonInvisible"
	btn.pressed.connect(_mostrar_detalle.bind(ins))
	tarjeta.add_child(btn)
	return tarjeta


# ============================ PASO 4: DETALLE ============================
func _mostrar_detalle(ins: Dictionary) -> void:
	var nivel: int = int(ins.get("nivel", 0))
	var obtenida := nivel > 0
	var color_medalla := JuegoRepository.color_nivel(nivel)

	%IconoDetalle.tipo = ins["icono"]
	if obtenida:
		%IconoDetalle.fondo = color_medalla
		%IconoDetalle.color = Color.WHITE
	else:
		%IconoDetalle.fondo = COLOR_GRIS_FONDO
		%IconoDetalle.color = COLOR_GRIS_ICONO

	if obtenida:
		%LblDetEstado.text = "%s · %s" % [JuegoRepository.nombre_nivel(nivel).to_upper(), _fecha_corta(str(ins.get("fecha", "")))]
		%LblDetEstado.theme_type_variation = &"EtiquetaVerde"
		%LblDetEstado.add_theme_color_override("font_color", color_medalla.darkened(0.15))
	else:
		%LblDetEstado.text = "BLOQUEADA"
		%LblDetEstado.theme_type_variation = &"Etiqueta"
		%LblDetEstado.remove_theme_color_override("font_color")

	%LblDetTitulo.text = ins["titulo"]
	%LblDetDescripcion.text = ins["descripcion"]

	# Niveles: cada umbral con su estado y el avance actual
	var progreso := int(ins.get("progreso", 0))
	var condiciones: Array = ins.get("condiciones", [ins.get("condicion", "")])
	var niveles: Array = ins.get("niveles", [])
	%Etq.text = "NIVELES · %d %s" % [progreso, ins.get("unidad", "")] if ins.has("unidad") else "NIVELES"
	var lineas: Array = []
	for k in condiciones.size():
		var c := JuegoRepository.color_nivel(k + 1)
		var alcanzado := nivel >= k + 1
		var marca := "✔" if alcanzado else "○"
		var meta := str(niveles[k]) if k < niveles.size() else ""
		lineas.append("[color=%s]%s %s[/color]  %s%s" % [c.to_html(false), marca, JuegoRepository.nombre_nivel(k + 1), condiciones[k],
			("  [color=#8A90A6](%d/%s)[/color]" % [mini(progreso, int(meta)), meta]) if (not alcanzado and meta != "") else ""])
	%LblDetCondicion.text = "\n".join(lineas)
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


## Botón Atrás de Android (Navegacion): cierra la tarjeta o vuelve al menú.
func atras() -> void:
	if %PanelDetalle.visible:
		%PanelDetalle.hide()
	else:
		get_tree().change_scene_to_file(RUTA_MENU)
