# res://scenes/cu01_perfil/perfil.gd
# CU-01: Editar perfil (SRS 1.1). El perfil se crea automáticamente; aquí se
# cambia la foto (avatar del catálogo), el nombre de usuario (3-20 caracteres)
# y la contraseña (4-8 dígitos, doble confirmación).
extends Control

const RUTA_MENU := "res://scenes/menu/Menu.tscn"

var avatar_elegido := ""
var grupo_avatares := ButtonGroup.new()
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
	for b in %GridAvatares.get_children():
		b.button_group = grupo_avatares
		b.toggled.connect(_on_avatar_toggled.bind(b))

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

	_mostrar_menu_perfil(false)


# ============================ MI PERFIL ============================
func _mostrar_menu_perfil(actualizado: bool) -> void:
	var p := JuegoRepository.obtener_perfil()
	%AvatarGrande.avatar_id = p.get("avatar_id", "avatar_01")
	%LblAliasPerfil.text = p["alias"]
	%LblSubPerfil.text = "Contraseña configurada" if JuegoRepository.tiene_contrasena() else "Perfil creado automáticamente"

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
	for b in %GridAvatares.get_children():
		var es: bool = b.get_node("Avatar").avatar_id == avatar_elegido
		b.set_pressed_no_signal(es)
		b.get_node("Check").visible = es
	_mostrar_panel(%PanelFoto)


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
