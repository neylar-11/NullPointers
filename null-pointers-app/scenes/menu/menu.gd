# res://scenes/menu/menu.gd
# Menú principal (mockup "Hola de nuevo"). Conecta las pantallas de los CU.
extends Control

const RUTA_PERFIL   := "res://scenes/cu01_perfil/Perfil.tscn"       # CU-01
const RUTA_MAPA     := "res://scenes/cu02_mapa/Mapa.tscn"           # CU-02
const RUTA_PROGRESO := "res://scenes/cu06_progreso/Progreso.tscn"   # CU-06 (Sprint 2)
const RUTA_TEORIA   := "res://scenes/cu04_teoria/Teoria.tscn"       # CU-04 (Sprint 2)

const TOTAL_MODULOS := 8


func _ready() -> void:
	%BtnAvatar.pressed.connect(func(): _ir_a(RUTA_PERFIL))
	%BtnJugar.pressed.connect(func(): _ir_a(RUTA_MAPA))
	%BtnProgreso.pressed.connect(func(): _ir_a(RUTA_PROGRESO))
	%BtnTeoria.pressed.connect(func(): _ir_a(RUTA_TEORIA))
	_actualizar_datos()


## Llena los textos del menú con lo que hay en la base de datos local.
func _actualizar_datos() -> void:
	var perfil := JuegoRepository.obtener_perfil()
	%LblAlias.text = perfil["alias"]
	%Avatar.avatar_id = perfil.get("avatar_id", "avatar_01")
	%LblPuntos.text = "%d pts" % JuegoRepository.obtener_puntos_totales()

	var siguiente := JuegoRepository.siguiente_modulo()
	if siguiente.is_empty():
		%LblJugarSub.text = "Mapa de módulos · ¡Completaste todos los módulos!"
	else:
		%LblJugarSub.text = "Mapa de módulos · Siguiente: Módulo %d · %s" % [
			int(siguiente["id"]), siguiente["nombre"]]

	%LblProgresoSub.text = "%d de %d módulos completados" % [
		JuegoRepository.modulos_completados(), TOTAL_MODULOS]


## Cambia de pantalla; si la escena aún no existe, solo avisa en consola.
func _ir_a(ruta: String) -> void:
	if ResourceLoader.exists(ruta):
		get_tree().change_scene_to_file(ruta)
	else:
		print("Pantalla pendiente: ", ruta)
