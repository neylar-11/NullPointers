# res://scenes/cu01_perfil/perfil.gd
# CU-01: Editar perfil (SRS 1.1). El perfil se crea automáticamente; aquí se
# cambia la foto (avatar del catálogo), el nombre de usuario (3-20 caracteres)
# y la contraseña (4-8 dígitos, doble confirmación).
extends Control

const RUTA_MENU := "res://scenes/menu/Menu.tscn"
const RUTA_SESION := "res://scenes/cu12_sesion/Sesion.tscn"   # CU-12

var avatar_elegido := ""
var grupo_avatares := ButtonGroup.new()
var icono_script := preload("res://assets/ui/Icono.gd")
var cambios := {"foto": false, "nombre": false, "contrasena": false}


func _ready() -> void:
	# --- Mi perfil ---
	%BtnVolver.pressed.connect(_ir_al_menu)
	%BtnCancelar.pressed.connect(_ir_al_menu)
	%BtnVolverMenu.pressed.connect(_ir_al_menu)
	%BtnSeguir.pressed.connect(_mostrar_menu_perfil.bind(false))
	%BtnFoto.pressed.connect(_abrir_foto)
	%BtnNombre.pressed.connect(_abrir_nombre)
	%BtnContrasena.pressed.connect(_abrir_contrasena)
	# --- CU-12: sesión y eliminación ---
	%BtnSesion.pressed.connect(func(): %PanelCerrarSesion.show())
	%BtnCancelarCerrar.pressed.connect(%PanelCerrarSesion.hide)
	%BtnConfirmarCerrar.pressed.connect(_cerrar_sesion)
	%BtnEliminarPerfil.pressed.connect(_abrir_eliminar)
	%BtnCancelarEliminar.pressed.connect(%PanelEliminarPerfil.hide)
	%BtnConfirmarEliminar.pressed.connect(_eliminar_perfil)
	%TxtEliminarContra.text_changed.connect(func(_t): %LblEliminarError.hide())

	# --- Nombre ---
	%BtnVolverNombre.pressed.connect(_mostrar_menu_perfil.bind(false))
	%BtnCancelarNombre.pressed.connect(_mostrar_menu_perfil.bind(false))
	%TxtNombre.text_changed.connect(_validar_nombre)
	%TxtNombre.text_submitted.connect(func(_t): _guardar_nombre())
	%BtnGuardarNombre.pressed.connect(_guardar_nombre)

	# --- Foto ---
	%BtnVolverFoto.pressed.connect(_mostrar_menu_perfil.bind(false))
	%BtnCancelarFoto.pressed.connect(_mostrar_menu_perfil.bind(false))
	%BtnUsarAvatar.pressed.connect(_guardar_avatar)
	_construir_catalogo_avatares()

	# --- Contraseña ---
	%BtnVolverContra.pressed.connect(_mostrar_menu_perfil.bind(false))
	%BtnCancelarContra.pressed.connect(_mostrar_menu_perfil.bind(false))
	%TxtContra1.text_changed.connect(func(_t): _validar_contrasena())
	%TxtContra2.text_changed.connect(func(_t): _validar_contrasena())
	%TxtContra2.text_submitted.connect(func(_t): _guardar_contrasena())
	%BtnOjo.pressed.connect(func():
		%TxtContra1.secret = not %TxtContra1.secret
		%TxtContra2.secret = %TxtContra1.secret)
	%BtnGuardarContra.pressed.connect(_guardar_contrasena)
	%BtnQuitarContra.pressed.connect(func():
		JuegoRepository.quitar_contrasena()
		cambios["contrasena"] = true
		_mostrar_menu_perfil(true))

	_mostrar_menu_perfil(false)


# ============================ MI PERFIL ============================
func _mostrar_menu_perfil(actualizado: bool) -> void:
	var p := JuegoRepository.obtener_perfil()
	%AvatarGrande.avatar_id = p.get("avatar_id", "avatar_01")
	%LblAliasPerfil.text = p["alias"]
	%LblSubPerfil.text = "Contraseña configurada" if JuegoRepository.tiene_contrasena() else "Sin contraseña: cualquiera con este teléfono puede entrar a tu perfil"

	%BannerOk.visible = actualizado
	%Resumen.visible = actualizado
	%Opciones.visible = not actualizado
	%BtnVolverMenu.visible = actualizado
	%BtnSeguir.visible = actualizado
	%BtnCancelar.visible = not actualizado
	if actualizado:
		%LblResFoto.text = "Actualizada" if cambios["foto"] else "Sin cambios"
		%LblResNombre.text = p["alias"]
		%LblResContra.text = "Configurada" if JuegoRepository.tiene_contrasena() else "Sin configurar"
		%LblResFoto.theme_type_variation = &"TextoVerde" if cambios["foto"] else &"TextoSecundario"
		%LblResContra.theme_type_variation = &"TextoVerde" if JuegoRepository.tiene_contrasena() else &"TextoSecundario"

	_mostrar_panel(%PanelMenu)


func _mostrar_panel(panel: Control) -> void:
	for p in [%PanelMenu, %PanelNombre, %PanelFoto, %PanelContrasena]:
		p.visible = p == panel


## Botón Atrás de Android (Navegacion).
func atras() -> void:
	if %PanelCerrarSesion.visible:
		%PanelCerrarSesion.hide()
	elif %PanelEliminarPerfil.visible:
		%PanelEliminarPerfil.hide()
	elif %PanelMenu.visible:
		_ir_al_menu()
	else:
		_mostrar_menu_perfil(false)


# ============================ CU-12: SESIÓN ============================
func _cerrar_sesion() -> void:
	JuegoRepository.cerrar_sesion()
	get_tree().change_scene_to_file(RUTA_SESION)


func _abrir_eliminar() -> void:
	%TxtEliminarContra.visible = JuegoRepository.tiene_contrasena()
	%TxtEliminarContra.text = ""
	%LblEliminarError.hide()
	%PanelEliminarPerfil.show()


func _eliminar_perfil() -> void:
	if JuegoRepository.tiene_contrasena() and %TxtEliminarContra.text != JuegoRepository.obtener_perfil().get("contrasena", ""):
		%LblEliminarError.show()
		return
	JuegoRepository.eliminar_perfil(JuegoRepository.perfil_activo_id)
	get_tree().change_scene_to_file(RUTA_SESION)


func _ir_al_menu() -> void:
	get_tree().change_scene_to_file(RUTA_MENU)


# ============================ NOMBRE ============================
func _abrir_nombre() -> void:
	var alias: String = JuegoRepository.obtener_perfil()["alias"]
	%LblActual.text = "Tu nombre actual es [b]%s[/b]. Puedes cambiarlo cuando quieras." % alias
	%LblAnterior.text = alias
	%TxtNombre.text = ""
	_validar_nombre("")
	_mostrar_panel(%PanelNombre)
	%TxtNombre.grab_focus()


func _validar_nombre(texto: String) -> void:
	var n := texto.strip_edges().length()
	var valido := JuegoRepository.alias_valido(texto)
	%LblContador.text = "%d / %d" % [n, JuegoRepository.ALIAS_MAX]
	%BtnGuardarNombre.disabled = not valido
	if n == 0:
		%TxtNombre.theme_type_variation = &""
		%LblAyudaNombre.text = "Entre 3 y 20 caracteres"
		%LblAyudaNombre.theme_type_variation = &"TextoSecundario"
		%LblContador.theme_type_variation = &"Negrita"
		%TarjetaInfo.hide()
	elif valido:
		%TxtNombre.theme_type_variation = &"EntradaOk"
		%LblAyudaNombre.text = "Entre 3 y 20 caracteres"
		%LblAyudaNombre.theme_type_variation = &"TextoSecundario"
		%LblContador.theme_type_variation = &"TextoVerde"
		%TarjetaInfo.hide()
	else:
		%TxtNombre.theme_type_variation = &"EntradaError"
		%LblAyudaNombre.text = "El nombre debe tener entre 3 y 20 caracteres"
		%LblAyudaNombre.theme_type_variation = &"TextoNaranjaNormal"
		%LblContador.theme_type_variation = &"TextoNaranja"
		%TarjetaInfo.show()


func _guardar_nombre() -> void:
	if JuegoRepository.actualizar_nombre(%TxtNombre.text):
		cambios["nombre"] = true
		_mostrar_menu_perfil(true)
	else:
		_validar_nombre(%TxtNombre.text)


# ============================ FOTO ============================
func _abrir_foto() -> void:
	avatar_elegido = JuegoRepository.obtener_perfil().get("avatar_id", "avatar_01")
	_construir_catalogo_avatares()
	for b in %GridAvatares.get_children():
		var es: bool = b.get_node("Avatar").avatar_id == avatar_elegido
		b.set_pressed_no_signal(es)
		b.get_node("Check").visible = es
	_mostrar_panel(%PanelFoto)


## Catálogo de 14 avatares: los desbloqueados se pueden elegir; los bloqueados se ven en gris
## con un candado y la condición para conseguirlos (se desbloquean al avanzar en los temas).
func _construir_catalogo_avatares() -> void:
	for hijo in %GridAvatares.get_children():
		hijo.queue_free()
	var catalogo := JuegoRepository.obtener_catalogo_avatares()
	var disponibles := 0
	for a in catalogo:
		if a["disponible"]:
			disponibles += 1
		%GridAvatares.add_child(_crear_boton_avatar(a))
	%LblSub.text = "%d de %d avatares desbloqueados. Los demás se ganan avanzando en los temas." % [disponibles, catalogo.size()]


func _crear_boton_avatar(a: Dictionary) -> Button:
	var disponible: bool = a["disponible"]
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 196)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.theme_type_variation = &"BotonAvatar"
	b.toggle_mode = true
	b.disabled = not disponible
	b.button_group = grupo_avatares

	var av := Avatar.new()
	av.name = "Avatar"
	av.avatar_id = a["id"]
	av.bloqueado = not disponible
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.set_anchors_preset(Control.PRESET_CENTER_TOP)
	av.position = Vector2(0, 14)
	av.size = Vector2(104, 104)
	av.anchor_left = 0.5; av.anchor_right = 0.5
	av.offset_left = -52; av.offset_right = 52
	av.offset_top = 14; av.offset_bottom = 118
	b.add_child(av)

	var nombre := Label.new()
	nombre.name = "Nombre"
	nombre.text = a["nombre"]
	nombre.theme_type_variation = &"Negrita" if disponible else &"TextoSecundario"
	nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nombre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nombre.set_anchors_preset(Control.PRESET_TOP_WIDE)
	nombre.offset_top = 124; nombre.offset_bottom = 148
	b.add_child(nombre)

	var pie := Label.new()
	pie.name = "Pie"
	pie.theme_type_variation = &"Pequeno"
	pie.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pie.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pie.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pie.set_anchors_preset(Control.PRESET_TOP_WIDE)
	pie.offset_left = 6; pie.offset_right = -6
	pie.offset_top = 148; pie.offset_bottom = 192
	if disponible:
		pie.text = "" if int(a["meta"]) == 0 else "Desbloqueado"
	else:
		pie.text = "%s (%d/%d)" % [a["condicion"], int(a["progreso"]), int(a["meta"])]
	b.add_child(pie)

	var check := Control.new()
	check.name = "Check"
	check.set_script(icono_script)
	check.tipo = "check"
	check.color = Color("#2F55E6")
	check.grosor = 3.0
	check.visible = false
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check.position = Vector2(8, 8)
	check.size = Vector2(24, 24)
	b.add_child(check)

	if not disponible:
		var candado := Control.new()
		candado.set_script(icono_script)
		candado.tipo = "candado"
		candado.color = Color("#5B6178")
		candado.fondo = Color.WHITE
		candado.grosor = 2.0
		candado.mouse_filter = Control.MOUSE_FILTER_IGNORE
		candado.position = Vector2(0, 0)
		candado.size = Vector2(30, 30)
		candado.anchor_left = 0.5; candado.anchor_right = 0.5
		candado.offset_left = 24; candado.offset_right = 54
		candado.offset_top = 86; candado.offset_bottom = 116
		b.add_child(candado)

	b.toggled.connect(_on_avatar_toggled.bind(b))
	return b


func _on_avatar_toggled(activo: bool, b: Button) -> void:
	b.get_node("Check").visible = activo
	if activo:
		avatar_elegido = b.get_node("Avatar").avatar_id


func _guardar_avatar() -> void:
	if JuegoRepository.actualizar_avatar(avatar_elegido):
		cambios["foto"] = true
		_mostrar_menu_perfil(true)


# ============================ CONTRASEÑA ============================
func _abrir_contrasena() -> void:
	%TxtContra1.text = ""
	%TxtContra2.text = ""
	%TxtContra1.secret = true
	%TxtContra2.secret = true
	_validar_contrasena()
	%BtnQuitarContra.visible = JuegoRepository.tiene_contrasena()
	_mostrar_panel(%PanelContrasena)
	%TxtContra1.grab_focus()


func _validar_contrasena() -> void:
	var c1: String = %TxtContra1.text
	var c2: String = %TxtContra2.text
	var v1 := JuegoRepository.contrasena_valida(c1)
	var coinciden := c1 == c2

	if c1.is_empty():
		%LblAyudaContra.text = "4 a 8 dígitos"
		%LblAyudaContra.theme_type_variation = &"TextoSecundario"
		%TxtContra1.theme_type_variation = &""
	elif v1:
		%LblAyudaContra.text = "%d dígitos · válida" % c1.length()
		%LblAyudaContra.theme_type_variation = &"TextoVerdeNormal"
		%TxtContra1.theme_type_variation = &"EntradaOk"
	else:
		%LblAyudaContra.text = "Debe tener solo dígitos, de 4 a 8"
		%LblAyudaContra.theme_type_variation = &"TextoNaranjaNormal"
		%TxtContra1.theme_type_variation = &"EntradaError"

	var mostrar_error := not c2.is_empty() and not coinciden
	%LblErrorContra.visible = mostrar_error
	%TxtContra2.theme_type_variation = &"EntradaError" if mostrar_error else (&"EntradaOk" if (v1 and coinciden and not c2.is_empty()) else &"")
	%BtnGuardarContra.disabled = not (v1 and coinciden)


func _guardar_contrasena() -> void:
	if JuegoRepository.actualizar_contrasena(%TxtContra1.text, %TxtContra2.text):
		cambios["contrasena"] = true
		_mostrar_menu_perfil(true)
	else:
		_validar_contrasena()
