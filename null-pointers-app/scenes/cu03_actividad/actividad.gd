# res://scenes/cu03_actividad/actividad.gd
# CU-03: Resolver actividad de aprendizaje (quiz).
#
# Flujo (diagrama de actividad CU-3):
#   mostrar pregunta → alumno elige y envía → evaluar → retro (correcta / incorrecta)
#   → ¿quedan preguntas? sí: siguiente / no: registrar intento y mostrar resultado
#   → >= 70 %: módulo completado + siguiente desbloqueado / < 70 %: reintentar
#
# El mapa (CU-02) debe poner JuegoRepository.modulo_seleccionado = id ANTES de
# cambiar a esta escena.
extends Control

const RUTA_MAPA   := "res://scenes/cu02_mapa/Mapa.tscn"
const RUTA_MENU   := "res://scenes/menu/Menu.tscn"
const RUTA_TEORIA := "res://scenes/cu04_teoria/Teoria.tscn"

const COLOR_CORRECTA   := Color(0.45, 1.0, 0.55)
const COLOR_INCORRECTA := Color(1.0, 0.45, 0.45)

var id_modulo: int
var modulo: Dictionary
var reactivos: Array
var indice := 0                 # pregunta actual (0..n-1)
var aciertos := 0
var puntos_reto := 0            # puntos acumulados en ESTE intento
var puntos_por_pregunta := 20
var opcion_elegida := -1
var botones: Array[Button] = []


func _ready() -> void:
	botones = [%BtnOpcion1, %BtnOpcion2, %BtnOpcion3, %BtnOpcion4]

	# --- Cargar módulo y preguntas desde la BD local (RNF-01) ---
	id_modulo = JuegoRepository.modulo_seleccionado
	modulo = JuegoRepository.obtener_modulo(id_modulo)
	reactivos = JuegoRepository.obtener_reactivos(id_modulo)
	if modulo.is_empty() or reactivos.is_empty():
		push_error("El módulo %d no existe o no tiene preguntas" % id_modulo)
		_volver_al_mapa()
		return
	puntos_por_pregunta = int(modulo["puntos_maximos"]) / reactivos.size()

	# --- Conectar botones ---
	for i in botones.size():
		botones[i].pressed.connect(_on_opcion_presionada.bind(i))
	%BtnEnviar.pressed.connect(_on_enviar)
	%BtnContinuar.pressed.connect(_on_continuar)
	%BtnVerTeoria.pressed.connect(_on_ver_teoria)
	%BtnSalir.pressed.connect(func(): %DialogoSalir.popup_centered())
	%DialogoSalir.confirmed.connect(_volver_al_mapa)
	%BtnReintentar.pressed.connect(_on_reintentar)
	%BtnVolverMapa.pressed.connect(_volver_al_mapa)

	_mostrar_pregunta()


# =========================== PANTALLA DE PREGUNTA ===========================
func _mostrar_pregunta() -> void:
	var r: Dictionary = reactivos[indice]
	%LblModulo.text = "Módulo %d · %s" % [id_modulo, modulo["nombre"]]
	%LblPuntosReto.text = "%d pts" % puntos_reto
	%LblProgreso.text = "Pregunta %d de %d · En curso" % [indice + 1, reactivos.size()]
	%LblPregunta.text = r["pregunta"]

	for i in botones.size():
		var b := botones[i]
		b.visible = i < r["opciones"].size()
		if b.visible:
			b.text = r["opciones"][i]
		b.button_pressed = false
		b.disabled = false
		b.modulate = Color.WHITE

	opcion_elegida = -1
	%PanelRetro.hide()
	%BtnEnviar.show()
	%BtnEnviar.disabled = true


func _on_opcion_presionada(i: int) -> void:
	opcion_elegida = i
	%BtnEnviar.disabled = false


func _on_enviar() -> void:
	if opcion_elegida < 0:
		return
	var r: Dictionary = reactivos[indice]
	var correcta := int(r["respuesta_correcta"])

	for b in botones:
		b.disabled = true
	botones[correcta].modulate = COLOR_CORRECTA

	if opcion_elegida == correcta:
		aciertos += 1
		puntos_reto += puntos_por_pregunta
		%LblRetroTitulo.text = "¡Correcto!"
		%LblRetroTexto.text = "+%d puntos sumados al reto" % puntos_por_pregunta
		%BtnVerTeoria.hide()
	else:
		botones[opcion_elegida].modulate = COLOR_INCORRECTA
		%LblRetroTitulo.text = "Respuesta incorrecta"
		%LblRetroTexto.text = r["retroalimentacion"]
		%BtnVerTeoria.show()           # flujo alternativo → CU-04

	%LblPuntosReto.text = "%d pts" % puntos_reto
	%LblProgreso.text = "Pregunta %d de %d · Evaluada" % [indice + 1, reactivos.size()]
	var es_ultima := indice == reactivos.size() - 1
	%BtnContinuar.text = "Ver resultado" if es_ultima else "Siguiente pregunta"
	%BtnEnviar.hide()
	%PanelRetro.show()


func _on_continuar() -> void:
	indice += 1
	if indice < reactivos.size():
		_mostrar_pregunta()
	else:
		_terminar_reto()


func _on_ver_teoria() -> void:
	# CU-04 todavía no existe; cuando esté, aquí se abrirá la teoría del módulo.
	if ResourceLoader.exists(RUTA_TEORIA):
		get_tree().change_scene_to_file(RUTA_TEORIA)
	else:
		print("Pantalla pendiente (CU-04): ", RUTA_TEORIA)


# ============================ PANTALLA DE RESULTADO ============================
func _terminar_reto() -> void:
	# Pasos 7-10 del diagrama: guardar intento, actualizar perfil, desbloquear
	var res := JuegoRepository.registrar_intento(id_modulo, aciertos)

	%LblResModulo.text = "Módulo %d · %s" % [id_modulo, modulo["nombre"]]
	%LblResPorcentaje.text = "%d %%" % res["porcentaje"]
	%LblResPuntos.text = str(res["puntos"])
	%LblResMaximos.text = str(res["puntos_maximos"])
	%LblResIntentos.text = str(res["intentos"])

	if res["completado"]:
		%LblResTitulo.text = "¡Reto completado!"
		%LblResEstado.text = "Módulo completado"
		%LblResDetalle.text = "Alcanzaste el mínimo de %d %%" % JuegoRepository.PORCENTAJE_MINIMO
		var sig: Dictionary = res["siguiente_desbloqueado"]
		if sig.is_empty():
			%LblResSiguiente.hide()
		else:
			%LblResSiguiente.show()
			%LblResSiguiente.text = "Siguiente módulo desbloqueado: Módulo %d · %s" % [
				int(sig["id"]), sig["nombre"]]
		%BtnReintentar.hide()
	else:
		%LblResTitulo.text = "Reto terminado"
		%LblResEstado.text = "No alcanzaste el mínimo"
		%LblResDetalle.text = "Necesitas %d %% para completar el módulo" % JuegoRepository.PORCENTAJE_MINIMO
		%LblResSiguiente.show()
		if res["mejor_previo"] >= 0:
			%LblResSiguiente.text = "Se conserva tu mejor puntaje · Mejor intento previo: %d %%" % res["mejor_previo"]
		else:
			%LblResSiguiente.text = "Puedes reintentar las veces que quieras"
		%BtnReintentar.show()

	if res["puntos_sumados"] > 0:
		%LblResTotal.text = "Puntuación total del perfil: %d pts (+%d)" % [
			res["puntos_totales"], res["puntos_sumados"]]
	else:
		%LblResTotal.text = "Puntuación total del perfil: %d pts · Sin cambios" % res["puntos_totales"]

	%PanelPregunta.hide()
	%PanelResultado.show()


func _on_reintentar() -> void:
	indice = 0
	aciertos = 0
	puntos_reto = 0
	%PanelResultado.hide()
	%PanelPregunta.show()
	_mostrar_pregunta()


func _volver_al_mapa() -> void:
	# Si se sale a media partida, el intento simplemente no se registra.
	if ResourceLoader.exists(RUTA_MAPA):
		get_tree().change_scene_to_file(RUTA_MAPA)
	else:
		get_tree().change_scene_to_file(RUTA_MENU)
