# res://scenes/cu02_mapa/mapa.gd
# CU-02: Elegir módulo. Mapa 2D de nodos en zigzag + hoja de detalle.
#
# Flujo (SRS 1.1):
#   1-2. "Jugar" → se carga el mapa con el estado de cada módulo  → _construir_mapa()
#   3-4. Toca un módulo desbloqueado/completado → detalle            → _mostrar_detalle()
#   5-6. "Iniciar" → actividad (CU-03)                               → _on_accion()
#   Alt. bloqueado → requisito de desbloqueo                         → _mostrar_bloqueado()
extends Control

const RUTA_MENU      := "res://scenes/menu/Menu.tscn"
const RUTA_ACTIVIDAD := "res://scenes/cu03_actividad/Actividad.tscn"

const COLOR_VERDE := Color("#178A4C")
const COLOR_AZUL  := Color("#2F55E6")
const COLOR_GRIS  := Color("#C9CDD9")
const COLOR_GRIS_ICONO := Color("#7A8197")

const TAM_NODO := 84.0
# Posición horizontal (0-1) de cada módulo, de abajo hacia arriba (zigzag como el mockup)
const COLUMNAS := [0.17, 0.5, 0.83, 0.5, 0.17, 0.5, 0.83, 0.5]

var modulos: Array = []
var modulo_sel: Dictionary = {}
var nodos: Array[Control] = []
var icono_script := preload("res://assets/ui/Icono.gd")


func _ready() -> void:
	%BtnVolver.pressed.connect(func(): get_tree().change_scene_to_file(RUTA_MENU))
	%BtnCerrar.pressed.connect(%PanelDetalle.hide)
	%BtnCerrarFondo.pressed.connect(%PanelDetalle.hide)
	%BtnAccion.pressed.connect(_on_accion)
	%BtnEntendido.pressed.connect(%PanelBloqueado.hide)
	%BtnCerrarBloqueado.pressed.connect(%PanelBloqueado.hide)
	%AreaMapa.resized.connect(_posicionar_nodos)
	_construir_mapa()


# ============================== MAPA ==============================
func _construir_mapa() -> void:
	modulos = JuegoRepository.obtener_modulos()
	%LblPuntos.text = "%d pts" % JuegoRepository.obtener_puntos_totales()
	%LblResumen.text = "%d de %d módulos completados" % [JuegoRepository.modulos_completados(), modulos.size()]

	for n in nodos:
		n.queue_free()
	nodos.clear()

	for m in modulos:
		nodos.append(_crear_nodo(m))
	_posicionar_nodos()


## Crea el nodo circular + su etiqueta como un Control contenedor.
func _crear_nodo(m: Dictionary) -> Control:
	var estado: String = m["estado"]
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
			ic.tipo = "play"; ic.color = Color.WHITE
		_:
			ic.tipo = "candado"; ic.color = COLOR_GRIS_ICONO
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 22; ic.offset_top = 22; ic.offset_right = -22; ic.offset_bottom = -22
	btn.add_child(ic)

	var lbl := Label.new()
	lbl.text = "%d · %s" % [int(m["id"]), _nombre_corto(m["nombre"])]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.theme_type_variation = &"NodoTextoActivo" if estado == "desbloqueado" else &"NodoTexto"
	lbl.position = Vector2(0, TAM_NODO + 6)
	lbl.size = Vector2(cont.custom_minimum_size.x, 22)
	cont.add_child(lbl)

	%AreaMapa.add_child(cont)
	return cont


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

	# Conectores punteados entre módulos consecutivos
	%Conectores.limpiar()
	for i in n - 1:
		var color := COLOR_GRIS
		if modulos[i]["estado"] == "completado":
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

	%LblDetEncabezado.text = "MÓDULO %d · %s" % [id, estado.to_upper()]
	%LblDetEncabezado.theme_type_variation = &"EtiquetaVerde" if completado else &"EtiquetaAzul"
	%LblDetNombre.text = m["nombre"]
	%LblDetTipo.text = m["tipo"].capitalize()
	%IconoTile.tipo = "puzzle" if m["tipo"] == "puzzle" else "quiz"
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

	%NotaCompletado.visible = completado
	%LblDetDescripcion.visible = not completado
	if not completado:
		var desc: String = m["descripcion"]
		if mejor < 0:
			desc += " Aún no tienes intentos en este módulo."
		%LblDetDescripcion.text = desc
	%BtnAccion.text = "Volver a jugar" if completado else "Iniciar"
	%PanelDetalle.show()


func _mostrar_bloqueado(m: Dictionary) -> void:
	var id := int(m["id"])
	var previo := JuegoRepository.obtener_modulo(id - 1)
	%LblBloqEncabezado.text = "MÓDULO %d · BLOQUEADO" % id
	%LblBloqNombre.text = m["nombre"]
	%LblBloqNumero.text = str(id - 1)
	%LblBloqRequisito.text = "Completa [color=#2F55E6]Módulo %d · %s[/color]" % [id - 1, previo.get("nombre", "")]
	%PanelBloqueado.show()


func _on_accion() -> void:
	# Avisar al CU-03 qué módulo se eligió y cambiar de pantalla
	JuegoRepository.modulo_seleccionado = int(modulo_sel["id"])
	if ResourceLoader.exists(RUTA_ACTIVIDAD):
		get_tree().change_scene_to_file(RUTA_ACTIVIDAD)
	else:
		print("Pantalla pendiente (CU-03): ", RUTA_ACTIVIDAD)
