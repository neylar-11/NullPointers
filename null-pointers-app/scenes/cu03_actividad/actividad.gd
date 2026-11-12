# res://scenes/cu03_actividad/actividad.gd
# CU-03: Resolver actividad de aprendizaje (quiz).
#
# Flujo (SRS 1.1 / diagrama de actividad CU-3):
#   mostrar pregunta → alumno elige y envía → evaluar → retro (correcta / incorrecta)
#   → ¿quedan preguntas? sí: siguiente / no: registrar intento y mostrar resultado
#   → >= 70 %: módulo completado + siguiente desbloqueado / < 70 %: reintentar
#
# El mapa (CU-02) pone JuegoRepository.modulo_seleccionado = id ANTES de abrir esta escena.
#
# Sprint 3:
#   CU-09: cada respuesta incorrecta se registra en la lista de errores (JuegoRepository.registrar_error).
#   CU-10: botón "Pista" antes de enviar: "Recordar el concepto" (25 %) y "Descartar una opción" (50 %).
#          Los descuentos se aplican a los puntos de la pregunta y el intento registra las pistas usadas.
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

# --- CU-10: estado de las pistas ---
var pistas_permitidas := true          # false en módulos tipo puzzle (flujo alternativo 5)
var pistas_intento := 0                # total de pistas usadas en este intento (postcondición)
var puntos_pregunta := 20              # puntos que aún puede ganar la pregunta actual (con descuentos)
var pista_recordar_usada := false      # "Recordar el concepto" ya se usó en esta pregunta
var opcion_descartada := -1            # índice descartado por "Descartar una opción" (-1 = ninguna)
var restaurando := false               # true mientras se reconstruye la pantalla al volver de la teoría


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
	pistas_permitidas = modulo["tipo"] != "puzzle"      # CU-10 alt. 5: sin pistas en puzzles

	# --- Botones ---
	%BtnEnviar.pressed.connect(_on_enviar)
	%BtnContinuar.pressed.connect(_on_continuar)
	%BtnVerTeoria.pressed.connect(_on_ver_teoria)
	%BtnSalir.pressed.connect(%PanelSalir.show)
	%BtnSeguirReto.pressed.connect(%PanelSalir.hide)
	%BtnSalirConfirmar.pressed.connect(_volver_al_mapa)
	%BtnReintentar.pressed.connect(_on_reintentar)
	%BtnVolverMapa.pressed.connect(_volver_al_mapa)
	# CU-10
	%BtnPista.pressed.connect(_on_pista)
	%BtnCerrarPista.pressed.connect(%PanelPista.hide)
	%BtnCerrarPistaFondo.pressed.connect(%PanelPista.hide)
	%BtnPistaRecordar.pressed.connect(_on_pista_recordar)
	%BtnPistaDescartar.pressed.connect(_on_pista_descartar)
	%BtnPista.visible = pistas_permitidas

	var materia := JuegoRepository.obtener_materia(int(modulo.get("id_materia", 1)))
	%LblModulo.text = "%s · %s" % [materia.get("corto", "Módulo %d" % id_modulo), _nombre_corto(modulo["nombre"])]
	%Barra.max_value = reactivos.size()

	# CU-04 paso 5: si venimos de la teoría, continuar en el punto donde se detuvo (paso 4)
	var pausa: Dictionary = JuegoRepository.reto_en_pausa
	JuegoRepository.reto_en_pausa = {}        # se consume siempre (una pausa de otro módulo se descarta)
	if not pausa.is_empty() and int(pausa["id_modulo"]) == id_modulo:
		_restaurar_desde_pausa(pausa)
	else:
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
	%BotonesPregunta.show()
	%BtnEnviar.disabled = true

	# CU-10: cada pregunta inicia con todos sus puntos y sin pistas
	puntos_pregunta = puntos_por_pregunta
	pista_recordar_usada = false
	opcion_descartada = -1
	%PanelPistaTexto.hide()
	%BtnPista.disabled = false
	%BtnPista.text = "Pista"


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
		"descartada":     # CU-10: opción eliminada por la pista "Descartar una opción"
			op.theme_type_variation = &"Opcion"
			radio.hide()
			marca.tipo = "cerrar"; marca.color = GRIS; marca.show()
			tag.text = "DESCARTADA"; tag.theme_type_variation = &"Etiqueta"; tag.show()
			lbl.theme_type_variation = &"TextoTerciario"
		_:
			op.theme_type_variation = &"Opcion"
			radio.tipo = "radio"; radio.color = GRIS; radio.show()
			lbl.theme_type_variation = &"Negrita"
			tag.text = "CORRECTA"; tag.theme_type_variation = &"EtiquetaVerde"


func _on_opcion_presionada(i: int) -> void:
	if opcion_elegida == i or i == opcion_descartada:
		return
	for j in opciones.size():
		if j == opcion_descartada:
			continue
		_estilo_opcion(j, "seleccionada" if j == i else "normal")
	opcion_elegida = i
	%BtnEnviar.disabled = false


# =============================== CU-10: PISTAS ===============================
## Paso 1-2: "Pista" muestra las dos opciones con su costo en puntos.
func _on_pista() -> void:
	var r: Dictionary = reactivos[indice]
	var id_reactivo := int(r["id"])
	var costo_recordar := int(round(puntos_por_pregunta * JuegoRepository.costo_pista("recordar")))
	var costo_descartar := int(round(puntos_por_pregunta * JuegoRepository.costo_pista("descartar")))
	%LblPistaValor.text = "Esta pregunta vale %d pts" % puntos_pregunta

	# Alt. 2: sin concepto asociado → "Recordar el concepto" no está disponible
	var hay_concepto := JuegoRepository.texto_pista_concepto(id_reactivo) != ""
	# Alt. 3: pregunta de dos opciones → "Descartar una opción" no está disponible
	var hay_descartable: bool = r["opciones"].size() > 2
	# Alt. 1: segunda pista → solo se ofrece la que falta
	var recordar_disp := hay_concepto and not pista_recordar_usada
	var descartar_disp: bool = hay_descartable and opcion_descartada < 0

	%TarjetaRecordar.visible = recordar_disp
	%TarjetaDescartar.visible = descartar_disp
	%LblRecordarSub.text = "Una frase del concepto asociado · cuesta 25 %% (−%d pts)" % costo_recordar
	%LblDescartarSub.text = "Elimina una respuesta incorrecta · cuesta 50 %% (−%d pts)" % costo_descartar
	if not recordar_disp and not descartar_disp:
		%LblPistaNota.text = "Ya no hay pistas disponibles para esta pregunta."
	elif not hay_concepto:
		%LblPistaNota.text = "Esta pregunta no tiene concepto asociado; solo puedes descartar una opción."
	elif not hay_descartable:
		%LblPistaNota.text = "Pregunta de dos opciones: no se puede descartar ninguna."
	else:
		%LblPistaNota.text = "Los descuentos se acumulan. Completar un módulo sin pistas da la insignia \"Sin ayuda\"."
	%PanelPista.show()


## Paso 3-4: aplica la pista, resta el costo y lo indica en pantalla.
func _aplicar_costo(tipo: String) -> void:
	var costo := int(round(puntos_por_pregunta * JuegoRepository.costo_pista(tipo)))
	puntos_pregunta = maxi(puntos_pregunta - costo, 0)
	pistas_intento += 1
	%LblEstado.text = "Esta pregunta ahora vale %d pts" % puntos_pregunta
	%BtnPista.text = "Pista (%d)" % _pistas_en_pregunta()
	if _pistas_en_pregunta() >= 2:
		%BtnPista.disabled = true        # Alt. 1: con las dos usadas, el botón se deshabilita
	%PanelPista.hide()


func _pistas_en_pregunta() -> int:
	return int(pista_recordar_usada) + int(opcion_descartada >= 0)


func _on_pista_recordar() -> void:
	var texto := JuegoRepository.texto_pista_concepto(int(reactivos[indice]["id"]))
	if texto == "" or pista_recordar_usada:
		return
	pista_recordar_usada = true
	%LblPistaTexto.text = texto
	%PanelPistaTexto.show()
	_aplicar_costo("recordar")


func _on_pista_descartar() -> void:
	if opcion_descartada >= 0:
		return
	var idx := JuegoRepository.opcion_a_descartar(int(reactivos[indice]["id"]))
	if idx < 0:
		return
	opcion_descartada = idx
	_estilo_opcion(idx, "descartada")
	opciones[idx].get_node("BtnOpcion%d" % (idx + 1)).disabled = true
	if opcion_elegida == idx:            # si justo tenía seleccionada la descartada, se deselecciona
		opcion_elegida = -1
		%BtnEnviar.disabled = true
	_aplicar_costo("descartar")


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
		elif i == opcion_descartada:
			_estilo_opcion(i, "descartada")
		else:
			_estilo_opcion(i, "apagada")

	if acierto:
		aciertos += 1
		puntos_reto += puntos_pregunta             # CU-10 paso 6: se suman los puntos ya reducidos
		%PanelRetro.theme_type_variation = &"TarjetaVerde"
		%IconoRetro.tipo = "check"; %IconoRetro.fondo = VERDE
		%LblRetroTitulo.text = "¡Correcto!"
		%LblRetroTitulo.theme_type_variation = &"TextoVerde"
		if puntos_pregunta < puntos_por_pregunta:
			%LblRetroTexto.text = "+%d puntos sumados al reto (%d de %d por las pistas)" % [puntos_pregunta, puntos_pregunta, puntos_por_pregunta]
		else:
			%LblRetroTexto.text = "+%d puntos sumados al reto" % puntos_pregunta
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
		if not restaurando:
			JuegoRepository.registrar_error(int(r["id"]))     # CU-09: entra a la lista de errores

	%LblPuntosReto.text = "%d pts" % puntos_reto
	%LblEstado.text = "Evaluada"
	var es_ultima := indice == reactivos.size() - 1
	if acierto:
		%BtnContinuar.text = "Ver resultado" if es_ultima else "Siguiente pregunta"
	else:
		%BtnContinuar.text = "Ver resultado" if es_ultima else "Continuar"
	%BotonesPregunta.hide()
	%PanelPista.hide()
	%PanelRetro.show()
	%BotonesRetro.show()


func _on_continuar() -> void:
	indice += 1
	if indice < reactivos.size():
		_mostrar_pregunta()
	else:
		_terminar_reto()


func _on_ver_teoria() -> void:
	# CU-04 paso 1: guardar el estado del reto y abrir la teoría del concepto asociado.
	# Al regresar, _ready() restaura este estado (paso 5 del CU-04 → paso 4 del CU-03).
	JuegoRepository.reto_en_pausa = {
		"id_modulo": id_modulo,
		"indice": indice,
		"aciertos": aciertos,
		"puntos_reto": puntos_reto,
		"opcion_elegida": opcion_elegida,
		# CU-10: el estado de las pistas también se conserva
		"pistas_intento": pistas_intento,
		"puntos_pregunta": puntos_pregunta,
		"pista_recordar_usada": pista_recordar_usada,
		"opcion_descartada": opcion_descartada,
	}
	JuegoRepository.reactivo_teoria = int(reactivos[indice]["id"])
	get_tree().change_scene_to_file(RUTA_TEORIA)


## Reconstruye la pantalla de "respuesta incorrecta" tal como estaba antes de ir a la teoría.
func _restaurar_desde_pausa(p: Dictionary) -> void:
	restaurando = true
	indice = int(p["indice"])
	aciertos = int(p["aciertos"])
	puntos_reto = int(p["puntos_reto"])
	_mostrar_pregunta()
	pistas_intento = int(p.get("pistas_intento", 0))
	puntos_pregunta = int(p.get("puntos_pregunta", puntos_por_pregunta))
	pista_recordar_usada = bool(p.get("pista_recordar_usada", false))
	opcion_descartada = int(p.get("opcion_descartada", -1))
	if pista_recordar_usada:
		%LblPistaTexto.text = JuegoRepository.texto_pista_concepto(int(reactivos[indice]["id"]))
		%PanelPistaTexto.show()
	opcion_elegida = int(p["opcion_elegida"])
	if opcion_elegida >= 0:
		_on_enviar()        # vuelve a pintar la evaluación (misma respuesta, mismo resultado)
		# _on_enviar sumó el acierto otra vez solo si fue correcta; desde la teoría nunca lo es,
		# pero se protege por si acaso:
		var r: Dictionary = reactivos[indice]
		if opcion_elegida == int(r["respuesta_correcta"]):
			aciertos -= 1
			puntos_reto -= puntos_pregunta
			%LblPuntosReto.text = "%d pts" % puntos_reto
	restaurando = false


# ============================ PANTALLA DE RESULTADO ============================
func _terminar_reto() -> void:
	# Pasos 5-7 del SRS: mostrar resultado, guardar intento, actualizar perfil, desbloquear
	# CU-10: los puntos del intento ya traen los descuentos; se registran las pistas usadas
	var res := JuegoRepository.registrar_intento(id_modulo, aciertos, puntos_reto, pistas_intento)
	var completado: bool = res["completado"]

	%LblResModulo.text = "%s · %s" % [%LblModulo.text.get_slice(" · ", 0), modulo["nombre"]]
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
		%F2.visible = not sig.is_empty() or bool(res.get("practica_desbloqueada", false))
		if not sig.is_empty():
			%IconoEstado2.tipo = "candado"; %IconoEstado2.color = VERDE
			%LblResSiguiente.text = "Siguiente módulo desbloqueado"
			%LblResSiguienteDet.text = sig["nombre"]
		elif res.get("practica_desbloqueada", false):
			# CU-11 paso 1: se desbloqueó el nodo final "Práctica de ingeniero" de la materia
			%IconoEstado2.tipo = "puzzle"; %IconoEstado2.color = VERDE
			%LblResSiguiente.text = "¡Práctica de ingeniero desbloqueada!"
			%LblResSiguienteDet.text = "Completaste todos los módulos de la materia. Búscala al final del mapa."
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

	# CU-10: el resumen indica cuántas pistas se usaron
	if pistas_intento > 0:
		%LblResDetalle.text += "\nPistas usadas: %d" % pistas_intento

	# CU-05: avisar si este intento desbloqueó insignias
	var nuevas: Array = res.get("insignias_nuevas", [])
	if not nuevas.is_empty():
		var nombres: Array = []
		for i in nuevas:
			nombres.append(i["titulo"])
		%LblResDetalle.text += "\nNueva insignia: %s" % ", ".join(nombres)

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
	pistas_intento = 0
	%PanelResultado.hide()
	%PanelPregunta.show()
	_mostrar_pregunta()


func _volver_al_mapa() -> void:
	# Si se sale a media partida, el intento simplemente no se registra (flujo alt. abandono).
	if ResourceLoader.exists(RUTA_MAPA):
		get_tree().change_scene_to_file(RUTA_MAPA)
	else:
		get_tree().change_scene_to_file(RUTA_MENU)
