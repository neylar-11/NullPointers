# res://test/unit/test_cu11_practica.gd
# Pruebas unitarias del CU-11 Resolver práctica de ingeniero (RF-11)
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


# UT-11-01: la práctica no está disponible hasta completar los 3 módulos (precondición)
func test_practica_bloqueada_hasta_completar_el_tema():
	assert_false(repo.practica_disponible(2))
	repo.registrar_intento(201, 5)
	repo.registrar_intento(202, 5)
	assert_false(repo.practica_disponible(2), "Falta el Puzzle")

# UT-11-02: completar el último módulo desbloquea la práctica (paso 1)
func test_completar_tema_desbloquea_practica():
	repo.registrar_intento(201, 5)
	repo.registrar_intento(202, 5)
	var n = int(repo.obtener_modulo(203)["num_preguntas"])
	var r = repo.registrar_intento(203, n, -1, 0, n)
	assert_true(r["practica_desbloqueada"])
	assert_true(repo.practica_disponible(2))

# UT-11-03: 70 % aprueba, domina el tema y da "Dominio" (paso 9)
func test_practica_con_70_domina_tema():
	completar_tema(2)
	var r = repo.registrar_intento_practica(2, 7, 10)
	assert_eq(r["porcentaje"], 70)
	assert_true(r["aprobada"])
	assert_true(r["recien_dominada"])
	assert_true(repo.tema_dominado(2))
	assert_has(r["insignias_nuevas"].map(func(i): return i["id"]), "dominio")

# UT-11-04: 60 % no aprueba ni suma puntos, pero sí se guarda (alt.)
func test_practica_con_60_no_domina():
	completar_tema(2)
	var puntos = repo.obtener_puntos_totales()
	var r = repo.registrar_intento_practica(2, 6, 10)
	assert_false(r["aprobada"])
	assert_false(repo.tema_dominado(2))
	assert_eq(repo.obtener_puntos_totales(), puntos)
	assert_true(r["guardado"])

# UT-11-05: rejugar una práctica dominada solo guarda si supera al mejor (alt. 4)
func test_rejugar_practica_dominada_sin_mejorar_no_se_guarda():
	completar_tema(2)
	repo.registrar_intento_practica(2, 9, 10)
	var puntos = repo.obtener_puntos_totales()
	var r = repo.registrar_intento_practica(2, 8, 10)
	assert_false(r["guardado"])
	assert_eq(repo.obtener_puntos_totales(), puntos)
	r = repo.registrar_intento_practica(2, 10, 10)
	assert_true(r["guardado"])
	assert_eq(r["puntos_sumados"], 10)

# UT-11-06: la práctica sortea 4 ejercicios; si el tema tiene menos, completa con lógica (tema 1)
func test_sortear_practica_completa_con_ejercicios_de_logica():
	assert_eq(repo.obtener_puzzles_tema(12).size(), 2)
	var lista = repo.sortear_practica(12)
	assert_eq(lista.size(), 4)
	assert_eq(lista.filter(func(e): return int(e["id_tema"]) == 1).size(), 2)

# UT-11-07: un tema sin práctica regresa vacío
func test_registrar_practica_de_tema_inexistente():
	assert_true(repo.registrar_intento_practica(99, 5, 10).is_empty())
	assert_push_error("no tiene práctica")
