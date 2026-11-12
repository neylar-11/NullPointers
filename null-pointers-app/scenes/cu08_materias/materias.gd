# res://scenes/cu08_materias/materias.gd
# CU-08: Elegir materia. Catálogo de materias del área de ingeniería de software.
#
# Flujo (SRS 3.0):
#   1-2. "Jugar" → se carga el catálogo con nombre, módulos completados/total y % → _construir_catalogo()
#   3-4. Toca una materia → se recuerda y se abre su mapa 2D (CU-02)             → _on_materia_presionada()
#   5-6. Desde el mapa se puede regresar aquí o al menú.
#   Alt. materia sin avance → 0 % y etiqueta "Sin iniciar" (sigue seleccionable)
#   Alt. última materia visitada → resaltada como "Continuar en…"
#   Alt. cancelar → "Volver" regresa al menú sin cambios
#
# Postcondición: ningún dato del progreso se modifica (solo se guarda la última materia).
extends Control

const RUTA_MENU := "res://scenes/menu/Menu.tscn"
const RUTA_MAPA := "res://scenes/cu02_mapa/Mapa.tscn"

var icono_script := preload("res://assets/ui/Icono.gd")


func _ready() -> void:
	%BtnVolver.pressed.connect(func(): get_tree().change_scene_to_file(RUTA_MENU))
	%LblPuntos.text = "%d pts" % JuegoRepository.obtener_puntos_totales()
	_construir_catalogo()


# ============================ PASO 2: CATÁLOGO ============================
func _construir_catalogo() -> void:
	for hijo in %Lista.get_children():
		hijo.queue_free()
	var catalogo := JuegoRepository.obtener_catalogo_materias()
	var dominadas := 0
	for fila in catalogo:
		if fila["dominada"]:
			dominadas += 1
		%Lista.add_child(_crear_tarjeta(fila))
	if dominadas > 0:
		%LblSub.text = "Has dominado %d de %d materias. Cada materia tiene su propio mapa de módulos." % [dominadas, catalogo.size()]


## Tarjeta de una materia: icono de color, nombre, avance, barra y etiqueta de estado.
func _crear_tarjeta(f: Dictionary) -> Control:
	var color := Color(f["color"])
	var es_ultima: bool = f["es_ultima"]
	var sin_iniciar: bool = f["sin_iniciar"]

	var tarjeta := PanelContainer.new()
	tarjeta.theme_type_variation = &"TarjetaAzul" if es_ultima else &"TarjetaBoton"

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tarjeta.add_child(col)

	# --- Etiqueta superior: "Continuar en…" / "Sin iniciar" / "Dominada" ---
	var etiqueta := Label.new()
	etiqueta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if f["dominada"]:
		etiqueta.text = "MATERIA DOMINADA"
		etiqueta.theme_type_variation = &"EtiquetaVerde"
	elif es_ultima and not sin_iniciar:
		etiqueta.text = "CONTINUAR EN…"
		etiqueta.theme_type_variation = &"EtiquetaAzul"
	elif sin_iniciar:
		etiqueta.text = "SIN INICIAR"
		etiqueta.theme_type_variation = &"Etiqueta"
	else:
		etiqueta.text = "EN CURSO"
		etiqueta.theme_type_variation = &"EtiquetaAzul"
	col.add_child(etiqueta)

	# --- Fila principal: caja con icono + textos ---
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 16)
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(fila)

	var caja := PanelContainer.new()
	caja.custom_minimum_size = Vector2(64, 64)
	caja.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.theme_type_variation = &"CajaIconoBlanca"
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = color
	estilo.set_corner_radius_all(18)
	caja.add_theme_stylebox_override("panel", estilo)
	var ic := Control.new()
	ic.set_script(icono_script)
	ic.custom_minimum_size = Vector2(64, 64)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.tipo = f["icono"]
	ic.color = Color.WHITE
	ic.grosor = 2.5
	caja.add_child(ic)
	fila.add_child(caja)

	var textos := VBoxContainer.new()
	textos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	textos.add_theme_constant_override("separation", 4)
	textos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(textos)

	var nombre := Label.new()
	nombre.text = f["nombre"]
	nombre.theme_type_variation = &"TituloTarjeta"
	nombre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nombre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	textos.add_child(nombre)

	var desc := Label.new()
	desc.text = f["descripcion"]
	desc.theme_type_variation = &"Pequeno"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	textos.add_child(desc)

	# --- Avance: "n de m módulos" + chip con % + barra ---
	var avance := HBoxContainer.new()
	avance.add_theme_constant_override("separation", 10)
	avance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(avance)

	var lbl_avance := Label.new()
	lbl_avance.text = "%d de %d módulos completados" % [int(f["modulos_completados"]), int(f["modulos_totales"])]
	lbl_avance.theme_type_variation = &"TextoSecundario"
	lbl_avance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_avance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avance.add_child(lbl_avance)

	var chip := PanelContainer.new()
	chip.theme_type_variation = &"ChipGris" if sin_iniciar else (&"ChipVerde" if f["dominada"] else &"Chip")
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pct := Label.new()
	pct.text = "%d %%" % int(f["porcentaje"])
	pct.theme_type_variation = &"TextoVerde" if f["dominada"] else (&"Pequeno" if sin_iniciar else &"TextoAzul")
	pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(pct)
	avance.add_child(chip)

	var barra := ProgressBar.new()
	barra.custom_minimum_size = Vector2(0, 8)
	barra.max_value = 100
	barra.value = int(f["porcentaje"])
	barra.show_percentage = false
	barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var relleno := StyleBoxFlat.new()
	relleno.bg_color = color
	relleno.set_corner_radius_all(999)
	barra.add_theme_stylebox_override("fill", relleno)
	col.add_child(barra)

	# --- Botón invisible que cubre toda la tarjeta (paso 3) ---
	var btn := Button.new()
	btn.theme_type_variation = &"BotonInvisible"
	btn.pressed.connect(_on_materia_presionada.bind(int(f["id"])))
	tarjeta.add_child(btn)
	return tarjeta


# ============================ PASOS 3-4: ABRIR EL MAPA ============================
func _on_materia_presionada(id_materia: int) -> void:
	JuegoRepository.seleccionar_materia(id_materia)
	get_tree().change_scene_to_file(RUTA_MAPA)
