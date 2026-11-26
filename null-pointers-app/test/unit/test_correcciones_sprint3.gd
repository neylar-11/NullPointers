# res://test/unit/test_correcciones_sprint3.gd
# Pruebas de las correcciones reportadas en las pruebas en teléfono (26/11/2026):
#   DEF-07 preguntas repetidas entre Quiz I y Quiz II y entre intentos
#   DEF-08 "Ver teoría" abría un concepto que parecía de otro ejercicio
#   DEF-10 (datos) errores de Quiz II y de módulos ya completados siguen entrando al repaso
extends GutTest

const Repo = preload("res://autoload/JuegoRepository.gd")
var repo

func before_each():
	repo = Repo.new()
	repo.ruta_bd = "user://test_bd.json"
	repo.bd = repo._bd_inicial()

func after_each():
	repo.free()
	for sufijo in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_bd.json" + sufijo))


func quizzes(id_tema: int) -> Array:
	var lista: Array = []
	for m in repo.obtener_modulos_tema(id_tema):
		if m["tipo"] == "quiz":
			lista.append(int(m["id"]))
	return lista

func ids(reactivos: Array) -> Array:
	var r: Array = []
	for x in reactivos:
		r.append(int(x["id"]))
	return r


# UT-S3-01: todos los temas tienen banco suficiente para dos quizzes de 5 sin compartir preguntas
func test_banco_de_cada_quiz_alcanza_para_cinco():
	for t in repo.obtener_temas():
		for id_q in quizzes(int(t["id"])):
			assert_true(repo.banco_modulo(id_q).size() >= repo.PREGUNTAS_POR_QUIZ,
				"Tema %d módulo %d: banco de %d" % [int(t["id"]), id_q, repo.banco_modulo(id_q).size()])

# UT-S3-02: los bancos de Quiz I y Quiz II del mismo tema no comparten preguntas y juntos cubren el tema
func test_quiz_uno_y_dos_no_comparten_preguntas():
	for t in repo.obtener_temas():
		var q := quizzes(int(t["id"]))
		var b1 := ids(repo.banco_modulo(q[0]))
		var b2 := ids(repo.banco_modulo(q[1]))
		for id_r in b1:
			assert_false(id_r in b2, "Tema %d: la pregunta %d está en los dos quizzes" % [int(t["id"]), id_r])
		assert_eq(b1.size() + b2.size(), repo.obtener_reactivos_tema(int(t["id"])).size())

# UT-S3-03: un sorteo trae 5 preguntas distintas, todas del banco propio del módulo
func test_sorteo_sin_repetidas_y_del_banco_propio():
	var q := quizzes(3)
	var s := ids(repo.sortear_reactivos(q[1]))
	assert_eq(s.size(), repo.PREGUNTAS_POR_QUIZ)
	var propio := ids(repo.banco_modulo(q[1]))
	for i in s.size():
		assert_true(s[i] in propio)
		assert_eq(s.find(s[i]), i, "la pregunta %d se repite en el intento" % s[i])

# UT-S3-04: al reintentar, se prefieren las preguntas que no salieron en el intento anterior
func test_reintento_prefiere_preguntas_nuevas():
	var q := quizzes(1)                       # tema 1: 15 preguntas → 8 y 7 por quiz
	var primero := ids(repo.sortear_reactivos(q[0]))
	var segundo := ids(repo.sortear_reactivos(q[0]))
	var nuevas := 0
	for id_r in segundo:
		if not (id_r in primero):
			nuevas += 1
	# banco de 8, 5 por intento → al menos 3 preguntas nuevas garantizadas
	assert_true(nuevas >= 3, "solo %d preguntas nuevas en el reintento" % nuevas)
	assert_eq(repo.bd["ultimo_sorteo"][str(q[0])], segundo)

# UT-S3-05: el último sorteo sobrevive al guardado en JSON (ids como float)
func test_ultimo_sorteo_persistido_se_respeta():
	var q := quizzes(2)
	var primero := ids(repo.sortear_reactivos(q[0]))
	repo.guardar_bd()
	repo.cargar_bd()
	var segundo := ids(repo.sortear_reactivos(q[0]))
	var nuevas := 0
	for id_r in segundo:
		if not (id_r in primero):
			nuevas += 1
	assert_true(nuevas >= 3)

# UT-S3-06: todos los ejercicios de puzzle/práctica y todas las preguntas apuntan a un concepto que existe
func test_conceptos_de_ejercicios_y_preguntas_existen():
	for p in repo.bd["puzzles"]:
		var c := str(p.get("concepto", ""))
		assert_false(repo.obtener_concepto_por_id(c).is_empty(), "ejercicio «%s» sin concepto válido (%s)" % [str(p["instruccion"]).substr(0, 40), c])
	for r in repo.bd["reactivos"]:
		var c := str(r.get("id_concepto", ""))
		assert_false(repo.obtener_concepto_por_id(c).is_empty(), "pregunta %d sin concepto válido (%s)" % [int(r["id"]), c])
		assert_eq(int(repo.obtener_concepto_por_id(c)["id_tema"]), int(r["id_tema"]), "pregunta %d: concepto de otro tema" % int(r["id"]))

# UT-S3-07: el concepto de cada ejercicio es del mismo tema que el ejercicio
func test_concepto_de_cada_ejercicio_es_de_su_tema():
	for p in repo.bd["puzzles"]:
		var c: Dictionary = repo.obtener_concepto_por_id(str(p.get("concepto", "")))
		assert_eq(int(c["id_tema"]), int(p["id_tema"]), "ejercicio «%s»" % str(p["instruccion"]).substr(0, 40))

# UT-S3-08: los errores del Quiz II y de un módulo ya completado también entran al repaso
func test_errores_despues_de_completar_siguen_registrandose():
	var q := quizzes(4)
	# Quiz I aprobado con una pregunta mal
	var r1: Array = repo.banco_modulo(q[0])
	repo.registrar_error(int(r1[0]["id"]))
	repo.registrar_intento(q[0], 4, -1, 0, 5)
	assert_eq(repo.obtener_modulo(q[0])["estado"], "completado")
	assert_eq(repo.obtener_errores_pendientes().size(), 1)
	# Quiz II con dos mal
	var r2: Array = repo.banco_modulo(q[1])
	repo.registrar_error(int(r2[0]["id"]))
	repo.registrar_error(int(r2[1]["id"]))
	repo.registrar_intento(q[1], 3, -1, 0, 5)
	assert_eq(repo.obtener_errores_pendientes().size(), 3)
	# Rejugar el Quiz I ya completado con otra pregunta mal: también entra
	repo.registrar_error(int(r1[1]["id"]))
	repo.registrar_intento(q[0], 4, -1, 0, 5)
	assert_eq(repo.obtener_errores_pendientes().size(), 4)
	assert_eq(repo.obtener_errores_pendientes(4).size(), 4)

# UT-S3-09: un módulo completado sin 100 % aparece como "mejorable" en el progreso
func test_progreso_marca_modulos_mejorables():
	var q := quizzes(5)
	repo.registrar_intento(q[0], 4, -1, 0, 5)       # 80 %: completado pero mejorable
	repo.registrar_intento(q[1], 5, -1, 0, 5)       # 100 %
	var p: Dictionary = repo.obtener_progreso()
	assert_eq(p["dominados"].size(), 2)
	var mejorables := 0
	for f in p["dominados"]:
		if f["mejorable"]:
			mejorables += 1
			assert_eq(int(f["mejor_porcentaje"]), 80)
	assert_eq(mejorables, 1)
	assert_eq(int(p["mejorables"]), 1)
