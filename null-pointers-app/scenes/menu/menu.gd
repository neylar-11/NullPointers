# res://scenes/menu/menu.gd
# Menú principal (mockup "Hola de nuevo"). Conecta las pantallas de los CU.
extends Control

const RUTA_PERFIL    := "res://scenes/cu01_perfil/Perfil.tscn"         # CU-01
const RUTA_MATERIAS  := "res://scenes/cu08_materias/Materias.tscn"     # CU-08 (antes abría el mapa directo)
const RUTA_MAPA      := "res://scenes/cu02_mapa/Mapa.tscn"             # CU-02
const RUTA_INSIGNIAS := "res://scenes/cu05_insignias/Insignias.tscn"   # CU-05
const RUTA_PROGRESO  := "res://scenes/cu06_progreso/Progreso.tscn"     # CU-06
const RUTA_REPASO    := "res://scenes/cu09_repaso/Repaso.tscn"         # CU-09
# CU-04 (teoría) no tiene entrada en el menú: solo se abre desde una respuesta incorrecta (CU-03).
# CU-10 (pista) vive dentro del reto (CU-03) y CU-11 (práctica) al final de cada mapa (CU-02).


func _ready() -> void:
	%BtnAvatar.pressed.connect(func(): _ir_a(RUTA_PERFIL))
	%BtnJugar.pressed.connect(_on_jugar)
	%BtnProgreso.pressed.connect(func(): _ir_a(RUTA_PROGRESO))
	%BtnInsignias.pressed.connect(func(): _ir_a(RUTA_INSIGNIAS))
	%BtnRepaso.pressed.connect(func(): _ir_a(RUTA_REPASO))
	_actualizar_datos()


## CU-08 paso 1: "Jugar" abre el catálogo de materias; si no existe, el mapa.
func _on_jugar() -> void:
	if ResourceLoader.exists(RUTA_MATERIAS):
		_ir_a(RUTA_MATERIAS)
	else:
		_ir_a(RUTA_MAPA)


## Llena los textos del menú con lo que hay en la base de datos local.
func _actualizar_datos() -> void:
	var perfil := JuegoRepository.obtener_perfil()
	%LblAlias.text = perfil["alias"]
	%Avatar.avatar_id = perfil.get("avatar_id", "avatar_01")
	%LblPuntos.text = "%d pts" % JuegoRepository.obtener_puntos_totales()

	# CU-08: se sugiere continuar en la última materia visitada
	var materia := JuegoRepository.obtener_ultima_materia()
	var siguiente := JuegoRepository.siguiente_modulo_materia(int(materia.get("id", 1)))
	if siguiente.is_empty():
		siguiente = JuegoRepository.siguiente_modulo()
	if siguiente.is_empty():
		%LblJugarSub.text = "Elige una materia · ¡Completaste todos los módulos!"
	else:
		var mat_sig := JuegoRepository.obtener_materia(int(siguiente.get("id_materia", 1)))
		%LblJugarSub.text = "Elige una materia · Siguiente: %s · %s" % [
			mat_sig.get("corto", ""), siguiente["nombre"]]

	var total_modulos: int = JuegoRepository.obtener_modulos().size()
	var dominadas := JuegoRepository.materias_dominadas()
	var sub := "%d de %d módulos completados" % [JuegoRepository.modulos_completados(), total_modulos]
	if dominadas > 0:
		sub += " · %d materia%s dominada%s" % [dominadas, "" if dominadas == 1 else "s", "" if dominadas == 1 else "s"]
	%LblProgresoSub.text = sub

	%LblInsigniasSub.text = "%d de %d obtenidas" % [
		JuegoRepository.insignias_obtenidas(), JuegoRepository.obtener_insignias().size()]

	# CU-09: cuántas preguntas falladas esperan repaso
	var errores := JuegoRepository.obtener_errores_pendientes().size()
	if errores == 0:
		%LblRepasoSub.text = "No tienes errores por repasar"
	else:
		%LblRepasoSub.text = "%d pregunta%s por repasar" % [errores, "" if errores == 1 else "s"]


## Cambia de pantalla; si la escena aún no existe, solo avisa en consola.
func _ir_a(ruta: String) -> void:
	if ResourceLoader.exists(ruta):
		get_tree().change_scene_to_file(ruta)
	else:
		print("Pantalla pendiente: ", ruta)
