# res://test/unit/test_cu06_progreso.gd
# Pruebas unitarias del CU-06 Ver progreso (RF-06)
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
	DirAccess.remove_absolute("user://test_bd.json")


# UT-06-01: sin intentos el progreso está vacío (CU-06 flujo alterno)
func test_obtener_progreso_sin_intentos_esta_vacio():
	var p = repo.obtener_progreso()
	assert_false(p["tiene_intentos"], "No debe haber intentos")
	assert_eq(p["puntuacion_total"], 0)
	assert_eq(p["dominados"].size(), 0, "Lista de dominados vacía")
	assert_eq(p["areas_mejora"].size(), 0, "Lista de áreas de mejora vacía")


# UT-06-02: clasifica módulos en dominados y áreas de mejora (RF-06)
func test_obtener_progreso_clasifica_dominados_y_areas_mejora():
	# Preparar
	repo.registrar_intento(1, 4)
	repo.registrar_intento(2, 3)
	# Ejecutar
	var p = repo.obtener_progreso()
	# Verificar
	assert_eq(p["dominados"].size(), 1)
	assert_eq(p["dominados"][0]["id"], 1, "El módulo 1 (80 %) debe estar en dominados")
	assert_eq(p["areas_mejora"].size(), 1)
	assert_eq(p["areas_mejora"][0]["id"], 2, "El módulo 2 (60 %) debe estar en áreas de mejora")
	assert_eq(p["modulos_completados"], 1)
	assert_eq(p["modulos_totales"], 14, "14 módulos en las 3 materias (Sprint 3)")
