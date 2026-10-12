# res://scenes/cu03_actividad/actividad.gd
# CU-03: Resolver actividad de aprendizaje (quiz).
#
# Flujo (SRS 1.1 / diagrama de actividad CU-3):
#   mostrar pregunta → alumno elige y envía → evaluar → retro (correcta / incorrecta)
#   → ¿quedan preguntas? sí: siguiente / no: registrar intento y mostrar resultado
#   → >= 70 %: módulo completado + siguiente desbloqueado / < 70 %: reintentar
#
# El mapa (CU-02) pone JuegoRepository.modulo_seleccionado = id ANTES de abrir esta escena.
extends Control

const RUTA_MAPA   := "res://scenes/cu02_mapa/Mapa.tscn"
const RUTA_MENU   := "res://scenes/menu/Menu.tscn"
const RUTA_TEORIA := "res://scenes/cu04_teoria/Teoria.tscn"

const VERDE   := Color("#178A4C")
const NARANJA := Color("#C2410C")
const GRIS    := Color("#8A90A0")
const AZUL    := Color("#2F55E6")

var id_modulo: int
var modulo: Dictionary
var reactivos: Array
var indice := 0                 # pregunta actual (0..n-1)
var aciertos := 0
var puntos_reto := 0            # puntos acumulados en ESTE intento
var puntos_por_pregunta := 20
var opcion_elegida := -1
var opciones: Array[PanelContainer] = []


func _ready() -> void:
	for i in 4:
		opciones.append(%Opciones.get_node("Opcion%d" % (i + 1)))
		opciones[i].get_node("BtnOpcion%d" % (i + 1)).pressed.connect(_on_opcion_presionada.bind(i))

	# --- Cargar módulo y preguntas desde la BD local (RNF-01) ---
	id_modulo = JuegoRepository.modulo_seleccionado
	modulo = JuegoRepository.obtener_modulo(id_modulo)
	reactivos = JuegoRepository.obtener_reactivos(id_modulo)
	if modulo.is_empty() or reactivos.is_empty():
		push_error("El módulo %d no existe o no tiene preguntas" % id_modulo)
		_volver_al_mapa()
		return
	puntos_por_pregunta = int(modulo["puntos_maximos"]) / reactivos.size()

	# --- Botones ---
	%BtnEnviar.pressed.connect(_on_enviar)
	%BtnContinuar.pressed.connect(_on_continuar)
	%BtnVerTeoria.pressed.connect(_on_ver_teoria)
	%BtnSalir.pressed.connect(%PanelSalir.show)
	%BtnSeguirReto.pressed.connect(%PanelSalir.hide)
	%BtnSalirConfirmar.pressed.connect(_volver_al_mapa)
	%BtnReintentar.pressed.connect(_on_reintentar)
	%BtnVolverMapa.pressed.connect(_volver_al_mapa)

	%LblModulo.text = "Módulo %d · %s" % [id_modulo, _nombre_corto(modulo["nombre"])]
	%Barra.max_value = reactivos.size()
	_mostrar_pregunta()


func _nombre_corto(nombre: String) -> String:
	var cortos := {"Requerimientos de software": "Requerimientos", "Modelado con UML": "Modelado UML",
		"Ciclo de vida del software": "Ciclo de vida"}
	return cortos.get(nombre, nombre)


# =========================== PANTALLA DE PREGUNTA ===========================
func _mostrar_pregunta() -> void:
	var r: Dictionary = reactivos[indice]
	%LblPuntosReto.text = "%d pts" % puntos_reto
	%ChipPts.theme_type_variation = &"Chip"
	%LblProgreso.text = "Pregunta %d de %d" % [indice + 1, reactivos.size()]
	%LblEstado.text = "Reto cargado" if indice == 0 else "En curso"
	%Barra.value = indice + 1
	%LblPregunta.text = r["pregunta"]

	for i in opciones.size():
		var op := opciones[i]
		op.visible = i < r["opciones"].size()
		if op.visible:
			op.get_node("Fila/Lbl").text = r["opciones"][i]
		_estilo_opcion(i, "normal")
		op.get_node("BtnOpcion%d" % (i + 1)).disabled = false

	opcion_elegida = -1
	%PanelRetro.hide()
	%BotonesRetro.hide()
	%BtnEnviar.show()
	%BtnEnviar.disabled = true


## Estilo visual de una opción: normal | seleccionada | correcta | incorrecta | apagada
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
		"correcta_tag":   # la correcta cuando el alumno falló
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


func _on_enviar() -> void:
	if opcion_elegida < 0:
		return
	var r: Dictionary = reactivos[indice]
	var correcta := int(r["respuesta_correcta"])
	var acierto := opcion_elegida == correcta

	for i in opciones.size():
		opciones[i].get_node("BtnOpcion%d" % (i + 1)).disabled = true
		if i == correcta:
			_estilo_opcion(i, "correcta" if acierto else "correcta_tag")
		elif i == opcion_elegida:
			_estilo_opcion(i, "incorrecta")
		else:
			_estilo_opcion(i, "apagada")

	if acierto:
		aciertos += 1
		puntos_reto += puntos_por_pregunta
		%PanelRetro.theme_type_variation = &"TarjetaVerde"
		%IconoRetro.tipo = "check"; %IconoRetro.fondo = VERDE
		%LblRetroTitulo.text = "¡Correcto!"
		%LblRetroTitulo.theme_type_variation = &"TextoVerde"
		%LblRetroTexto.text = "+%d puntos sumados al reto" % puntos_por_pregunta
		%LblRetroTexto.theme_type_variation = &"TextoVerdeNormal"
		%ChipPts.theme_type_variation = &"ChipVerde"
		%BtnVerTeoria.hide()
	else:
		%PanelRetro.theme_type_variation = &"TarjetaNaranja"
		%IconoRetro.tipo = "cerrar"; %IconoRetro.fondo = NARANJA
		%LblRetroTitulo.text = "Respuesta incorrecta"
		%LblRetroTitulo.theme_type_variation = &"TextoNaranja"
		%LblRetroTexto.text = r["retroalimentacion"]
		%LblRetroTexto.theme_type_variation = &"TextoNaranjaNormal"
		%BtnVerTeoria.show()           # flujo alternativo → CU-04

	%LblPuntosReto.text = "%d pts" % puntos_reto
	%LblEstado.text = "Evaluada"
	var es_ultima := indice == reactivos.size() - 1
	if acierto:
		%BtnContinuar.text = "Ver resultado" if es_ultima else "Siguiente pregunta"
	else:
		%BtnContinuar.text = "Ver resultado" if es_ultima else "Continuar"
	%BtnEnviar.hide()
	%PanelRetro.show()
	%BotonesRetro.show()


func _on_continuar() -> void:
	indice += 1
	if indice < reactivos.size():
		_mostrar_pregunta()
	else:
		_terminar_reto()


func _on_ver_teoria() -> void:
	# CU-04 (Sprint 2): cuando exista, aquí se abrirá la teoría del concepto.
	if ResourceLoader.exists(RUTA_TEORIA):
		get_tree().change_scene_to_file(RUTA_TEORIA)
	else:
		print("Pantalla pendiente (CU-04): ", RUTA_TEORIA)


# ============================ PANTALLA DE RESULTADO ============================
func _terminar_reto() -> void:
	# Pasos 5-7 del SRS: mostrar resultado, guardar intento, actualizar perfil, desbloquear
	var res := JuegoRepository.registrar_intento(id_modulo, aciertos)
	var completado: bool = res["completado"]

	%LblResModulo.text = "Módulo %d · %s" % [id_modulo, modulo["nombre"]]
	%LblResPorcentaje.text = "%d %%" % res["porcentaje"]
	%Anillo.porcentaje = res["porcentaje"]
	%Anillo.color = VERDE if completado else NARANJA
	%LblResPuntos.text = str(res["puntos"])
	%LblResMaximos.text = str(res["puntos_maximos"])
	%LblResIntentos.text = str(res["intentos"])
	%LblResIntentos.get_parent().get_node("Etq").text = "Intento" if res["intentos"] == 1 else "Intentos"

	if completado:
		%LblResTitulo.text = "¡Reto completado!"
		%PanelEstado.theme_type_variation = &"TarjetaVerde"
		%IconoEstado1.tipo = "check"; %IconoEstado1.fondo = VERDE; %IconoEstado1.color = Color.WHITE
		%LblResEstado.text = "Módulo completado"
		%LblResDetalle.text = "Alcanzaste el mínimo de %d %%" % JuegoRepository.PORCENTAJE_MINIMO
		var sig: Dictionary = res["siguiente_desbloqueado"]
		%F2.visible = not sig.is_empty()
		if not sig.is_empty():
			%IconoEstado2.tipo = "candado"; %IconoEstado2.color = VERDE
			%LblResSiguiente.text = "Siguiente módulo desbloqueado"
			%LblResSiguienteDet.text = "Módulo %d · %s" % [int(sig["id"]), sig["nombre"]]
		_colorear_estado(true)
		%BtnReintentar.hide()
		%BtnVolverMapa.theme_type_variation = &""
	else:
		%LblResTitulo.text = "Reto terminado"
		%PanelEstado.theme_type_variation = &"TarjetaNaranja"
		%IconoEstado1.tipo = "alerta"; %IconoEstado1.fondo = NARANJA; %IconoEstado1.color = Color.WHITE
		%LblResEstado.text = "No alcanzaste el mínimo"
		%LblResDetalle.text = "Necesitas %d %% para completar el módulo" % JuegoRepository.PORCENTAJE_MINIMO
		%F2.show()
		%IconoEstado2.tipo = "guardar"; %IconoEstado2.color = NARANJA
		%LblResSiguiente.text = "Se conserva tu mejor puntaje"
		if res["mejor_previo"] >= 0:
			%LblResSiguienteDet.text = "Mejor intento previo: %d %%" % res["mejor_previo"]
		else:
			%LblResSiguienteDet.text = "Puedes reintentar las veces que quieras"
		_colorear_estado(false)
		%BtnReintentar.show()
		%BtnVolverMapa.theme_type_variation = &"BotonSecundario"

	%LblResTotal.text = "%d pts" % res["puntos_totales"]
	if res["puntos_sumados"] > 0:
		%ChipDelta.theme_type_variation = &"ChipVerde"
		%LblResDelta.text = "+%d" % res["puntos_sumados"]
		%LblResDelta.theme_type_variation = &"TextoVerde"
	else:
		%ChipDelta.theme_type_variation = &"ChipGris"
		%LblResDelta.text = "Sin cambios"
		%LblResDelta.theme_type_variation = &"Pequeno"

	%PanelPregunta.hide()
	%PanelResultado.show()


func _colorear_estado(verde: bool) -> void:
	%LblResEstado.theme_type_variation = &"TextoVerde" if verde else &"TextoNaranja"
	%LblResDetalle.theme_type_variation = &"TextoVerdeNormal" if verde else &"TextoNaranjaNormal"
	%LblResSiguiente.theme_type_variation = &"TextoVerde" if verde else &"TextoNaranja"
	%LblResSiguienteDet.theme_type_variation = &"TextoVerdeNormal" if verde else &"TextoNaranjaNormal"


func _on_reintentar() -> void:
	indice = 0
	aciertos = 0
	puntos_reto = 0
	%PanelResultado.hide()
	%PanelPregunta.show()
	_mostrar_pregunta()


func _volver_al_mapa() -> void:
	# Si se sale a media partida, el intento simplemente no se registra (flujo alt. abandono).
	if ResourceLoader.exists(RUTA_MAPA):
		get_tree().change_scene_to_file(RUTA_MAPA)
	else:
		get_tree().change_scene_to_file(RUTA_MENU)
