# res://scenes/cu11_practica/practica.gd
# CU-11: Resolver práctica de ingeniero.
#
# Flujo (SRS 3.0):
#   1-2. El mapa (CU-02) desbloqueó el nodo final y el alumno tocó "Iniciar".
#        JuegoRepository.practica_materia trae la materia.
#   3.   Se carga la práctica: escenario + secuencia de 3 a 5 ejercicios      → _ready()
#   4.   Se muestra el escenario y el ejercicio actual, de uno de estos tipos  → _mostrar_ejercicio()
#          clasificar  : tocar la etiqueta de cada tarjeta para asignarle categoría
#          construir   : colocar actores y casos de uso en el diagrama (misma mecánica)
#          ordenar     : tocar las piezas en orden para construir la secuencia
#          seleccionar : elegir qué tareas caben sin exceder las horas
#   5.   "Comprobar"                                                          → _on_comprobar()
#   6.   Evaluación pieza por pieza + retroalimentación + puntos proporcionales
#   7.   Siguiente ejercicio                                                  → _on_continuar()
#   8-9. Resumen; se guarda el intento; ≥ 70 % → materia "Dominada" + insignia → _terminar()
#   Alt. ejercicio incorrecto → solución recomendada con justificación + "Ver teoría"
#   Alt. < 70 % → no se alcanzó el mínimo; se conserva el mejor puntaje
#   Alt. abandono → confirmación; si acepta, se descarta el intento
#   Alt. rejugar práctica dominada → el intento solo se guarda si supera al mejor
#
# Regla: las piezas se presentan en orden aleatorio en cada intento.
extends Control

const RUTA_MAPA := "res://scenes/cu02_mapa/Mapa.tscn"

const VERDE   := Color("#178A4C")
const NARANJA := Color("#C2410C")
const AZUL    := Color("#2F55E6")
const GRIS    := Color("#8A90A0")

var icono_script := preload("res://assets/ui/Icono.gd")

var id_materia: int = 1
var materia: Dictionary = {}
var practica: Dictionary = {}
var ejercicios: Array = []
var indice := 0
var piezas_correctas_total := 0
var piezas_totales := 0
var puntos_practica := 0           # puntos acumulados en este intento (proporcionales a las piezas)
var resumen_ejercicios: Array = [] # [{instruccion, correctas, total}] para la pantalla final

# Estado del ejercicio actual
var piezas: Array = []             # piezas barajadas del ejercicio actual
var asignacion: Array = []         # clasificar/construir: categoría elegida por pieza ("" = sin asignar)
var secuencia: Array = []          # ordenar: índices de piezas en el orden tocado
var seleccion: Array = []          # seleccionar: bool por pieza
var tarjetas: Array[Control] = []  # controles de cada pieza (para colorear al comprobar)
var evaluado := false


func _ready() -> void:
	id_materia = JuegoRepository.practica_materia
	materia = JuegoRepository.obtener_materia(id_materia)
	practica = JuegoRepository.obtener_practica(id_materia)
	if practica.is_empty() or materia.is_empty():
		push_error("La materia %d no tiene práctica" % id_materia)
		_volver_al_mapa()
		return
	ejercicios = practica["ejercicios"]
	for ej in ejercicios:
		piezas_totales += ej["piezas"].size()

	%BtnSalir.pressed.connect(%PanelSalir.show)
	%BtnSeguir.pressed.connect(%PanelSalir.hide)
	%BtnSalirConfirmar.pressed.connect(_volver_al_mapa)     # alt. abandono: se descarta el intento
	%BtnComprobar.pressed.connect(_on_comprobar)
	%BtnDeshacer.pressed.connect(_on_deshacer)
	%BtnContinuar.pressed.connect(_on_continuar)
	%BtnVerTeoria.pressed.connect(_on_ver_teoria)
	%BtnCerrarTeoria.pressed.connect(%PanelTeoria.hide)
	%BtnCerrarTeoriaFondo.pressed.connect(%PanelTeoria.hide)
	%BtnReintentar.pressed.connect(_on_reintentar)
	%BtnVolverMapa.pressed.connect(_volver_al_mapa)

	%LblMateria.text = "Práctica · %s" % materia.get("corto", "")
	%LblEscenarioTitulo.text = practica["titulo"]
	%LblEscenario.text = practica["escenario"]
	%Barra.max_value = ejercicios.size()
	_mostrar_ejercicio()


# ============================ PASO 4: EJERCICIO ============================
func _mostrar_ejercicio() -> void:
	var ej: Dictionary = ejercicios[indice]
	var tipo: String = ej["tipo"]
	evaluado = false
	%LblProgreso.text = "Ejercicio %d de %d" % [indice + 1, ejercicios.size()]
	%Barra.value = indice + 1
	%LblPuntosPractica.text = "%d pts" % puntos_practica
	%ChipPts.theme_type_variation = &"Chip"
	%TarjetaEscenario.visible = indice == 0          # el escenario se lee al inicio
	%LblInstruccion.text = ej["instruccion"]
	%PanelRetro.hide()
	%BotonesRetro.hide()
	%BotonesEjercicio.show()
	%BtnComprobar.disabled = true
	%BtnDeshacer.visible = tipo == "ordenar"
	%BtnDeshacer.disabled = true

	match tipo:
		"clasificar":
			%LblTipo.text = "CLASIFICAR"
			%LblAyuda.text = "Toca la etiqueta de cada tarjeta para cambiar su categoría: %s." % " / ".join(ej["categorias"])
		"construir":
			%LblTipo.text = "CONSTRUIR DIAGRAMA"
			%LblAyuda.text = "Toca la etiqueta de cada elemento para colocarlo en el diagrama: %s." % " / ".join(ej["categorias"])
		"ordenar":
			%LblTipo.text = "CONSTRUIR SECUENCIA"
			%LblAyuda.text = "Toca las piezas en el orden correcto. Usa Deshacer para quitar la última."
		"seleccionar":
			%LblTipo.text = "SELECCIONAR"
			%LblAyuda.text = "Marca las tareas que caben. Límite: %d h." % int(ej["limite"])

	for hijo in %Area.get_children():
		hijo.queue_free()
	tarjetas.clear()

	# Regla: las piezas se presentan en orden aleatorio en cada intento
	piezas = ej["piezas"].duplicate()
	piezas.shuffle()
	asignacion.clear(); secuencia.clear(); seleccion.clear()
	for _p in piezas:
		asignacion.append("")
		seleccion.append(false)

	match tipo:
		"clasificar", "construir": _construir_clasificar(ej)
		"ordenar":                 _construir_ordenar()
		"seleccionar":             _construir_seleccionar(ej)


## Tarjeta base de una pieza: panel "Opcion" con un HBox (texto + control a la derecha).
func _tarjeta_pieza(texto: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Opcion"
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var fila := HBoxContainer.new()
	fila.name = "Fila"
	fila.add_theme_constant_override("separation", 12)
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(fila)
	var lbl := Label.new()
	lbl.name = "Lbl"
	lbl.text = texto
	lbl.theme_type_variation = &"Negrita"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(lbl)
	return {"panel": panel, "fila": fila, "lbl": lbl}


# ---------- clasificar / construir ----------
func _construir_clasificar(ej: Dictionary) -> void:
	for i in piezas.size():
		var t := _tarjeta_pieza(piezas[i]["texto"])
		var chip := Button.new()
		chip.name = "Chip"
		chip.text = "Elegir ▾"
		chip.theme_type_variation = &"BotonSecundario"
		chip.custom_minimum_size = Vector2(170, 56)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.pressed.connect(_on_ciclar_categoria.bind(i, ej["categorias"]))
		t["fila"].add_child(chip)
		%Area.add_child(t["panel"])
		tarjetas.append(t["panel"])


## Cada toque pasa a la siguiente categoría (Elegir → cat1 → cat2 → … → Elegir).
func _on_ciclar_categoria(i: int, categorias: Array) -> void:
	if evaluado:
		return
	var actual: String = asignacion[i]
	var k := categorias.find(actual)
	var siguiente: String = categorias[0] if k < 0 else (categorias[k + 1] if k + 1 < categorias.size() else "")
	asignacion[i] = siguiente
	var chip: Button = tarjetas[i].get_node("Col/Fila/Chip")
	chip.text = (siguiente + " ▾") if siguiente != "" else "Elegir ▾"
	tarjetas[i].theme_type_variation = &"OpcionSel" if siguiente != "" else &"Opcion"
	var completo := true
	for a in asignacion:
		if a == "":
			completo = false
	%BtnComprobar.disabled = not completo


# ---------- ordenar ----------
func _construir_ordenar() -> void:
	for i in piezas.size():
		var t := _tarjeta_pieza(str(piezas[i]))
		var num := PanelContainer.new()
		num.name = "Num"
		num.theme_type_variation = &"ChipGris"
		num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lbl_num := Label.new()
		lbl_num.name = "LblNum"
		lbl_num.text = "—"
		lbl_num.theme_type_variation = &"Negrita"
		lbl_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		num.add_child(lbl_num)
		t["fila"].add_child(num)
		t["fila"].move_child(num, 0)
		var btn := Button.new()
		btn.name = "Btn"
		btn.theme_type_variation = &"BotonInvisible"
		btn.pressed.connect(_on_pieza_orden.bind(i))
		t["panel"].add_child(btn)
		%Area.add_child(t["panel"])
		tarjetas.append(t["panel"])


func _on_pieza_orden(i: int) -> void:
	if evaluado or i in secuencia:
		return
	secuencia.append(i)
	_pintar_secuencia()


func _on_deshacer() -> void:
	if evaluado or secuencia.is_empty():
		return
	secuencia.pop_back()
	_pintar_secuencia()


func _pintar_secuencia() -> void:
	for i in tarjetas.size():
		var pos := secuencia.find(i)
		var lbl_num: Label = tarjetas[i].get_node("Col/Fila/Num/LblNum")
		lbl_num.text = str(pos + 1) if pos >= 0 else "—"
		tarjetas[i].get_node("Col/Fila/Num").theme_type_variation = &"Chip" if pos >= 0 else &"ChipGris"
		tarjetas[i].theme_type_variation = &"OpcionSel" if pos >= 0 else &"Opcion"
	%BtnDeshacer.disabled = secuencia.is_empty()
	%BtnComprobar.disabled = secuencia.size() < piezas.size()


# ---------- seleccionar ----------
func _construir_seleccionar(ej: Dictionary) -> void:
	# Contador de horas usadas / límite
	var contador := PanelContainer.new()
	contador.name = "Contador"
	contador.theme_type_variation = &"TarjetaGris"
	var lbl_h := Label.new()
	lbl_h.name = "LblHoras"
	lbl_h.theme_type_variation = &"Negrita"
	lbl_h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	contador.add_child(lbl_h)
	%Area.add_child(contador)

	for i in piezas.size():
		var t := _tarjeta_pieza("%s · %d h" % [piezas[i]["texto"], int(piezas[i]["horas"])])
		var caja := Control.new()
		caja.name = "Caja"
		caja.set_script(icono_script)
		caja.custom_minimum_size = Vector2(30, 30)
		caja.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caja.tipo = "radio"; caja.color = GRIS; caja.grosor = 2.2
		t["fila"].add_child(caja)
		t["fila"].move_child(caja, 0)
		var btn := Button.new()
		btn.name = "Btn"
		btn.theme_type_variation = &"BotonInvisible"
		btn.pressed.connect(_on_pieza_seleccion.bind(i, int(ej["limite"])))
		t["panel"].add_child(btn)
		%Area.add_child(t["panel"])
		tarjetas.append(t["panel"])
	_pintar_seleccion(int(ej["limite"]))


func _horas_seleccionadas() -> int:
	var h := 0
	for i in piezas.size():
		if seleccion[i]:
			h += int(piezas[i]["horas"])
	return h


func _on_pieza_seleccion(i: int, limite: int) -> void:
	if evaluado:
		return
	if not seleccion[i] and _horas_seleccionadas() + int(piezas[i]["horas"]) > limite:
		# Restricción: no se puede exceder el límite de horas
		var lbl_h: Label = %Area.get_node("Contador/LblHoras")
		lbl_h.text = "No cabe: excederías las %d h disponibles" % limite
		lbl_h.theme_type_variation = &"TextoNaranja"
		return
	seleccion[i] = not seleccion[i]
	_pintar_seleccion(limite)


func _pintar_seleccion(limite: int) -> void:
	var usadas := _horas_seleccionadas()
	var lbl_h: Label = %Area.get_node("Contador/LblHoras")
	lbl_h.text = "Horas elegidas: %d de %d disponibles" % [usadas, limite]
	lbl_h.theme_type_variation = &"TextoAzul" if usadas > 0 else &"Negrita"
	var alguna := false
	for i in tarjetas.size():
		var caja: Control = tarjetas[i].get_node("Col/Fila/Caja")
		caja.tipo = "radio_sel" if seleccion[i] else "radio"
		caja.color = AZUL if seleccion[i] else GRIS
		tarjetas[i].theme_type_variation = &"OpcionSel" if seleccion[i] else &"Opcion"
		alguna = alguna or seleccion[i]
	%BtnComprobar.disabled = not alguna


# ============================ PASOS 5-6: COMPROBAR ============================
func _on_comprobar() -> void:
	if evaluado:
		return
	evaluado = true
	var ej: Dictionary = ejercicios[indice]
	var tipo: String = ej["tipo"]
	var correctas := 0
	var total := piezas.size()

	for i in piezas.size():
		var ok := false
		var detalle := ""
		match tipo:
			"clasificar", "construir":
				ok = asignacion[i] == piezas[i]["categoria"]
				if not ok:
					detalle = "Debía ir en: %s" % piezas[i]["categoria"]
			"ordenar":
				var pos_correcta: int = ej["piezas"].find(piezas[i])
				ok = secuencia.find(i) == pos_correcta
				if not ok:
					detalle = "Posición correcta: %d" % (pos_correcta + 1)
			"seleccionar":
				ok = seleccion[i] == bool(piezas[i]["correcta"])
				if not ok:
					detalle = "Sí debía elegirse" if piezas[i]["correcta"] else "No debía elegirse"
		if ok:
			correctas += 1
		_pintar_resultado_pieza(i, ok, detalle)

	piezas_correctas_total += correctas
	puntos_practica = int(round(float(piezas_correctas_total) / float(piezas_totales) * JuegoRepository.PUNTOS_PRACTICA))
	resumen_ejercicios.append({"instruccion": ej["instruccion"], "correctas": correctas, "total": total})

	var perfecto := correctas == total
	%LblPuntosPractica.text = "%d pts" % puntos_practica
	%ChipPts.theme_type_variation = &"ChipVerde" if perfecto else &"Chip"
	%PanelRetro.theme_type_variation = &"TarjetaVerde" if perfecto else &"TarjetaNaranja"
	%IconoRetro.tipo = "check" if perfecto else "alerta"
	%IconoRetro.fondo = VERDE if perfecto else NARANJA
	%LblRetroTitulo.text = "%d de %d piezas correctas" % [correctas, total]
	%LblRetroTitulo.theme_type_variation = &"TextoVerde" if perfecto else &"TextoNaranja"
	%LblRetroTexto.text = ej["justificacion"] if perfecto else "Solución recomendada: " + ej["justificacion"]
	%LblRetroTexto.theme_type_variation = &"TextoVerdeNormal" if perfecto else &"TextoNaranjaNormal"
	%BtnVerTeoria.visible = not perfecto and str(ej.get("concepto", "")) != ""   # alt. 1 → CU-04
	%BtnContinuar.text = "Ver resultado" if indice == ejercicios.size() - 1 else "Siguiente ejercicio"
	%BotonesEjercicio.hide()
	%PanelRetro.show()
	%BotonesRetro.show()


## Marca una pieza como correcta (verde) o incorrecta (naranja) con el detalle de la solución.
func _pintar_resultado_pieza(i: int, ok: bool, detalle: String) -> void:
	var panel: Control = tarjetas[i]
	panel.theme_type_variation = &"OpcionOk" if ok else &"OpcionMal"
	var lbl: Label = panel.get_node("Col/Fila/Lbl")
	lbl.theme_type_variation = &"TextoVerde" if ok else &"TextoNaranja"
	if panel.has_node("Btn"):
		panel.get_node("Btn").disabled = true
	if panel.has_node("Col/Fila/Chip"):
		panel.get_node("Col/Fila/Chip").disabled = true
	if not ok and detalle != "":
		# Solución recomendada en una segunda línea, bajo la pieza
		var tag := Label.new()
		tag.text = detalle.to_upper()
		tag.theme_type_variation = &"EtiquetaNaranja"
		tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.get_node("Col").add_child(tag)
	var marca := Control.new()
	marca.set_script(icono_script)
	marca.custom_minimum_size = Vector2(26, 26)
	marca.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	marca.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marca.tipo = "check" if ok else "cerrar"
	marca.color = VERDE if ok else NARANJA
	marca.grosor = 3.0
	panel.get_node("Col/Fila").add_child(marca)


## Alt. 1: "Ver teoría" muestra el concepto asociado al ejercicio sin salir de la práctica.
func _on_ver_teoria() -> void:
	var c := JuegoRepository.obtener_concepto_por_id(str(ejercicios[indice].get("concepto", "")))
	if c.is_empty():
		return
	var modulo := JuegoRepository.obtener_modulo(int(c["id_modulo"]))
	%LblTeoriaEtq.text = ("CONCEPTO · %s" % modulo.get("nombre", "")).to_upper()
	%LblTeoriaTitulo.text = c["titulo"]
	%LblTeoriaTexto.text = c["explicacion"]
	%LblTeoriaTruco.text = "Truco rápido: " + c["truco"]
	JuegoRepository.registrar_consulta_teoria()
	%PanelTeoria.show()


# ============================ PASO 7: SIGUIENTE ============================
func _on_continuar() -> void:
	indice += 1
	if indice < ejercicios.size():
		_mostrar_ejercicio()
	else:
		_terminar()


# ============================ PASOS 8-9: RESULTADO ============================
func _terminar() -> void:
	var res := JuegoRepository.registrar_intento_practica(id_materia, piezas_correctas_total, piezas_totales)
	var aprobada: bool = res["aprobada"]

	%LblResMateria.text = "Práctica de ingeniero · %s" % materia.get("corto", "")
	%LblResPorcentaje.text = "%d %%" % res["porcentaje"]
	%Anillo.porcentaje = res["porcentaje"]
	%Anillo.color = VERDE if aprobada else NARANJA
	%LblResPuntos.text = str(res["puntos"])
	%LblResPiezas.text = "%d/%d" % [piezas_correctas_total, piezas_totales]
	%LblResIntentos.text = str(res["intentos"])

	if aprobada:
		%LblResTitulo.text = "¡Materia dominada!" if res["recien_dominada"] else "¡Práctica aprobada!"
		%PanelEstado.theme_type_variation = &"TarjetaVerde"
		%IconoEstado.tipo = "check"; %IconoEstado.fondo = VERDE; %IconoEstado.color = Color.WHITE
		%LblResEstado.text = "%s · Dominada" % materia.get("corto", "")
		%LblResEstado.theme_type_variation = &"TextoVerde"
		%LblResDetalle.theme_type_variation = &"TextoVerdeNormal"
		%LblResDetalle.text = "Alcanzaste el mínimo de %d %%." % JuegoRepository.PORCENTAJE_MINIMO
		if not res["guardado"]:
			%LblResDetalle.text += " El intento no supera tu mejor puntaje, así que no se guarda."
		%BtnReintentar.hide()
		%BtnVolverMapa.theme_type_variation = &""
	else:
		%LblResTitulo.text = "Práctica terminada"
		%PanelEstado.theme_type_variation = &"TarjetaNaranja"
		%IconoEstado.tipo = "alerta"; %IconoEstado.fondo = NARANJA; %IconoEstado.color = Color.WHITE
		%LblResEstado.text = "No alcanzaste el mínimo"
		%LblResEstado.theme_type_variation = &"TextoNaranja"
		%LblResDetalle.theme_type_variation = &"TextoNaranjaNormal"
		%LblResDetalle.text = "Necesitas %d %% para dominar la materia." % JuegoRepository.PORCENTAJE_MINIMO
		if res["mejor_previo"] >= 0:
			%LblResDetalle.text += " Se conserva tu mejor puntaje: %d %%." % res["mejor_previo"]
		%BtnReintentar.show()
		%BtnVolverMapa.theme_type_variation = &"BotonSecundario"

	var nuevas: Array = res.get("insignias_nuevas", [])
	if not nuevas.is_empty():
		var nombres: Array = []
		for i in nuevas:
			nombres.append(i["titulo"])
		%LblResDetalle.text += "\nNueva insignia: %s" % ", ".join(nombres)

	# Resumen de los ejercicios
	for hijo in %Resumen.get_children():
		hijo.queue_free()
	for k in resumen_ejercicios.size():
		var r: Dictionary = resumen_ejercicios[k]
		var fila := HBoxContainer.new()
		fila.add_theme_constant_override("separation", 10)
		var lbl := Label.new()
		lbl.text = "%d. %s" % [k + 1, r["instruccion"]]
		lbl.theme_type_variation = &"Pequeno"
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl.max_lines_visible = 2
		fila.add_child(lbl)
		var chip := PanelContainer.new()
		var todo: bool = r["correctas"] == r["total"]
		chip.theme_type_variation = &"ChipVerde" if todo else &"ChipGris"
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var n := Label.new()
		n.text = "%d/%d" % [r["correctas"], r["total"]]
		n.theme_type_variation = &"TextoVerde" if todo else &"TextoNaranja"
		chip.add_child(n)
		fila.add_child(chip)
		%Resumen.add_child(fila)

	%LblResTotal.text = "%d pts" % res["puntos_totales"]
	if res["puntos_sumados"] > 0:
		%ChipDelta.theme_type_variation = &"ChipVerde"
		%LblResDelta.text = "+%d" % res["puntos_sumados"]
		%LblResDelta.theme_type_variation = &"TextoVerde"
	else:
		%ChipDelta.theme_type_variation = &"ChipGris"
		%LblResDelta.text = "Sin cambios"
		%LblResDelta.theme_type_variation = &"Pequeno"

	%PanelEjercicio.hide()
	%PanelResultado.show()


func _on_reintentar() -> void:
	indice = 0
	piezas_correctas_total = 0
	puntos_practica = 0
	resumen_ejercicios.clear()
	%PanelResultado.hide()
	%PanelEjercicio.show()
	_mostrar_ejercicio()


func _volver_al_mapa() -> void:
	JuegoRepository.materia_seleccionada = id_materia
	get_tree().change_scene_to_file(RUTA_MAPA)
