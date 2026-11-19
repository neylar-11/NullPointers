# res://test/unit/test_cu08_temas.gd
# Pruebas unitarias del CU-08 Elegir tema (RF-08)
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


# UT-08-01: catálogo de 12 temas sin iniciar
func test_catalogo_inicial_12_temas_sin_iniciar():
	var cat = repo.obtener_catalogo_temas()
	assert_eq(cat.size(), 12)
	for fila in cat:
		assert_true(fila["sin_iniciar"])
		assert_eq(fila["porcentaje"], 0)
		assert_eq(fila["modulos_totales"], 3)

# UT-08-02: avance de un tema = módulos completados / 3
func test_catalogo_calcula_porcentaje_de_avance():
	repo.registrar_intento(501, 5)
	var fila = repo.obtener_catalogo_temas()[4]
	assert_eq(fila["modulos_completados"], 1)
	assert_eq(fila["porcentaje"], 33)
	assert_false(fila["sin_iniciar"])

# UT-08-03: un tema intentado sin completar ya no está "Sin iniciar"
func test_tema_con_intento_fallado_ya_no_esta_sin_iniciar():
	repo.registrar_intento(601, 1)
	assert_false(repo.obtener_catalogo_temas()[5]["sin_iniciar"])

# UT-08-04: elegir un tema lo recuerda como "Continuar en…" (alt. 2)
func test_seleccionar_tema_lo_recuerda_como_ultimo():
	repo.seleccionar_tema(9)
	assert_eq(repo.tema_seleccionado, 9)
	assert_eq(int(repo.obtener_ultimo_tema()["id"]), 9)
	assert_true(repo.obtener_catalogo_temas()[8]["es_ultimo"])

# UT-08-05: el banco tiene 15 preguntas en los temas 1-8 y 10 en los temas 9-12 (160)
func test_banco_de_160_preguntas_por_tema():
	assert_eq(repo.bd["reactivos"].size(), 160)
	for t in range(1, 13):
		assert_eq(repo.obtener_reactivos_tema(t).size(), 15 if t <= 8 else 10, "Tema %d" % t)
