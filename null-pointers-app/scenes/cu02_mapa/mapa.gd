# res://scenes/cu02_mapa/mapa.gd
# CU-02: Seleccionar módulo de aprendizaje.
#
# Flujo normal del SRS:
#   1. Alumno toca "Jugar" en el menú             → llega aquí
#   2. Sistema carga el mapa con módulos          → _construir_mapa()
#   3. Alumno toca un nodo                        → _mostrar_detalle()
#   4. Sistema muestra descripción y puntos       → tarjeta PanelDetalle
#   Postcondición: pasa a la actividad (CU-03)    → _on_accion()
extends Control

const RUTA_MENU      := "res://scenes/menu/Menu.tscn"
const RUTA_ACTIVIDAD := "res://scenes/cu03_actividad/Actividad.tscn"

const COLOR_COMPLETADO   := Color(0.45, 1.0, 0.55)
const COLOR_DESBLOQUEADO := Color(1.0, 0.84, 0.3)
const COLOR_BLOQUEADO    := Color(0.5, 0.5, 0.55)

var modulos: Array = []
var modulo_sel: Dictionary = {}


func _ready() -> void:
	%BtnVolver.pressed.connect(func(): get_tree().change_scene_to_file(RUTA_MENU))
	%BtnCerrar.pressed.connect(%PanelDetalle.hide)
	%BtnAccion.pressed.connect(_on_accion)
	_construir_mapa()


# ============================== MAPA ==============================
func _construir_mapa() -> void:
	modulos = JuegoRepository.obtener_modulos()

	%LblPuntos.text = "%d pts" % JuegoRepository.obtener_puntos_totales()
	%LblResumen.text = "%d de %d módulos completados · Ingeniería de Software" % [
		JuegoRepository.modulos_completados(), modulos.size()]

	# Limpiar nodos anteriores (por si se reconstruye)
	for hijo in %ListaNodos.get_children():
		hijo.queue_free()

	# Un botón por módulo, en zig-zag para que parezca un camino
	for i in modulos.size():
		var m: Dictionary = modulos[i]

		var fila := MarginContainer.new()
		fila.add_theme_constant_override("margin_left", 0 if i % 2 == 0 else 200)
		fila.add_theme_constant_override("margin_right", 200 if i % 2 == 0 else 0)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 96)
		btn.text = "%d · %s" % [int(m["id"]), m["nombre"]]
		btn.add_theme_font_size_override("font_size", 24)
		btn.modulate = _color_estado(m["estado"])
		btn.pressed.connect(_mostrar_detalle.bind(m))

		fila.add_child(btn)
		%ListaNodos.add_child(fila)


func _color_estado(estado: String) -> Color:
	match estado:
		"completado":   return COLOR_COMPLETADO
		"desbloqueado": return COLOR_DESBLOQUEADO
		_:              return COLOR_BLOQUEADO


# ============================ TARJETA DE DETALLE ============================
func _mostrar_detalle(m: Dictionary) -> void:
	modulo_sel = m
	var id := int(m["id"])
	var estado: String = m["estado"]
	var mejor := int(m["mejor_puntaje"])

	%LblDetEncabezado.text = "MÓDULO %d · %s" % [id, estado.to_upper()]
	%LblDetEncabezado.modulate = _color_estado(estado)
	%LblDetNombre.text = m["nombre"]
	%LblDetTipo.text = m["tipo"].capitalize()
	%LblDetMaximos.text = str(int(m["puntos_maximos"]))
	%LblDetMejor.text = "—" if mejor < 0 else "%d · %d %%" % [int(m["puntos_obtenidos"]), mejor]

	match estado:
		"bloqueado":
			var previo := JuegoRepository.obtener_modulo(id - 1)
			%LblDetDescripcion.text = "Para desbloquearlo: completa Módulo %d · %s con un puntaje mínimo de %d %%." % [
				id - 1, previo.get("nombre", ""), JuegoRepository.PORCENTAJE_MINIMO]
			%BtnAccion.text = "Entendido"
		"completado":
			%LblDetDescripcion.text = "Ya superaste este módulo. Puedes volver a jugarlo; solo se guardará un nuevo intento si mejoras tu puntaje."
			%BtnAccion.text = "Volver a jugar"
		_:
			var desc: String = m["descripcion"]
			if mejor < 0:
				desc += " Aún no tienes intentos en este módulo."
			%LblDetDescripcion.text = desc
			%BtnAccion.text = "Iniciar"

	%PanelDetalle.show()


func _on_accion() -> void:
	if modulo_sel["estado"] == "bloqueado":
		%PanelDetalle.hide()
		return

	# Avisar al CU-03 qué módulo se eligió y cambiar de pantalla
	JuegoRepository.modulo_seleccionado = int(modulo_sel["id"])
	if ResourceLoader.exists(RUTA_ACTIVIDAD):
		get_tree().change_scene_to_file(RUTA_ACTIVIDAD)
	else:
		print("Pantalla pendiente (CU-03): ", RUTA_ACTIVIDAD)
