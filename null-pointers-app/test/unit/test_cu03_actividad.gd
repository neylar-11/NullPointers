# res://test/unit/test_cu03_actividad.gd
# Pruebas unitarias del CU-03 Resolver actividad de aprendizaje (RF-03)
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


# UT-03-01: 80 % completa el módulo y desbloquea el siguiente del mismo tema
func test_registrar_intento_con_80_completa_y_desbloquea_siguiente():
	var r = repo.registrar_intento(101, 4)
	assert_eq(r["porcentaje"], 80)
	assert_true(r["completado"])
	assert_eq(repo.obtener_modulo(102)["estado"], "desbloqueado")
	assert_eq(repo.obtener_puntos_totales(), 80)

# UT-03-02: 60 % no completa
func test_registrar_intento_con_60_no_completa():
	var r = repo.registrar_intento(101, 3)
	assert_eq(r["porcentaje"], 60)
	assert_false(r["completado"])
	assert_eq(repo.obtener_modulo(102)["estado"], "bloqueado")

# UT-03-03: un intento peor conserva el mejor puntaje y los puntos (CU-03 alt. 2)
func test_registrar_intento_peor_conserva_mejor_puntaje():
	repo.registrar_intento(101, 5)
	repo.registrar_intento(101, 4)
	assert_eq(repo.obtener_puntos_totales(), 100)
	assert_eq(int(repo.obtener_modulo(101)["mejor_puntaje"]), 100)

# UT-03-04: al rejugar un módulo completado, el intento que no mejora no se guarda (CU-03 alt. 4)
# Detectó DEF-01 en el Sprint 2; corregido en el Sprint 3.
func test_registrar_intento_que_no_mejora_no_se_guarda():
	repo.registrar_intento(101, 5)
	var r = repo.registrar_intento(101, 4)
	assert_false(r["guardado"])
	assert_eq(repo.obtener_intentos(101).size(), 1)

# UT-03-08: rejugar un módulo completado y mejorar sí guarda el intento (CU-03 alt. 4)
func test_rejugar_y_mejorar_si_se_guarda():
	repo.registrar_intento(101, 4)
	var r = repo.registrar_intento(101, 5)
	assert_true(r["guardado"])
	assert_eq(repo.obtener_intentos(101).size(), 2)
	assert_eq(int(repo.obtener_modulo(101)["mejor_puntaje"]), 100)

# UT-03-09: un módulo no completado guarda todos sus intentos (la regla solo aplica al rejugar uno completado)
func test_modulo_no_completado_guarda_todos_los_intentos():
	repo.registrar_intento(101, 2)
	repo.registrar_intento(101, 1)
	assert_eq(repo.obtener_intentos(101).size(), 2)

# UT-03-05: cada quiz sortea 5 preguntas distintas del banco de su tema (RF-03)
func test_sortear_reactivos_toma_5_del_tema_sin_repetir():
	for i in 20:
		var lista = repo.sortear_reactivos(301)
		assert_eq(lista.size(), 5)
		var ids = {}
		for r in lista:
			assert_eq(int(r["id_tema"]), 3)
			ids[r["id"]] = true
		assert_eq(ids.size(), 5, "Sin preguntas repetidas en un intento")

# UT-03-06: el resultado trae el número de intentos que muestra la pantalla (regresión del PR #7)
func test_registrar_intento_regresa_el_numero_de_intentos():
	assert_eq(repo.registrar_intento(101, 2)["intentos"], 1)
	assert_eq(repo.registrar_intento(101, 5)["intentos"], 2)

# UT-03-07: completar un módulo de un tema no desbloquea módulos de otro (regla del CU-08)
func test_completar_modulo_no_afecta_otros_temas():
	completar_tema(2)
	assert_eq(repo.obtener_modulo(102)["estado"], "bloqueado")
	assert_eq(repo.obtener_modulo(302)["estado"], "bloqueado")
