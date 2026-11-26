# res://scenes/menu/menu.gd
# Menú principal (mockup "Hola de nuevo"). Conecta las pantallas de los CU.
extends Control

const RUTA_PERFIL    := "res://scenes/cu01_perfil/Perfil.tscn"         # CU-01
const RUTA_TEMAS     := "res://scenes/cu08_temas/Temas.tscn"           # CU-08 (antes abría el mapa directo)
const RUTA_MAPA      := "res://scenes/cu02_mapa/Mapa.tscn"             # CU-02
const RUTA_INSIGNIAS := "res://scenes/cu05_insignias/Insignias.tscn"   # CU-05
const RUTA_PROGRESO  := "res://scenes/cu06_progreso/Progreso.tscn"     # CU-06
const RUTA_REPASO    := "res://scenes/cu09_repaso/Repaso.tscn"         # CU-09
const RUTA_CONFIG    := "res://scenes/cu07_config/Configuracion.tscn"  # CU-07
const RUTA_SESION    := "res://scenes/cu12_sesion/Sesion.tscn"         # CU-12
# CU-04 (teoría) no tiene entrada en el menú: solo se abre desde una respuesta incorrecta (CU-03).
# CU-10 (pista) vive dentro del reto (CU-03) y CU-11 (práctica) al final de cada mapa (CU-02).


func _ready() -> void:
	if not JuegoRepository.sesion_activa():      # CU-12: sin perfil abierto no hay menú
		_ir_a(RUTA_SESION)
		return
	%BtnAvatar.pressed.connect(func(): _ir_a(RUTA_PERFIL))
	%BtnConfig.pressed.connect(func(): _ir_a(RUTA_CONFIG))
	%BtnJugar.pressed.connect(_on_jugar)
	%BtnProgreso.pressed.connect(func(): _ir_a(RUTA_PROGRESO))
	%BtnInsignias.pressed.connect(func(): _ir_a(RUTA_INSIGNIAS))
	%BtnRepaso.pressed.connect(func(): _ir_a(RUTA_REPASO))
	_actualizar_datos()


## CU-08 paso 1: "Jugar" abre el catálogo de temas; si no existe, el mapa.
func _on_jugar() -> void:
	if ResourceLoader.exists(RUTA_TEMAS):
		_ir_a(RUTA_TEMAS)
	else:
		_ir_a(RUTA_MAPA)


## Llena los textos del menú con lo que hay en la base de datos local.
func _actualizar_datos() -> void:
	var perfil := JuegoRepository.obtener_perfil()
	%LblAlias.text = perfil["alias"]
	%Avatar.avatar_id = perfil.get("avatar_id", "avatar_01")
	%LblPuntos.text = "%d pts" % JuegoRepository.obtener_puntos_totales()

	# CU-08: se sugiere continuar en el último tema visitado
	var tema := JuegoRepository.obtener_ultimo_tema()
	var siguiente := JuegoRepository.siguiente_modulo_tema(int(tema.get("id", 1)))
	if siguiente.is_empty():
		siguiente = JuegoRepository.siguiente_modulo()
	if siguiente.is_empty():
		%LblJugarSub.text = "Elige un tema · ¡Completaste todos los módulos!"
	else:
		var tema_sig := JuegoRepository.obtener_tema(int(siguiente.get("id_tema", 1)))
		%LblJugarSub.text = "Elige un tema · Siguiente: %s · %s" % [
			tema_sig.get("corto", ""), siguiente["nombre"]]

	var total_modulos: int = JuegoRepository.obtener_modulos().size()
	var dominados := JuegoRepository.temas_dominados()
	var sub := "%d de %d módulos completados" % [JuegoRepository.modulos_completados(), total_modulos]
	if dominados > 0:
		sub += " · %d tema%s dominado%s" % [dominados, "" if dominados == 1 else "s", "" if dominados == 1 else "s"]
	%LblProgresoSub.text = sub

	%LblInsigniasSub.text = "%d de %d obtenidas" % [
		JuegoRepository.insignias_obtenidas(), JuegoRepository.obtener_insignias().size()]

	# CU-09: cuántas preguntas falladas esperan repaso
	var errores := JuegoRepository.obtener_errores_pendientes().size()
	if errores == 0:
		%LblRepasoSub.text = "No tienes errores por repasar"
	else:
		%LblRepasoSub.text = "%d pregunta%s por repasar" % [errores, "" if errores == 1 else "s"]


## Botón Atrás de Android (Navegacion): el menú es la pantalla raíz, así que cierra la app.
func atras() -> void:
	get_tree().quit()


## Cambia de pantalla; si la escena aún no existe, solo avisa en consola.
func _ir_a(ruta: String) -> void:
	if ResourceLoader.exists(ruta):
		get_tree().change_scene_to_file(ruta)
	else:
		print("Pantalla pendiente: ", ruta)
