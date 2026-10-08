# res://scenes/cu01_perfil/perfil.gd
# CU-01: Gestionar perfil de jugador (crear o editar alias).
#
# Flujo normal del SRS:
#   1. Alumno elige crear/editar perfil   → llega a esta pantalla
#   2. Sistema muestra campo de texto      → TxtAlias
#   3. Alumno escribe alias y confirma     → BtnGuardar (o Enter)
#   4. Sistema valida que no esté vacío y guarda el registro local
extends Control

const RUTA_MENU := "res://scenes/menu/Menu.tscn"

var editando := false     # true = ya había perfil, solo se cambia el alias


func _ready() -> void:
	editando = JuegoRepository.existe_perfil()

	if editando:
		%LblTitulo.text = "Edita tu perfil"
		%LblDescripcion.text = "Cambia tu alias. Tus puntos y progreso se conservan."
		%TxtAlias.text = JuegoRepository.obtener_perfil()["alias"]
	else:
		%LblTitulo.text = "Crea tu perfil"
		%LblDescripcion.text = "Elige un alias para guardar tu progreso en este dispositivo."

	%BtnCancelar.visible = editando        # sin perfil no hay a dónde cancelar

	%BtnGuardar.pressed.connect(_on_guardar)
	%TxtAlias.text_submitted.connect(func(_texto): _on_guardar())
	%TxtAlias.text_changed.connect(func(_texto): %LblError.hide())
	%BtnCancelar.pressed.connect(_ir_al_menu)

	%TxtAlias.grab_focus()


func _on_guardar() -> void:
	var alias: String = %TxtAlias.text.strip_edges()

	var ok: bool
	if editando:
		ok = JuegoRepository.actualizar_nombre(alias)
	else:
		ok = JuegoRepository.crear_perfil(alias)

	if not ok:
		%LblError.text = "El alias no puede estar vacío."
		%LblError.show()
		%TxtAlias.grab_focus()
		return

	_ir_al_menu()


func _ir_al_menu() -> void:
	get_tree().change_scene_to_file(RUTA_MENU)
