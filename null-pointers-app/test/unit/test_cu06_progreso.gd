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
	for sufijo in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_bd.json" + sufijo))

# Completa con 100 % todos los módulos de un tema
func completar_tema(id_tema: int) -> void:
	for m in repo.obtener_modulos_tema(id_tema):
		repo.registrar_intento(int(m["id"]), int(m["num_preguntas"]), -1, 0, int(m["num_preguntas"]))


# UT-06-01: sin intentos, todo vacío (CU-06 alt.)
func test_obtener_progreso_sin_intentos_esta_vacio():
	var p = repo.obtener_progreso()
	assert_false(p["tiene_intentos"])
	assert_eq(p["puntuacion_total"], 0)
	assert_eq(p["dominados"].size(), 0)
	assert_eq(p["areas_mejora"].size(), 0)

# UT-06-02: clasifica dominados (≥ 70 %) y áreas de mejora (< 70 %)
func test_obtener_progreso_clasifica_dominados_y_areas_mejora():
	repo.registrar_intento(101, 4)
	repo.registrar_intento(201, 3)
	var p = repo.obtener_progreso()
	assert_eq(p["dominados"].map(func(f): return f["id"]), [101])
	assert_eq(p["areas_mejora"].map(func(f): return f["id"]), [201])
	assert_eq(p["modulos_completados"], 1)
	assert_eq(p["modulos_totales"], 36)

# UT-06-03 (Sprint 3): muestra temas dominados y preguntas pendientes de repaso
func test_obtener_progreso_incluye_temas_dominados_y_errores():
	completar_tema(1)
	repo.registrar_intento_practica(1, 10, 10)
	repo.registrar_error(int(repo.obtener_reactivos_tema(2)[0]["id"]))
	var p = repo.obtener_progreso()
	assert_eq(p["temas_dominados"], 1)
	assert_eq(p["temas_totales"], 12)
	assert_eq(p["errores_pendientes"], 1)
