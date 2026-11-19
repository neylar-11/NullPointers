# res://test/unit/test_persistencia.gd
# Pruebas de RNF-02 (no perder progreso) y de la migración de versiones anteriores
extends GutTest

const Repo = preload("res://autoload/JuegoRepository.gd")
var repo

# Preparar: repositorio nuevo, con su propia base de datos de prueba
func before_each():
	repo = Repo.new()
	repo.ruta_bd = "user://test_bd.json"
	repo.bd = repo._bd_inicial()

func after_each():
	repo.free()
	for sufijo in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_bd.json" + sufijo))

# Completa con 100 % todos los módulos de un tema
func completar_tema(id_tema: int) -> void:
	for m in repo.obtener_modulos_tema(id_tema):
		repo.registrar_intento(int(m["id"]), int(m["num_preguntas"]), -1, 0, int(m["num_preguntas"]))


# UT-RNF02-01: guardar y volver a cargar conserva el progreso
func test_guardar_y_cargar_conserva_progreso():
	repo.registrar_intento(101, 5)
	var otro = Repo.new()
	otro.ruta_bd = "user://test_bd.json"
	otro.cargar_bd()
	assert_eq(otro.obtener_puntos_totales(), 100)
	assert_eq(otro.obtener_modulo(101)["estado"], "completado")
	otro.free()

# UT-RNF02-02: si el archivo principal se daña, se recupera el respaldo en vez de perder todo
func test_archivo_danado_se_recupera_del_respaldo():
	repo.registrar_intento(101, 5)
	repo.registrar_intento(201, 5)
	var f = FileAccess.open("user://test_bd.json", FileAccess.WRITE)
	f.store_string("{\"modulos\": [ {\"id\": 1, ")
	f.close()
	var otro = Repo.new()
	otro.ruta_bd = "user://test_bd.json"
	otro.cargar_bd()
	assert_engine_error("Parse JSON failed")       # el error de lectura del archivo dañado es esperado
	assert_push_warning("se recuperó la copia de respaldo")
	assert_eq(otro.obtener_puntos_totales(), 100, "Se recupera el último guardado bueno")
	assert_eq(otro.obtener_modulo(101)["estado"], "completado")
	otro.free()

# UT-RNF02-03: un archivo del Sprint 2 (8 módulos) migra al esquema por temas sin perder perfil ni puntos
func test_migracion_desde_sprint_2():
	var vieja = {"modulos": [], "intentos_modulo": [], "insignias": [{"id": "primer_paso", "obtenida": true, "fecha": "x"}],
		"perfil_jugador": {"alias": "viejo", "avatar_id": "avatar_02", "contrasena": "1234", "puntos_totales": 180, "fecha_creacion": "x"}}
	for i in range(1, 9):
		vieja["modulos"].append({"id": i, "estado": "completado" if i <= 2 else "bloqueado", "mejor_puntaje": 90 if i <= 2 else -1, "puntos_obtenidos": 90 if i <= 2 else 0})
	var nueva = repo._migrar_a_temas(vieja)
	assert_eq(nueva["perfil_jugador"]["alias"], "viejo")
	assert_eq(int(nueva["perfil_jugador"]["puntos_totales"]), 180)
	assert_eq(repo.obtener_modulo_en(nueva, 101)["estado"], "completado")
	assert_eq(repo.obtener_modulo_en(nueva, 102)["estado"], "desbloqueado")
	for t in range(3, 9):
		assert_eq(repo.obtener_modulo_en(nueva, t * 100 + 1)["estado"], "desbloqueado", "El Quiz I del tema %d no debe quedar bloqueado" % t)
