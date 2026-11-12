# res://scenes/cu02_mapa/mapa.gd
# CU-02: Elegir módulo. Mapa 2D de nodos en zigzag + hoja de detalle.
#
# Flujo (SRS 1.1):
#   1-2. "Jugar" → se carga el mapa con el estado de cada módulo  → _construir_mapa()
#   3-4. Toca un módulo desbloqueado/completado → detalle            → _mostrar_detalle()
#   5-6. "Iniciar" → actividad (CU-03)                               → _on_accion()
#   Alt. bloqueado → requisito de desbloqueo                         → _mostrar_bloqueado()
#
# Sprint 3:
#   CU-08: el mapa muestra SOLO los módulos de JuegoRepository.materia_seleccionada
#          (la pone la pantalla de materias). "Volver" regresa al catálogo de materias.
#   CU-11: al final del mapa hay un nodo "Práctica de ingeniero" que se desbloquea
#          cuando todos los módulos de la materia están completados.
extends Control

const RUTA_MENU      := "res://scenes/menu/Menu.tscn"
const RUTA_MATERIAS  := "res://scenes/cu08_materias/Materias.tscn"
const RUTA_ACTIVIDAD := "res://scenes/cu03_actividad/Actividad.tscn"
const RUTA_PRACTICA  := "res://scenes/cu11_practica/Practica.tscn"

const COLOR_VERDE := Color("#178A4C")
const COLOR_AZUL  := Color("#2F55E6")
const COLOR_GRIS  := Color("#C9CDD9")
const COLOR_GRIS_ICONO := Color("#7A8197")

const TAM_NODO := 84.0
# Posición horizontal (0-1) de cada módulo, de abajo hacia arriba (zigzag como el mockup)
const COLUMNAS := [0.17, 0.5, 0.83, 0.5, 0.17, 0.5, 0.83, 0.5]
const ID_PRACTICA := -1          # id ficticio del nodo final "Práctica de ingeniero" (CU-11)

var id_materia: int = 1
var materia: Dictionary = {}
var modulos: Array = []
var modulo_sel: Dictionary = {}
var nodos: Array[Control] = []
var icono_script := preload("res://assets/ui/Icono.gd")


func _ready() -> void:
	%BtnVolver.pressed.connect(_volver)
	%BtnCerrar.pressed.connect(%PanelDetalle.hide)
	%BtnCerrarFondo.pressed.connect(%PanelDetalle.hide)
	%BtnAccion.pressed.connect(_on_accion)
	%BtnEntendido.pressed.connect(%PanelBloqueado.hide)
	%BtnCerrarBloqueado.pressed.connect(%PanelBloqueado.hide)
	%AreaMapa.resized.connect(_posicionar_nodos)
	_construir_mapa()


## CU-08 paso 6: al volver del mapa se regresa al catálogo de materias (o al menú).
func _volver() -> void:
	if ResourceLoader.exists(RUTA_MATERIAS):
		get_tree().change_scene_to_file(RUTA_MATERIAS)
	else:
		get_tree().change_scene_to_file(RUTA_MENU)


# ============================== MAPA ==============================
func _construir_mapa() -> void:
	id_materia = JuegoRepository.materia_seleccionada
	materia = JuegoRepository.obtener_materia(id_materia)
	if materia.is_empty():
		id_materia = 1
		materia = JuegoRepository.obtener_materia(1)
	modulos = JuegoRepository.obtener_modulos_materia(id_materia)
	%LblPuntos.text = "%d pts" % JuegoRepository.obtener_puntos_totales()
	%LblResumen.text = "%d de %d módulos completados" % [JuegoRepository.modulos_completados_materia(id_materia), modulos.size()]
	%LblMateria.text = materia.get("corto", "")
	%LblTituloBarra.text = "Mapa de módulos"

	for n in nodos:
		n.queue_free()
	nodos.clear()

	for m in modulos:
		nodos.append(_crear_nodo(m))
	# CU-11: nodo final de la práctica (solo si la materia tiene práctica)
	if not JuegoRepository.obtener_practica(id_materia).is_empty():
		nodos.append(_crear_nodo(_nodo_practica()))
	_posicionar_nodos()


## Datos del nodo final "Práctica de ingeniero" (CU-11) con el mismo formato que un módulo.
func _nodo_practica() -> Dictionary:
	var estado_p := JuegoRepository.obtener_practica_estado(id_materia)
	var estado := "bloqueado"
	if estado_p["dominada"]:
		estado = "completado"
	elif JuegoRepository.practica_disponible(id_materia):
		estado = "desbloqueado"
	var practica := JuegoRepository.obtener_practica(id_materia)
	return {
		"id": ID_PRACTICA,
		"id_materia": id_materia,
		"nombre": "Práctica de ingeniero",
		"tipo": "practica",
		"descripcion": "Escenario: %s. %d ejercicios de manipulación (clasificar, construir, seleccionar)." % [
			practica.get("titulo", ""), practica.get("ejercicios", []).size()],
		"num_preguntas": practica.get("ejercicios", []).size(),
		"puntos_maximos": JuegoRepository.PUNTOS_PRACTICA,
		"estado": estado,
		"mejor_puntaje": int(estado_p["mejor_porcentaje"]),
		"puntos_obtenidos": int(estado_p["mejor_puntos"]),
	}


## Crea el nodo circular + su etiqueta como un Control contenedor.
func _crear_nodo(m: Dictionary) -> Control:
	var estado: String = m["estado"]
	var es_practica := int(m["id"]) == ID_PRACTICA
	var cont := Control.new()
	cont.custom_minimum_size = Vector2(TAM_NODO * 2.2, TAM_NODO + 30)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(TAM_NODO, TAM_NODO)
	btn.size = Vector2(TAM_NODO, TAM_NODO)
	btn.position = Vector2((cont.custom_minimum_size.x - TAM_NODO) / 2, 0)
	match estado:
		"completado":   btn.theme_type_variation = &"NodoVerde"
		"desbloqueado": btn.theme_type_variation = &"NodoAzul"
		_:              btn.theme_type_variation = &"NodoGris"
	btn.pressed.connect(_on_nodo_presionado.bind(m))
	cont.add_child(btn)

	var ic := Control.new()
	ic.set_script(icono_script)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.grosor = 3.0
	match estado:
		"completado":
			ic.tipo = "check"; ic.color = Color.WHITE
		"desbloqueado":
			ic.tipo = "puzzle" if es_practica else "play"; ic.color = Color.WHITE
		_:
			ic.tipo = "candado"; ic.color = COLOR_GRIS_ICONO
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 22; ic.offset_top = 22; ic.offset_right = -22; ic.offset_bottom = -22
	btn.add_child(ic)

	var lbl := Label.new()
	if es_practica:
		lbl.text = "Práctica de ingeniero"
	else:
		lbl.text = "%d · %s" % [_numero_en_materia(m), _nombre_corto(m["nombre"])]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.theme_type_variation = &"NodoTextoActivo" if estado == "desbloqueado" else &"NodoTexto"
	lbl.position = Vector2(0, TAM_NODO + 6)
	lbl.size = Vector2(cont.custom_minimum_size.x, 22)
	cont.add_child(lbl)

	%AreaMapa.add_child(cont)
	return cont


## Número del módulo dentro de su materia (1, 2, 3…) para las etiquetas del mapa.
func _numero_en_materia(m: Dictionary) -> int:
	for k in modulos.size():
		if int(modulos[k]["id"]) == int(m["id"]):
			return k + 1
	return int(m["id"])


## Nombres cortos para que quepan bajo el nodo (como en el mockup).
func _nombre_corto(nombre: String) -> String:
	var cortos := {"Requerimientos de software": "Requerimientos", "Modelado con UML": "Modelado UML",
		"Ciclo de vida del software": "Ciclo de vida"}
	return cortos.get(nombre, nombre)


func _posicionar_nodos() -> void:
	if nodos.is_empty():
		return
	var area: Vector2 = %AreaMapa.size
	var n := nodos.size()
	var alto_fila := (area.y - (TAM_NODO + 30)) / maxf(n - 1, 1)
	var centros: Array[Vector2] = []
	for i in n:
		var cont := nodos[i]
		var cx: float = area.x * COLUMNAS[i % COLUMNAS.size()]
		var cy: float = area.y - (TAM_NODO + 30) - alto_fila * i   # de abajo hacia arriba
		cont.position = Vector2(cx - cont.custom_minimum_size.x / 2, cy)
		centros.append(Vector2(cx, cy + TAM_NODO / 2))

	# Conectores punteados entre módulos consecutivos (el último conecta con la práctica)
	%Conectores.limpiar()
	for i in n - 1:
		var color := COLOR_GRIS
		if i < modulos.size() and modulos[i]["estado"] == "completado":
			color = COLOR_VERDE
		var dir := (centros[i + 1] - centros[i]).normalized()
		%Conectores.agregar(centros[i] + dir * (TAM_NODO / 2 + 4), centros[i + 1] - dir * (TAM_NODO / 2 + 4), color)


# ============================ DETALLE ============================
func _on_nodo_presionado(m: Dictionary) -> void:
	modulo_sel = m
	if m["estado"] == "bloqueado":
		_mostrar_bloqueado(m)
	else:
		_mostrar_detalle(m)


func _mostrar_detalle(m: Dictionary) -> void:
	var id := int(m["id"])
	var estado: String = m["estado"]
	var mejor := int(m["mejor_puntaje"])
	var completado := estado == "completado"
	var es_practica := id == ID_PRACTICA

	if es_practica:
		%LblDetEncabezado.text = "PRÁCTICA · %s" % ("DOMINADA" if completado else "DISPONIBLE")
		%LblDetTipo.text = "Práctica"
		%IconoTile.tipo = "puzzle"
	else:
		%LblDetEncabezado.text = "MÓDULO %d · %s" % [_numero_en_materia(m), estado.to_upper()]
		%LblDetTipo.text = m["tipo"].capitalize()
		%IconoTile.tipo = "puzzle" if m["tipo"] == "puzzle" else "quiz"
	%LblDetEncabezado.theme_type_variation = &"EtiquetaVerde" if completado else &"EtiquetaAzul"
	%LblDetNombre.text = m["nombre"]
	%LblDetMaximos.text = str(int(m["puntos_maximos"]))
	if mejor < 0:
		%LblDetMejor.text = "—"
		%TileMejorP.theme_type_variation = &"Tile"
		%LblDetMejor.theme_type_variation = &"TituloTarjeta"
	else:
		%LblDetMejor.text = "%d · %d %%" % [int(m["puntos_obtenidos"]), mejor]
		%TileMejorP.theme_type_variation = &"TileVerde"
		%LblDetMejor.theme_type_variation = &"NumeroVerde"
		%LblDetMejor.add_theme_font_size_override("font_size", 24)

	%NotaCompletado.visible = completado and not es_practica
	%LblDetDescripcion.visible = not completado or es_practica
	if es_practica:
		var desc: String = m["descripcion"]
		if completado:
			desc += " Materia dominada: si vuelves a jugar, el intento solo se guarda si supera tu mejor puntaje."
		%LblDetDescripcion.text = desc
	elif not completado:
		var desc: String = m["descripcion"]
		if mejor < 0:
			desc += " Aún no tienes intentos en este módulo."
		%LblDetDescripcion.text = desc
	%BtnAccion.text = "Volver a jugar" if completado else "Iniciar"
	%PanelDetalle.show()


func _mostrar_bloqueado(m: Dictionary) -> void:
	if int(m["id"]) == ID_PRACTICA:
		# CU-11: la práctica exige todos los módulos de la materia completados
		var faltan := modulos.size() - JuegoRepository.modulos_completados_materia(id_materia)
		%LblBloqEncabezado.text = "PRÁCTICA · BLOQUEADA"
		%LblBloqNombre.text = m["nombre"]
		%LblBloqNumero.text = str(faltan)
		%LblBloqRequisito.text = "Completa [color=#2F55E6]todos los módulos de %s[/color] (te faltan %d)" % [materia.get("corto", "la materia"), faltan]
		%PanelBloqueado.show()
		return
	var numero := _numero_en_materia(m)
	var previo: Dictionary = modulos[numero - 2] if numero >= 2 else {}
	%LblBloqEncabezado.text = "MÓDULO %d · BLOQUEADO" % numero
	%LblBloqNombre.text = m["nombre"]
	%LblBloqNumero.text = str(numero - 1)
	%LblBloqRequisito.text = "Completa [color=#2F55E6]Módulo %d · %s[/color]" % [numero - 1, previo.get("nombre", "")]
	%PanelBloqueado.show()


func _on_accion() -> void:
	if int(modulo_sel["id"]) == ID_PRACTICA:
		# CU-11 paso 2: "Iniciar" abre la práctica de la materia
		JuegoRepository.practica_materia = id_materia
		get_tree().change_scene_to_file(RUTA_PRACTICA)
		return
	# Avisar al CU-03 qué módulo se eligió y cambiar de pantalla
	JuegoRepository.modulo_seleccionado = int(modulo_sel["id"])
	if ResourceLoader.exists(RUTA_ACTIVIDAD):
		get_tree().change_scene_to_file(RUTA_ACTIVIDAD)
	else:
		print("Pantalla pendiente (CU-03): ", RUTA_ACTIVIDAD)
