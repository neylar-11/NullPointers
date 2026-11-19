# res://test/unit/test_cu04_teoria.gd
# Pruebas unitarias del CU-04 Ver teoría (RF-04)
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


# UT-04-01: toda pregunta del banco tiene un concepto de su mismo tema
func test_cada_reactivo_tiene_concepto_de_su_tema():
	for r in repo.bd["reactivos"]:
		var c = repo.obtener_concepto(int(r["id"]))
		assert_false(c.is_empty(), "Reactivo %s sin concepto" % r["id"])
		if not c.is_empty():
			assert_eq(int(c["id_tema"]), int(r["id_tema"]))
			assert_ne(str(c["titulo"]), "")
			assert_ne(str(c["explicacion"]), "")

# UT-04-02: sin concepto asociado regresa vacío (CU-04 alt.)
func test_obtener_concepto_sin_concepto_devuelve_vacio():
	var r = repo.bd["reactivos"][0]
	r["id_concepto"] = ""
	assert_true(repo.obtener_concepto(int(r["id"])).is_empty())

# UT-04-03: consultar la teoría no altera puntos ni intentos (postcondición)
func test_registrar_consulta_teoria_no_altera_puntos_ni_intentos():
	repo.registrar_intento(101, 3)
	var puntos = repo.obtener_puntos_totales()
	var intentos = repo.bd["intentos_modulo"].size()
	repo.registrar_consulta_teoria()
	assert_eq(repo.obtener_puntos_totales(), puntos)
	assert_eq(repo.bd["intentos_modulo"].size(), intentos)
	assert_eq(int(repo.bd["teoria_consultas"]), 1)
