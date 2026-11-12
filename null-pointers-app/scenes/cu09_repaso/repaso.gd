# res://scenes/cu09_repaso/repaso.gd
# CU-09: Repasar mis errores.
#
# Flujo (SRS 3.0):
#   1.   Entra desde Mi progreso (CU-06) o desde el menú principal.
#   2.   Se lee la lista de preguntas pendientes (falladas y no acertadas en repaso),
#        agrupadas por materia y módulo, con conteos                     → _mostrar_lista()
#   3.   "Iniciar repaso" (todas) o una materia en particular             → _iniciar()
#   4-6. Se muestra la pregunta con su materia/módulo de origen, el alumno
#        responde y el sistema evalúa                                     → _mostrar_pregunta() / _on_enviar()
#   7.   Si quedan preguntas, regresa al paso 4                           → _on_continuar()
#   8-9. Resumen (repasadas, aciertos, salieron) y se guarda el estado    → _terminar()
#   Alt. correcta → sale de la lista; incorrecta → permanece + "Ver teoría" (CU-04)
#   Alt. lista vacía → "No tienes errores por repasar"
#   Alt. lista vaciada → insignia "Repasador" (CU-05)
#   Alt. abandono → se conserva lo corregido hasta ese momento (no hay puntos en juego)
#
# Regla: el repaso NO otorga puntos ni cambia el mejor puntaje; máximo 10 preguntas por sesión.
extends Control

const RUTA_MENU     := "res://scenes/menu/Menu.tscn"
const RUTA_PROGRESO := "res://scenes/cu06_progreso/Progreso.tscn"
const RUTA_TEORIA   := "res://scenes/cu04_teoria/Teoria.tscn"
const RUTA_REPASO   := "res://scenes/cu09_repaso/Repaso.tscn"

const VERDE   := Color("#178A4C")
const NARANJA := Color("#C2410C")
const GRIS    := Color("#8A90A0")
const AZUL    := Color("#2F55E6")

var icono_script := preload("res://assets/ui/Icono.gd")

var cola: Array = []            # ids de reactivo de esta sesión (máx. 10)
var indice := 0
var aciertos := 0
var salieron := 0
var opcion_elegida := -1
var opciones: Array[PanelContainer] = []
var reactivo_actual: Dictionary = {}


func _ready() -> void:
	%BtnVolver.pressed.connect(_on_volver)
	%BtnVolverMenu.pressed.connect(func(): get_tree().change_scene_to_file(RUTA_MENU))
	%BtnIniciar.pressed.connect(func(): _iniciar(-1))
	%BtnEnviar.pressed.connect(_on_enviar)
	%BtnContinuar.pressed.connect(_on_continuar)
	%BtnVerTeoria.pressed.connect(_on_ver_teoria)
	%BtnOtroRepaso.pressed.connect(_mostrar_lista)
	%BtnIrProgreso.pressed.connect(func(): get_tree().change_scene_to_file(RUTA_PROGRESO))
	_crear_opciones()

	# Paso 5 del CU-04: si venimos de la teoría, continuar en la pregunta donde se detuvo
	var pausa: Dictionary = JuegoRepository.repaso_en_pausa
	JuegoRepository.repaso_en_pausa = {}
	if not pausa.is_empty():
		_restaurar_desde_pausa(pausa)
	else:
		_mostrar_lista()


# ============================ PASO 2: LISTA ============================
func _mostrar_lista() -> void:
	%PanelPregunta.hide()
	%PanelResultado.hide()
	%PanelLista.show()

	for hijo in %ListaMaterias.get_children():
		hijo.queue_free()

	var pendientes := JuegoRepository.obtener_errores_pendientes()
	var total := pendientes.size()
	%LblContador.text = str(total)
	%ChipContador.theme_type_variation = &"ChipGris" if total == 0 else &"Chip"

	# Flujo alternativo 3: lista vacía
	if total == 0:
		%LblTitulo.text = "¡Lista en cero!"
		%LblSub.text = "Cada pregunta que falles en un reto aparecerá aquí para que la repases sin presión."
		%AvisoVacio.show()
		%BtnIniciar.hide()
		%BtnVolverMenu.text = "Volver"
		return

	%AvisoVacio.hide()
	%BtnIniciar.show()
	%BtnVolverMenu.text = "Volver"
	%LblTitulo.text = "Tienes %d pregunta%s por repasar" % [total, "" if total == 1 else "s"]
	%LblSub.text = "Las preguntas que fallaste en los retos, agrupadas por materia. Cada una que aciertes aquí sale de la lista. El repaso no da puntos ni cambia tu mejor puntaje."
	%BtnIniciar.text = "Iniciar repaso (todas · máx. %d)" % JuegoRepository.REPASO_MAXIMO

	for grupo in JuegoRepository.obtener_resumen_errores():
		%ListaMaterias.add_child(_crear_tarjeta_materia(grupo))


## Tarjeta de una materia con sus módulos y un botón "Repasar esta materia".
func _crear_tarjeta_materia(g: Dictionary) -> Control:
	var tarjeta := PanelContainer.new()
	tarjeta.theme_type_variation = &"TileBlanco"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	tarjeta.add_child(col)

	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 10)
	col.add_child(fila)

	var punto := Control.new()
	punto.set_script(icono_script)
	punto.custom_minimum_size = Vector2(16, 16)
	punto.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	punto.tipo = "check"; punto.color = Color(0, 0, 0, 0); punto.grosor = 0.1
	punto.fondo = Color(g["color"])
	fila.add_child(punto)

	var nombre := Label.new()
	nombre.text = g["materia"]
	nombre.theme_type_variation = &"Negrita"
	nombre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nombre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fila.add_child(nombre)

	var chip := PanelContainer.new()
	chip.theme_type_variation = &"ChipGris"
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var n := Label.new()
	n.text = "%d" % int(g["total"])
	n.theme_type_variation = &"TextoNaranja"
	chip.add_child(n)
	fila.add_child(chip)

	var detalle := Label.new()
	var partes: Array = []
	for m in g["modulos"]:
		partes.append("%s (%d)" % [m["nombre"], int(m["errores"])])
	detalle.text = " · ".join(partes)
	detalle.theme_type_variation = &"Pequeno"
	detalle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(detalle)

	var btn := Button.new()
	btn.text = "Repasar esta materia"
	btn.theme_type_variation = &"BotonSecundario"
	btn.custom_minimum_size = Vector2(0, 64)
	btn.pressed.connect(_iniciar.bind(int(g["id_materia"])))
	col.add_child(btn)
	return tarjeta


# ============================ PASO 3: INICIAR ============================
func _iniciar(id_materia: int) -> void:
	var pendientes := JuegoRepository.obtener_errores_pendientes(id_materia)
	if pendientes.is_empty():
		return
	cola.clear()
	for e in pendientes:
		cola.append(int(e["id_reactivo"]))
		if cola.size() >= JuegoRepository.REPASO_MAXIMO:     # regla: máximo 10 por sesión
			break
	indice = 0
	aciertos = 0
	salieron = 0
	%Barra.max_value = cola.size()
	%PanelLista.hide()
	%PanelResultado.hide()
	%PanelPregunta.show()
	_mostrar_pregunta()


# ============================ PASO 4: PREGUNTA ============================
func _mostrar_pregunta() -> void:
	reactivo_actual = JuegoRepository.obtener_reactivo(cola[indice])
	var modulo := JuegoRepository.obtener_modulo(int(reactivo_actual["id_modulo"]))
	var materia := JuegoRepository.obtener_materia(int(modulo.get("id_materia", 1)))
	%LblProgreso.text = "Pregunta %d de %d" % [indice + 1, cola.size()]
	%LblOrigen.text = ("%s · %s" % [materia.get("corto", ""), modulo.get("nombre", "")]).to_upper()
	%Barra.value = indice + 1
	%LblPregunta.text = reactivo_actual["pregunta"]
	%LblContador.text = "%d" % JuegoRepository.obtener_errores_pendientes().size()

	for i in opciones.size():
		var op := opciones[i]
		op.visible = i < reactivo_actual["opciones"].size()
		if op.visible:
			op.get_node("Fila/Lbl").text = reactivo_actual["opciones"][i]
		_estilo_opcion(i, "normal")
		op.get_node("BtnOpcion").disabled = false

	opcion_elegida = -1
	%PanelRetro.hide()
	%BotonesRetro.hide()
	%BtnEnviar.show()
	%BtnEnviar.disabled = true


## Construye por código las 4 opciones con la misma estructura visual que CU-03.
func _crear_opciones() -> void:
	for i in 4:
		var op := PanelContainer.new()
		op.name = "Opcion%d" % (i + 1)
		op.theme_type_variation = &"Opcion"

		var fila := HBoxContainer.new()
		fila.name = "Fila"
		fila.add_theme_constant_override("separation", 14)
		fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
		op.add_child(fila)

		var radio := Control.new()
		radio.name = "Radio"
		radio.set_script(icono_script)
		radio.custom_minimum_size = Vector2(26, 26)
		radio.mouse_filter = Control.MOUSE_FILTER_IGNORE
		radio.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		radio.tipo = "radio"; radio.color = GRIS; radio.grosor = 2.2
		fila.add_child(radio)

		var lbl := Label.new()
		lbl.name = "Lbl"
		lbl.text = "Opción %d" % (i + 1)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.theme_type_variation = &"Negrita"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fila.add_child(lbl)

		var marca := Control.new()
		marca.name = "Marca"
		marca.set_script(icono_script)
		marca.custom_minimum_size = Vector2(26, 26)
		marca.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marca.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		marca.tipo = "check"; marca.color = VERDE; marca.grosor = 3.0
		marca.hide()
		fila.add_child(marca)

		var tag := Label.new()
		tag.name = "Tag"
		tag.text = "CORRECTA"
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag.theme_type_variation = &"EtiquetaVerde"
		tag.hide()
		fila.add_child(tag)

		var btn := Button.new()
		btn.name = "BtnOpcion"
		btn.theme_type_variation = &"BotonInvisible"
		btn.pressed.connect(_on_opcion_presionada.bind(i))
		op.add_child(btn)

		%Opciones.add_child(op)
		opciones.append(op)


## Estilo visual de una opción: normal | seleccionada | correcta | correcta_tag | incorrecta | apagada
func _estilo_opcion(i: int, estado: String) -> void:
	var op := opciones[i]
	var radio: Control = op.get_node("Fila/Radio")
	var marca: Control = op.get_node("Fila/Marca")
	var tag: Label = op.get_node("Fila/Tag")
	var lbl: Label = op.get_node("Fila/Lbl")
	marca.hide(); tag.hide()
	match estado:
		"seleccionada":
			op.theme_type_variation = &"OpcionSel"
			radio.tipo = "radio_sel"; radio.color = AZUL; radio.show()
			lbl.theme_type_variation = &"TextoAzul"
		"correcta":
			op.theme_type_variation = &"OpcionOk"
			radio.hide()
			marca.tipo = "check"; marca.color = VERDE; marca.show()
			lbl.theme_type_variation = &"TextoVerde"
		"correcta_tag":
			op.theme_type_variation = &"OpcionOk"
			radio.hide()
			tag.show()
			lbl.theme_type_variation = &"TextoVerde"
		"incorrecta":
			op.theme_type_variation = &"OpcionMal"
			radio.hide()
			marca.tipo = "cerrar"; marca.color = NARANJA; marca.show()
			lbl.theme_type_variation = &"TextoNaranja"
		"apagada":
			op.theme_type_variation = &"Opcion"
			radio.hide()
			lbl.theme_type_variation = &"TextoSecundario"
		_:
			op.theme_type_variation = &"Opcion"
			radio.tipo = "radio"; radio.color = GRIS; radio.show()
			lbl.theme_type_variation = &"Negrita"


func _on_opcion_presionada(i: int) -> void:
	if opcion_elegida == i:
		return
	for j in opciones.size():
		_estilo_opcion(j, "seleccionada" if j == i else "normal")
	opcion_elegida = i
	%BtnEnviar.disabled = false


# ============================ PASOS 5-6: EVALUAR ============================
func _on_enviar() -> void:
	if opcion_elegida < 0:
		return
	var correcta := int(reactivo_actual["respuesta_correcta"])
	var acierto := opcion_elegida == correcta

	for i in opciones.size():
		opciones[i].get_node("BtnOpcion").disabled = true
		if i == correcta:
			_estilo_opcion(i, "correcta" if acierto else "correcta_tag")
		elif i == opcion_elegida:
			_estilo_opcion(i, "incorrecta")
		else:
			_estilo_opcion(i, "apagada")

	JuegoRepository.registrar_repaso(int(reactivo_actual["id"]), acierto)   # persiste de inmediato (alt. abandono)
	if acierto:
		aciertos += 1
		salieron += 1
		%PanelRetro.theme_type_variation = &"TarjetaVerde"
		%IconoRetro.tipo = "check"; %IconoRetro.fondo = VERDE
		%LblRetroTitulo.text = "¡Corregida!"
		%LblRetroTitulo.theme_type_variation = &"TextoVerde"
		%LblRetroTexto.text = "La pregunta sale de tu lista de errores."
		%LblRetroTexto.theme_type_variation = &"TextoVerdeNormal"
		%BtnVerTeoria.hide()
	else:
		%PanelRetro.theme_type_variation = &"TarjetaNaranja"
		%IconoRetro.tipo = "cerrar"; %IconoRetro.fondo = NARANJA
		%LblRetroTitulo.text = "Sigue en la lista"
		%LblRetroTitulo.theme_type_variation = &"TextoNaranja"
		%LblRetroTexto.text = reactivo_actual["retroalimentacion"]
		%LblRetroTexto.theme_type_variation = &"TextoNaranjaNormal"
		%BtnVerTeoria.show()      # flujo alternativo 2 → CU-04

	var es_ultima := indice == cola.size() - 1
	%BtnContinuar.text = "Ver resumen" if es_ultima else "Continuar"
	%BtnEnviar.hide()
	%PanelRetro.show()
	%BotonesRetro.show()


# ============================ PASO 7: SIGUIENTE ============================
func _on_continuar() -> void:
	indice += 1
	if indice < cola.size():
		_mostrar_pregunta()
	else:
		_terminar()


func _on_ver_teoria() -> void:
	# CU-04 desde el repaso: se guarda el estado de la sesión y la teoría regresa aquí
	JuegoRepository.repaso_en_pausa = {
		"cola": cola.duplicate(),
		"indice": indice,
		"aciertos": aciertos,
		"salieron": salieron,
		"opcion_elegida": opcion_elegida,
	}
	JuegoRepository.teoria_regreso = RUTA_REPASO
	JuegoRepository.reactivo_teoria = int(reactivo_actual["id"])
	get_tree().change_scene_to_file(RUTA_TEORIA)


func _restaurar_desde_pausa(p: Dictionary) -> void:
	cola = p["cola"]
	indice = int(p["indice"])
	aciertos = int(p["aciertos"])
	salieron = int(p["salieron"])
	%Barra.max_value = cola.size()
	%PanelLista.hide()
	%PanelResultado.hide()
	%PanelPregunta.show()
	_mostrar_pregunta()
	opcion_elegida = int(p["opcion_elegida"])
	if opcion_elegida >= 0:
		# Vuelve a pintar la evaluación sin volver a contar el resultado
		var correcta := int(reactivo_actual["respuesta_correcta"])
		for i in opciones.size():
			opciones[i].get_node("BtnOpcion").disabled = true
			if i == correcta:
				_estilo_opcion(i, "correcta_tag")
			elif i == opcion_elegida:
				_estilo_opcion(i, "incorrecta")
			else:
				_estilo_opcion(i, "apagada")
		%PanelRetro.theme_type_variation = &"TarjetaNaranja"
		%IconoRetro.tipo = "cerrar"; %IconoRetro.fondo = NARANJA
		%LblRetroTitulo.text = "Sigue en la lista"
		%LblRetroTitulo.theme_type_variation = &"TextoNaranja"
		%LblRetroTexto.text = reactivo_actual["retroalimentacion"]
		%LblRetroTexto.theme_type_variation = &"TextoNaranjaNormal"
		%BtnVerTeoria.show()
		%BtnContinuar.text = "Ver resumen" if indice == cola.size() - 1 else "Continuar"
		%BtnEnviar.hide()
		%PanelRetro.show()
		%BotonesRetro.show()


# ============================ PASOS 8-9: RESUMEN ============================
func _terminar() -> void:
	var nuevas := JuegoRepository.terminar_repaso()
	var restantes := JuegoRepository.obtener_errores_pendientes().size()
	%LblResRepasadas.text = str(cola.size())
	%LblResAciertos.text = str(aciertos)
	%LblResSalieron.text = str(salieron)
	%LblContador.text = str(restantes)
	if restantes == 0:
		%LblResTitulo.text = "¡Lista en cero!"
		%PanelEstado.theme_type_variation = &"TarjetaVerde"
		%LblResDetalle.theme_type_variation = &"TextoVerde"
		%LblResDetalle.text = "Corregiste todos tus errores. Sin puntos en juego, pero con mucho aprendizaje."
		%BtnOtroRepaso.hide()
	else:
		%LblResTitulo.text = "Repaso terminado"
		%PanelEstado.theme_type_variation = &"TarjetaAzul"
		%LblResDetalle.theme_type_variation = &"TextoAzul"
		%LblResDetalle.text = "Te queda%s %d pregunta%s por repasar. Puedes volver a intentarlo cuando quieras." % [
			"" if restantes == 1 else "n", restantes, "" if restantes == 1 else "s"]
		%BtnOtroRepaso.show()
	if not nuevas.is_empty():
		var nombres: Array = []
		for i in nuevas:
			nombres.append(i["titulo"])
		%LblResDetalle.text += "\nNueva insignia: %s" % ", ".join(nombres)
	%PanelPregunta.hide()
	%PanelResultado.show()


## Flujo alternativo 5: abandono. Lo corregido ya quedó guardado; no se pide confirmación.
func _on_volver() -> void:
	if %PanelPregunta.visible:
		JuegoRepository.terminar_repaso()
		_mostrar_lista()
	else:
		get_tree().change_scene_to_file(RUTA_MENU)
