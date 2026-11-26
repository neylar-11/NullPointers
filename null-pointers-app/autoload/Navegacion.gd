# res://autoload/Navegacion.gd
# Botón "Atrás" de Android. Godot, por defecto, cierra la app al recibir el
# aviso del sistema (NOTIFICATION_WM_GO_BACK_REQUEST). Aquí se desactiva eso
# (application/config/quit_on_go_back = false en project.godot) y se delega a
# la pantalla actual: si tiene un método atras(), hace lo mismo que su botón
# "volver"; si no, regresa al menú principal.
extends Node

const RUTA_MENU := "res://scenes/menu/Menu.tscn"
const RUTA_SESION := "res://scenes/cu12_sesion/Sesion.tscn"


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		atras()


## También se puede llamar desde cualquier pantalla (por ejemplo, con la tecla Escape en PC).
func atras() -> void:
	var escena := get_tree().current_scene
	if escena == null:
		return
	if escena.has_method("atras"):
		escena.call("atras")
	elif ResourceLoader.exists(RUTA_MENU):
		get_tree().change_scene_to_file(RUTA_MENU if JuegoRepository.sesion_activa() else RUTA_SESION)


## En PC, la tecla Escape imita el botón Atrás para poder probarlo.
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
		atras()
		get_viewport().set_input_as_handled()
