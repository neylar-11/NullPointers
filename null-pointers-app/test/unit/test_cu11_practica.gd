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
	DirAccess.remove_absolute("user://test_bd.json")

# Completa los módulos de una materia con 5/5 aciertos
func completar_materia(id_materia: int) -> void:
	for m in repo.obtener_modulos_materia(id_materia):
		repo.registrar_intento(int(m["id"]), 5)


# UT-11-01: la práctica no está disponible hasta completar todos los módulos (precondición)
func test_practica_bloqueada_hasta_completar_la_materia():
	assert_false(repo.practica_disponible(2))
	repo.registrar_intento(9, 5)
	repo.registrar_intento(10, 5)
	assert_false(repo.practica_disponible(2), "Falta el módulo 11")


# UT-11-02: completar el último módulo desbloquea la práctica (CU-11 paso 1)
func test_completar_materia_desbloquea_practica():
	repo.registrar_intento(9, 5)
	repo.registrar_intento(10, 5)
	var r = repo.registrar_intento(11, 5)
	assert_true(r["practica_desbloqueada"])
	assert_true(repo.practica_disponible(2))


# UT-11-03: 70 % o más aprueba y marca la materia como dominada (CU-11 paso 9)
func test_practica_con_70_domina_materia():
	completar_materia(2)
	var r = repo.registrar_intento_practica(2, 7, 10)
	assert_eq(r["porcentaje"], 70)
	assert_true(r["aprobada"])
	assert_true(r["recien_dominada"])
	assert_true(repo.materia_dominada(2))
	assert_eq(repo.materias_dominadas(), 1)
	assert_has(r["insignias_nuevas"].map(func(i): return i["id"]), "dominio")


# UT-11-04: menos de 70 % no aprueba ni suma puntos (CU-11 flujo alterno)
func test_practica_con_60_no_domina():
	completar_materia(2)
	var puntos_antes = repo.obtener_puntos_totales()
	var r = repo.registrar_intento_practica(2, 6, 10)
	assert_false(r["aprobada"])
	assert_false(repo.materia_dominada(2))
	assert_eq(repo.obtener_puntos_totales(), puntos_antes)
	assert_true(r["guardado"], "El intento reprobado sí se guarda")


# UT-11-05: rejugar una práctica dominada solo guarda si supera al mejor (CU-11 flujo alterno 4)
func test_rejugar_practica_dominada_sin_mejorar_no_se_guarda():
	completar_materia(2)
	repo.registrar_intento_practica(2, 9, 10)
	var puntos = repo.obtener_puntos_totales()
	var r = repo.registrar_intento_practica(2, 8, 10)
	assert_false(r["guardado"])
	assert_eq(r["intentos"], 1)
	assert_eq(repo.obtener_puntos_totales(), puntos, "Los puntos no bajan")
	r = repo.registrar_intento_practica(2, 10, 10)
	assert_true(r["guardado"])
	assert_eq(r["puntos_sumados"], 10, "Solo suma la mejora (90 → 100)")


# UT-11-06: una materia sin práctica regresa vacío
func test_registrar_practica_de_materia_inexistente():
	var r = repo.registrar_intento_practica(99, 5, 10)
	assert_true(r.is_empty())
	assert_push_error("no tiene práctica")
