# res://scenes/cu07_config/configuracion.gd
# CU-07: Configurar juego. Modo claro/oscuro y paleta de color de la interfaz.
# Las paletas se desbloquean con el avance (como los avatares) para incentivar
# seguir jugando. Todo se guarda en el perfil activo (JuegoRepository.config).
extends Control

const RUTA_MENU := "res://scenes/menu/Menu.tscn"

var icono_script := preload("res://assets/ui/Icono.gd")


func _ready() -> void:
	%BtnVolver.pressed.connect(_volver)
	%BtnClaro.pressed.connect(func(): _cambiar_modo("claro"))
	%BtnOscuro.pressed.connect(func(): _cambiar_modo("oscuro"))
	%BtnRestablecer.pressed.connect(_restablecer)
	_pintar()


func _pintar() -> void:
	var cfg := JuegoRepository.obtener_configuracion()
	%BtnClaro.set_pressed_no_signal(cfg["modo"] == "claro")
	%BtnOscuro.set_pressed_no_signal(cfg["modo"] == "oscuro")
	_construir_paletas(str(cfg["paleta"]))


func _cambiar_modo(modo: String) -> void:
	JuegoRepository.actualizar_modo(modo)     # Estilo escucha la señal y repinta
	_pintar()


func _construir_paletas(actual: String) -> void:
	for h in %GridPaletas.get_children():
		h.queue_free()
	var catalogo := JuegoRepository.obtener_catalogo_paletas()
	var disponibles := 0
	for p in catalogo:
		if p["disponible"]:
			disponibles += 1
		%GridPaletas.add_child(_crear_boton_paleta(p, str(p["id"]) == actual))
	%LblPaletaSub.text = "%d de %d colores desbloqueados. Los demás se ganan avanzando en los temas." % [disponibles, catalogo.size()]


func _crear_boton_paleta(p: Dictionary, elegida: bool) -> Button:
	var disponible: bool = p["disponible"]
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 150)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.theme_type_variation = &"BotonAvatar"
	b.toggle_mode = true
	b.set_pressed_no_signal(elegida)
	b.disabled = not disponible

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	b.add_child(col)

	var centro := CenterContainer.new()
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(centro)
	var circulo := Control.new()
	circulo.set_script(icono_script)
	circulo.custom_minimum_size = Vector2(52, 52)
	circulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circulo.tipo = "candado" if not disponible else ("check" if elegida else "")
	circulo.color = Color.WHITE
	circulo.grosor = 3.0
	var color := Color(str(p["color"]))
	circulo.fondo = color if disponible else color.lerp(Color("#C9CDD9"), 0.6)
	# El círculo de color no debe cambiar con la paleta: se marca el original como fijo
	circulo.set_meta("estilo_fijo", true)
	centro.add_child(circulo)

	var nombre := Label.new()
	nombre.text = str(p["nombre"])
	nombre.theme_type_variation = &"Negrita" if disponible else &"TextoSecundario"
	nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nombre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nombre)

	var pie := Label.new()
	pie.theme_type_variation = &"Pequeno"
	pie.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pie.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pie.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pie.custom_minimum_size = Vector2(0, 44)
	if disponible:
		pie.text = "En uso" if elegida else ("" if int(p["meta"]) == 0 else "Desbloqueado")
	else:
		pie.text = "%s (%d/%d)" % [p["condicion"], int(p["progreso"]), int(p["meta"])]
	col.add_child(pie)

	b.pressed.connect(func():
		if JuegoRepository.actualizar_paleta(str(p["id"])):
			_pintar())
	return b


func _restablecer() -> void:
	JuegoRepository.restablecer_configuracion()
	_pintar()


## Botón Atrás de Android (Navegacion).
func atras() -> void:
	_volver()


func _volver() -> void:
	get_tree().change_scene_to_file(RUTA_MENU)
