# res://scenes/cu06_progreso/progreso.gd
# CU-06: Ver progreso.
#
# Flujo (SRS 1.1 / diagrama de actividad CU-6):
#   1-2. "Mi progreso" en el menú → se lee el historial de intentos        → JuegoRepository.obtener_progreso()
#   3.   Puntuación total, módulos completados/total, conceptos dominados
#        (>= 70 %) y áreas de mejora (intentados con < 70 %)               → _mostrar()
#   4.   El alumno navega (scroll) y regresa al menú.
#   Alt. sin intentos → puntuación 0, listas vacías y
#        "Aún no has completado retos"                                     → _mostrar_vacio()
#
# Postcondición: solo consulta, no se altera ningún dato.
extends Control

const RUTA_MENU   := "res://scenes/menu/Menu.tscn"
const RUTA_MAPA   := "res://scenes/cu08_materias/Materias.tscn"   # CU-08: "Ir a jugar" abre el catálogo de materias
const RUTA_REPASO := "res://scenes/cu09_repaso/Repaso.tscn"       # CU-09

const VERDE   := Color("#178A4C")
const NARANJA := Color("#C2410C")


func _ready() -> void:
	%BtnVolver.pressed.connect(func(): get_tree().change_scene_to_file(RUTA_MENU))
	%BtnVolverMenu.pressed.connect(func(): get_tree().change_scene_to_file(RUTA_MENU))
	%BtnJugar.pressed.connect(func(): get_tree().change_scene_to_file(RUTA_MAPA))
	%BtnRepaso.pressed.connect(func(): get_tree().change_scene_to_file(RUTA_REPASO))
	%LblMinimo.text = "Dominado = mejor puntaje ≥ %d %%. Área de mejora = intentado con < %d %%." % [
		JuegoRepository.PORCENTAJE_MINIMO, JuegoRepository.PORCENTAJE_MINIMO]

	var perfil := JuegoRepository.obtener_perfil()
	%LblSaludo.text = "Así vas, %s" % perfil["alias"]

	var p := JuegoRepository.obtener_progreso()
	_mostrar(p)


# ============================ PASO 3: ESTADÍSTICAS ============================
func _mostrar(p: Dictionary) -> void:
	%LblTotal.text = str(p["puntuacion_total"])
	%LblCompletados.text = str(p["modulos_completados"])
	%LblTotalModulos.text = "/ %d" % p["modulos_totales"]
	%BarraModulos.max_value = p["modulos_totales"]
	%BarraModulos.value = p["modulos_completados"]

	# Con intentos la tarjeta de puntuación es azul; sin intentos (flujo alternativo) gris.
	var tiene: bool = p["tiene_intentos"]
	%TarjetaTotal.theme_type_variation = &"TarjetaAzulFuerte" if tiene else &"TarjetaGris"
	%EtqTotal.theme_type_variation = &"TextoBlanco" if tiene else &"Etiqueta"
	%LblTotal.theme_type_variation = &"NegritaBlanca" if tiene else &"Numero"
	%LblTotalSub.theme_type_variation = &"TextoBlanco" if tiene else &"Pequeno"
	%LblTotal.add_theme_font_size_override("font_size", 44)

	%AvisoVacio.visible = not tiene
	%BtnJugar.visible = not tiene

	# CU-09 paso 1: acceso al repaso desde Mi progreso (solo si hay errores pendientes)
	var errores: int = p.get("errores_pendientes", 0)
	%BtnRepaso.visible = errores > 0
	%BtnRepaso.text = "Repasar mis errores (%d)" % errores
	# CU-11: materias dominadas en el subtítulo de la puntuación
	var dominadas: int = p.get("materias_dominadas", 0)
	if dominadas > 0:
		%LblTotalSub.text = "%d materia%s dominada%s" % [dominadas, "" if dominadas == 1 else "s", "" if dominadas == 1 else "s"]

	_llenar_lista(%ListaDominados, p["dominados"], true)
	_llenar_lista(%ListaMejora, p["areas_mejora"], false)
	%LblNumDominados.text = str(p["dominados"].size())
	%LblNumMejora.text = str(p["areas_mejora"].size())


## Llena una sección con filas de módulo, o con el mensaje de lista vacía.
func _llenar_lista(contenedor: VBoxContainer, filas: Array, dominado: bool) -> void:
	for hijo in contenedor.get_children():
		hijo.queue_free()

	if filas.is_empty():
		var vacio := PanelContainer.new()
		vacio.theme_type_variation = &"TarjetaGris"
		var lbl := Label.new()
		lbl.text = "Sin módulos con ≥ %d %% todavía" % JuegoRepository.PORCENTAJE_MINIMO if dominado else "Sin módulos intentados"
		lbl.theme_type_variation = &"TextoTerciario"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vacio.add_child(lbl)
		contenedor.add_child(vacio)
		return

	for f in filas:
		contenedor.add_child(_crear_fila(f, dominado))


## Fila de un módulo: nombre, mejor puntaje e intentos, chip de % y barra.
func _crear_fila(f: Dictionary, dominado: bool) -> Control:
	var tarjeta := PanelContainer.new()
	tarjeta.theme_type_variation = &"TileBlanco"

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	tarjeta.add_child(col)

	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 10)
	col.add_child(fila)

	var textos := VBoxContainer.new()
	textos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	textos.add_theme_constant_override("separation", 2)
	fila.add_child(textos)

	var nombre := Label.new()
	nombre.text = "%s · %s" % [f.get("materia", "Módulo %d" % int(f["id"])), f["nombre"]]
	nombre.theme_type_variation = &"Negrita"
	nombre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	textos.add_child(nombre)

	var sub := Label.new()
	var n: int = f["intentos"]
	sub.text = "Mejor: %d pts · %d %s" % [int(f["mejor_puntos"]), n, "intento" if n == 1 else "intentos"]
	sub.theme_type_variation = &"Pequeno"
	textos.add_child(sub)

	var chip := PanelContainer.new()
	chip.theme_type_variation = &"ChipVerde" if dominado else &"ChipGris"
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pct := Label.new()
	pct.text = "%d %%" % int(f["mejor_porcentaje"])
	pct.theme_type_variation = &"TextoVerde" if dominado else &"TextoNaranja"
	chip.add_child(pct)
	fila.add_child(chip)

	var barra := ProgressBar.new()
	barra.custom_minimum_size = Vector2(0, 8)
	barra.max_value = 100
	barra.value = int(f["mejor_porcentaje"])
	barra.show_percentage = false
	if dominado:
		barra.theme_type_variation = &"BarraVerde"
	else:
		var estilo := StyleBoxFlat.new()
		estilo.bg_color = NARANJA
		estilo.set_corner_radius_all(999)
		barra.add_theme_stylebox_override("fill", estilo)
	col.add_child(barra)

	return tarjeta
