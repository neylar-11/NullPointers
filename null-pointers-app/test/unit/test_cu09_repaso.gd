# res://test/unit/test_cu09_repaso.gd
# Pruebas unitarias del CU-09 Repasar mis errores (RF-09)
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


# UT-09-01: sin errores la lista de repaso está vacía (CU-09 flujo alterno 1)
func test_sin_errores_no_hay_pendientes():
	assert_eq(repo.obtener_errores_pendientes().size(), 0)
	assert_eq(repo.obtener_resumen_errores().size(), 0)


# UT-09-02: una pregunta fallada entra a la lista una sola vez (CU-03 paso 6 alterno)
func test_registrar_error_no_duplica():
	repo.registrar_error(1)
	repo.registrar_error(1)
	assert_eq(repo.obtener_errores_pendientes().size(), 1, "La misma pregunta no se duplica")


# UT-09-03: un reactivo que no existe no se registra
func test_registrar_error_reactivo_inexistente_no_hace_nada():
	repo.registrar_error(9999)
	assert_eq(repo.bd["errores"].size(), 0)


# UT-09-04: el resumen agrupa por materia y módulo (CU-09 paso 2)
func test_resumen_agrupa_por_materia_y_modulo():
	# Preparar: 2 errores del módulo 1 (materia 1) y 1 del módulo 9 (materia 2)
	repo.registrar_error(1)
	repo.registrar_error(2)
	repo.registrar_error(41)
	# Ejecutar
	var resumen = repo.obtener_resumen_errores()
	# Verificar
	assert_eq(resumen.size(), 2, "Dos materias con errores")
	assert_eq(resumen[0]["id_materia"], 1)
	assert_eq(resumen[0]["total"], 2)
	assert_eq(resumen[0]["modulos"][0]["errores"], 2)
	assert_eq(resumen[1]["id_materia"], 2)
	assert_eq(repo.obtener_errores_pendientes(2).size(), 1, "Filtro por materia")


# UT-09-05: acertar en el repaso saca la pregunta de la lista; fallar la deja (CU-09 paso 6)
func test_registrar_repaso_acierto_corrige_fallo_permanece():
	repo.registrar_error(1)
	repo.registrar_error(2)
	repo.registrar_repaso(1, true)
	repo.registrar_repaso(2, false)
	var pendientes = repo.obtener_errores_pendientes()
	assert_eq(pendientes.size(), 1)
	assert_eq(int(pendientes[0]["id_reactivo"]), 2)


# UT-09-06: el repaso no da puntos ni cambia el mejor puntaje (regla del CU-09)
func test_repaso_no_otorga_puntos():
	repo.registrar_intento(1, 4)
	repo.registrar_error(5)
	var puntos_antes = repo.obtener_puntos_totales()
	repo.registrar_repaso(5, true)
	assert_eq(repo.obtener_puntos_totales(), puntos_antes)
	assert_eq(int(repo.obtener_modulo(1)["mejor_puntaje"]), 80)


# UT-09-07: volver a fallar una pregunta corregida la regresa a la lista
func test_fallar_de_nuevo_regresa_a_la_lista():
	repo.registrar_error(1)
	repo.registrar_repaso(1, true)
	repo.registrar_error(1)
	assert_eq(repo.obtener_errores_pendientes().size(), 1)


# UT-09-08: vaciar la lista otorga la insignia «Repasador» (CU-09 paso 9)
func test_vaciar_lista_otorga_repasador():
	repo.registrar_error(1)
	repo.registrar_repaso(1, true)
	var nuevas = repo.terminar_repaso()
	var ids = nuevas.map(func(i): return i["id"])
	assert_has(ids, "repasador")
