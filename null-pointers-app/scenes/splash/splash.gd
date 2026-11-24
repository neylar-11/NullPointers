# res://scenes/splash/splash.gd
# Pantalla de inicio de SoftPlay: "ventana de terminal" oscura donde el logo
# se escribe letra por letra, aparece el lema y se pasa al menú principal.
# Tocar la pantalla salta la animación.
extends Control

const RUTA_MENU := "res://scenes/menu/Menu.tscn"
const ESPERA_FINAL := 1.1     # segundos tras terminar de escribir

var _saliendo := false


func _ready() -> void:
	_pintar_ventana()
	%Logo.escritura_terminada.connect(_on_logo_listo)
	# el usuario puede saltar el splash tocando
	gui_input.connect(func(ev: InputEvent):
		if ev is InputEventScreenTouch or ev is InputEventMouseButton:
			if ev.pressed:
				_ir_al_menu())
	# seguro: si por alguna razón no se emite la señal, igual se avanza
	get_tree().create_timer(4.0).timeout.connect(_ir_al_menu)


## Fondo de la "ventana" con los tres puntos de la barra de título (estilo terminal).
func _pintar_ventana() -> void:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color("#1C2238")
	estilo.border_color = Color("#2A3350")
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(22)
	%Ventana.add_theme_stylebox_override("panel", estilo)

	for color in [Color("#FF5F57"), Color("#FEBC2E"), Color("#28C840")]:
		var punto := Panel.new()
		punto.custom_minimum_size = Vector2(16, 16)
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_corner_radius_all(8)
		punto.add_theme_stylebox_override("panel", sb)
		%Puntos.add_child(punto)


func _on_logo_listo() -> void:
	var tw := create_tween()
	tw.tween_property(%LblTagline, "modulate:a", 1.0, 0.35)
	tw.tween_property(%LblCargando, "modulate:a", 1.0, 0.25)
	tw.tween_interval(ESPERA_FINAL)
	tw.tween_callback(_ir_al_menu)


func _ir_al_menu() -> void:
	if _saliendo:
		return
	_saliendo = true
	if ResourceLoader.exists(RUTA_MENU):
		get_tree().change_scene_to_file(RUTA_MENU)
