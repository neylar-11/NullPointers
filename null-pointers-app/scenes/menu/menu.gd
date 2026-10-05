# res://scenes/menu/menu.gd
# Menú principal (mockup "Hola de nuevo"). Conecta las pantallas de los tres CU.
extends Control

# Rutas de las pantallas de cada compañero. Cuando creen su escena con este
# nombre exacto, el botón empieza a funcionar solo.
const RUTA_PERFIL   := "res://scenes/cu01_perfil/Perfil.tscn"       # Gibran  (CU-01)
const RUTA_MAPA     := "res://scenes/cu02_mapa/Mapa.tscn"           # Francisco (CU-02)
const RUTA_PROGRESO := "res://scenes/cu06_progreso/Progreso.tscn"   # CU-06 (después)
const RUTA_TEORIA   := "res://scenes/cu04_teoria/Teoria.tscn"       # CU-04 (después)

const TOTAL_MODULOS := 8


func _ready() -> void:
	# Conectar los botones por código (más claro que hacerlo desde el editor)
	%BtnAvatar.pressed.connect(func(): _ir_a(RUTA_PERFIL))
	%BtnJugar.pressed.connect(func(): _ir_a(RUTA_MAPA))
	%BtnProgreso.pressed.connect(func(): _ir_a(RUTA_PROGRESO))
	%BtnTeoria.pressed.connect(func(): _ir_a(RUTA_TEORIA))

	# Si todavía no hay perfil, mandar directo a crearlo (CU-01)
	if not JuegoRepository.existe_perfil():
		if ResourceLoader.exists(RUTA_PERFIL):
			get_tree().change_scene_to_file(RUTA_PERFIL)
			return
		# Mientras Gibran termina su pantalla, mostramos un perfil provisional
		JuegoRepository.crear_perfil("estudiante_7421")

	_actualizar_datos()


## Llena los textos del menú con lo que hay en la base de datos local.
func _actualizar_datos() -> void:
	var perfil := JuegoRepository.obtener_perfil()
	%LblAlias.text = perfil["alias"]
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
