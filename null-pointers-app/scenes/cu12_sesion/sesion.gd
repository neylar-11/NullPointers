# res://scenes/cu12_sesion/sesion.gd
# CU-12: Iniciar sesión / elegir perfil. Varios estudiantes pueden usar el mismo
# teléfono: cada perfil tiene su archivo de progreso. Un perfil con contraseña
# pide sus 4-8 dígitos para entrar (y para eliminarlo). Desde aquí también se
# crea un perfil nuevo (alias de 3 a 20 caracteres, contraseña opcional).
extends Control

const RUTA_MENU := "res://scenes/menu/Menu.tscn"

var icono_script := preload("res://assets/ui/Icono.gd")
var perfil_pendiente: Dictionary = {}     # perfil al que se intenta entrar / eliminar


func _ready() -> void:
	%BtnNuevo.pressed.connect(_abrir_nuevo)
	# Contraseña para entrar
	%BtnEntrar.pressed.connect(_entrar_con_contrasena)
	%TxtContra.text_submitted.connect(func(_t): _entrar_con_contrasena())
	%TxtContra.text_changed.connect(func(_t): %LblContraError.hide())
	%BtnOjo.pressed.connect(func(): %TxtContra.secret = not %TxtContra.secret)
	%BtnCancelarContra.pressed.connect(%PanelContrasena.hide)
	# Perfil nuevo
	%TxtNombre.text_changed.connect(func(_t): _validar_nuevo())
	%TxtNueva1.text_changed.connect(func(_t): _validar_nuevo())
	%TxtNueva2.text_changed.connect(func(_t): _validar_nuevo())
	%TxtNueva2.text_submitted.connect(func(_t): _crear())
	%BtnCrear.pressed.connect(_crear)
	%BtnCancelarNuevo.pressed.connect(%PanelNuevo.hide)
	# Eliminar
	%BtnEliminar.pressed.connect(_eliminar)
	%TxtEliminarContra.text_changed.connect(func(_t): %LblEliminarError.hide())
	%BtnCancelarEliminar.pressed.connect(%PanelEliminar.hide)
	_construir_lista()


# ============================ LISTA DE PERFILES ============================
func _construir_lista() -> void:
	for h in %Lista.get_children():
		h.queue_free()
	var perfiles := JuegoRepository.obtener_perfiles()
	for p in perfiles:
		%Lista.add_child(_crear_fila(p))
	if perfiles.size() == 1:
		%LblSub.text = "Toca tu perfil para entrar. Si alguien más usa este teléfono, puede crear el suyo."
	else:
		%LblSub.text = "Hay %d perfiles en este teléfono. Toca el tuyo para entrar." % perfiles.size()


func _crear_fila(p: Dictionary) -> Control:
	var tarjeta := PanelContainer.new()
	tarjeta.theme_type_variation = &"TarjetaBoton"
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 14)
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tarjeta.add_child(fila)

	var av := Avatar.new()
	av.avatar_id = str(p.get("avatar_id", "avatar_01"))
	av.custom_minimum_size = Vector2(64, 64)
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fila.add_child(av)

	var textos := VBoxContainer.new()
	textos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	textos.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	textos.add_theme_constant_override("separation", 2)
	textos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(textos)
	var alias := Label.new()
	alias.text = str(p["alias"])
	alias.theme_type_variation = &"TituloTarjeta"
	alias.mouse_filter = Control.MOUSE_FILTER_IGNORE
	textos.add_child(alias)
	var sub := Label.new()
	var con_contra := bool(p.get("con_contrasena", false))
	var ultimo := str(p.get("ultimo_acceso", ""))
	sub.text = ("Con contraseña" if con_contra else "Sin contraseña") + (" · último acceso " + ultimo.substr(0, 10) if ultimo != "" else "")
	sub.theme_type_variation = &"TextoSecundario"
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	textos.add_child(sub)

	if con_contra:
		var candado := Control.new()
		candado.set_script(icono_script)
		candado.tipo = "candado"
		candado.color = Color("#5B6178")
		candado.grosor = 2.0
		candado.custom_minimum_size = Vector2(22, 22)
		candado.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		candado.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fila.add_child(candado)

	# Botón invisible que cubre la tarjeta: entrar
	var btn := Button.new()
	btn.theme_type_variation = &"BotonInvisible"
	btn.pressed.connect(_on_perfil.bind(p))
	tarjeta.add_child(btn)

	# Botón de eliminar (pequeño, a la derecha)
	var borrar := Button.new()
	borrar.theme_type_variation = &"BotonCircular"
	borrar.custom_minimum_size = Vector2(52, 52)
	borrar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	borrar.tooltip_text = "Eliminar perfil"
	var ib := Control.new()
	ib.set_script(icono_script)
	ib.tipo = "basura"
	ib.color = Color("#C2410C")
	ib.grosor = 2.0
	ib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ib.set_anchors_preset(Control.PRESET_CENTER)
	ib.offset_left = -11; ib.offset_right = 11; ib.offset_top = -11; ib.offset_bottom = 11
	borrar.add_child(ib)
	borrar.pressed.connect(_abrir_eliminar.bind(p))
	fila.add_child(borrar)
	return tarjeta


# ============================ ENTRAR ============================
func _on_perfil(p: Dictionary) -> void:
	perfil_pendiente = p
	if bool(p.get("con_contrasena", false)):
		%LblContraSub.text = "El perfil %s está protegido." % p["alias"]
		%TxtContra.text = ""
		%TxtContra.secret = true
		%LblContraError.hide()
		%PanelContrasena.show()
		%TxtContra.grab_focus()
	elif JuegoRepository.iniciar_sesion(str(p["id"])):
		_ir_al_menu()


func _entrar_con_contrasena() -> void:
	if JuegoRepository.iniciar_sesion(str(perfil_pendiente["id"]), %TxtContra.text):
		%PanelContrasena.hide()
		_ir_al_menu()
	else:
		%LblContraError.show()
		%TxtContra.text = ""
		%TxtContra.grab_focus()


# ============================ PERFIL NUEVO ============================
func _abrir_nuevo() -> void:
	%TxtNombre.text = ""
	%TxtNueva1.text = ""
	%TxtNueva2.text = ""
	_validar_nuevo()
	%PanelNuevo.show()
	%TxtNombre.grab_focus()


func _validar_nuevo() -> void:
	var alias: String = %TxtNombre.text
	var c1: String = %TxtNueva1.text
	var c2: String = %TxtNueva2.text
	var alias_ok := JuegoRepository.alias_valido(alias)
	var repetido := false
	for p in JuegoRepository.obtener_perfiles():
		if str(p["alias"]).to_lower() == alias.strip_edges().to_lower():
			repetido = true
	if alias.strip_edges().is_empty():
		%LblNombreAyuda.text = "Entre 3 y 20 caracteres"
		%LblNombreAyuda.theme_type_variation = &"TextoSecundario"
		%TxtNombre.theme_type_variation = &""
	elif repetido:
		%LblNombreAyuda.text = "Ya existe un perfil con ese nombre"
		%LblNombreAyuda.theme_type_variation = &"TextoNaranjaNormal"
		%TxtNombre.theme_type_variation = &"EntradaError"
	elif alias_ok:
		%LblNombreAyuda.text = "%d / 20" % alias.strip_edges().length()
		%LblNombreAyuda.theme_type_variation = &"TextoVerdeNormal"
		%TxtNombre.theme_type_variation = &"EntradaOk"
	else:
		%LblNombreAyuda.text = "El nombre debe tener entre 3 y 20 caracteres"
		%LblNombreAyuda.theme_type_variation = &"TextoNaranjaNormal"
		%TxtNombre.theme_type_variation = &"EntradaError"

	var contra_ok := c1.is_empty() and c2.is_empty()
	if c1.is_empty() and c2.is_empty():
		%LblNuevaAyuda.text = "Si pones contraseña, se pedirá cada vez que entres a este perfil."
		%LblNuevaAyuda.theme_type_variation = &"TextoSecundario"
	elif not JuegoRepository.contrasena_valida(c1):
		%LblNuevaAyuda.text = "La contraseña debe tener solo dígitos, de 4 a 8"
		%LblNuevaAyuda.theme_type_variation = &"TextoNaranjaNormal"
	elif c1 != c2:
		%LblNuevaAyuda.text = "Las contraseñas no coinciden"
		%LblNuevaAyuda.theme_type_variation = &"TextoNaranjaNormal"
	else:
		%LblNuevaAyuda.text = "Contraseña válida. ¡No la olvides!"
		%LblNuevaAyuda.theme_type_variation = &"TextoVerdeNormal"
		contra_ok = true
	%BtnCrear.disabled = not (alias_ok and not repetido and contra_ok)


func _crear() -> void:
	if %BtnCrear.disabled:
		return
	var e := JuegoRepository.crear_perfil_nuevo(%TxtNombre.text, %TxtNueva1.text)
	if not e.is_empty():
		%PanelNuevo.hide()
		_ir_al_menu()
	else:
		_validar_nuevo()


# ============================ ELIMINAR ============================
func _abrir_eliminar(p: Dictionary) -> void:
	perfil_pendiente = p
	%LblEliminarTitulo.text = "¿Eliminar el perfil %s?" % p["alias"]
	%TxtEliminarContra.visible = bool(p.get("con_contrasena", false))
	%TxtEliminarContra.text = ""
	%LblEliminarError.hide()
	%PanelEliminar.show()


func _eliminar() -> void:
	var id := str(perfil_pendiente["id"])
	if bool(perfil_pendiente.get("con_contrasena", false)):
		# La contraseña se comprueba intentando iniciar sesión sin quedarse en ella
		if not JuegoRepository.iniciar_sesion(id, %TxtEliminarContra.text):
			%LblEliminarError.show()
			return
		JuegoRepository.cerrar_sesion()
	JuegoRepository.eliminar_perfil(id)
	%PanelEliminar.hide()
	_construir_lista()


# ============================ NAVEGACIÓN ============================
## Botón Atrás de Android: cierra el panel abierto; si no hay ninguno, cierra la app
## (esta es la pantalla raíz mientras no hay sesión).
func atras() -> void:
	for p in [%PanelContrasena, %PanelNuevo, %PanelEliminar]:
		if p.visible:
			p.hide()
			return
	get_tree().quit()


func _ir_al_menu() -> void:
	get_tree().change_scene_to_file(RUTA_MENU)
