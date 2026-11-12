# res://scenes/cu04_teoria/teoria.gd
# CU-04: Ver teoría.
#
# Flujo (SRS 1.1 / diagrama de actividad CU-4):
#   1. El alumno tocó "Ver teoría" en una respuesta incorrecta (CU-03).
#   2. Se busca en almacenamiento local el concepto asociado al reactivo.
#   3. Se muestra título y explicación            → _mostrar_concepto()
#   Alt. sin concepto → "Contenido no disponible"  → _mostrar_no_disponible()
#   4-5. "Volver al reto" regresa a CU-03 en el punto donde se detuvo (paso 4).
#
# Postcondición: no se toca puntaje ni intento. CU-03 restaura su estado
# desde JuegoRepository.reto_en_pausa.
extends Control

const RUTA_ACTIVIDAD := "res://scenes/cu03_actividad/Actividad.tscn"
const RUTA_MAPA      := "res://scenes/cu02_mapa/Mapa.tscn"


func _ready() -> void:
	%BtnVolver.pressed.connect(_volver_al_reto)
	%BtnVolverReto.pressed.connect(_volver_al_reto)
	if JuegoRepository.teoria_regreso != "":
		%BtnVolverReto.text = "Volver al repaso"       # CU-09: se abrió desde Repasar mis errores

	var id_reactivo: int = JuegoRepository.reactivo_teoria
	var concepto := JuegoRepository.obtener_concepto(id_reactivo)
	if concepto.is_empty():
		_mostrar_no_disponible()
	else:
		_mostrar_concepto(concepto)
		JuegoRepository.registrar_consulta_teoria()   # cuenta para la insignia "Estudioso"


# ============================ PASO 3: CONCEPTO ============================
func _mostrar_concepto(c: Dictionary) -> void:
	var modulo := JuegoRepository.obtener_modulo(int(c["id_modulo"]))
	var nombre_modulo: String = modulo.get("nombre", "")
	%LblEtiqueta.text = ("CONCEPTO · MÓDULO %d · %s" % [int(c["id_modulo"]), nombre_modulo]).to_upper()
	%LblTitulo.text = c["titulo"]
	%LblExplicacion.text = c["explicacion"]
	%LblTruco.text = "Truco rápido: " + c["truco"]

	# Chips de ideas clave (se crean por código para que el número sea variable)
	for hijo in %Claves.get_children():
		hijo.queue_free()
	for clave in c["claves"]:
		var chip := PanelContainer.new()
		chip.theme_type_variation = &"ChipGris"
		var lbl := Label.new()
		lbl.text = clave
		lbl.theme_type_variation = &"Negrita"
		chip.add_child(lbl)
		%Claves.add_child(chip)

	%PanelConcepto.show()
	%PanelNoDisponible.hide()


# ===================== FLUJO ALTERNATIVO: SIN CONCEPTO =====================
func _mostrar_no_disponible() -> void:
	%PanelConcepto.hide()
	%PanelNoDisponible.show()


# ===================== PASOS 4-5: VOLVER A CU-03 =====================
func _volver_al_reto() -> void:
	JuegoRepository.reactivo_teoria = -1
	# CU-09: si la teoría se abrió desde el repaso de errores, se regresa ahí
	var regreso: String = JuegoRepository.teoria_regreso
	JuegoRepository.teoria_regreso = ""
	if regreso != "" and ResourceLoader.exists(regreso):
		get_tree().change_scene_to_file(regreso)
	elif not JuegoRepository.reto_en_pausa.is_empty() and ResourceLoader.exists(RUTA_ACTIVIDAD):
		get_tree().change_scene_to_file(RUTA_ACTIVIDAD)   # CU-03 continúa en el paso 4
	else:
		get_tree().change_scene_to_file(RUTA_MAPA)        # no había reto en pausa
