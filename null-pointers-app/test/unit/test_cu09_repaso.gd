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
	for sufijo in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_bd.json" + sufijo))

# Completa con 100 % todos los módulos de un tema
func completar_tema(id_tema: int) -> void:
	for m in repo.obtener_modulos_tema(id_tema):
		repo.registrar_intento(int(m["id"]), int(m["num_preguntas"]), -1, 0, int(m["num_preguntas"]))


func rid(tema: int, k: int = 0) -> int:
	return int(repo.obtener_reactivos_tema(tema)[k]["id"])

# UT-09-01: sin errores no hay pendientes (alt. 3)
func test_sin_errores_no_hay_pendientes():
	assert_eq(repo.obtener_errores_pendientes().size(), 0)
	assert_eq(repo.obtener_resumen_errores().size(), 0)

# UT-09-02: la misma pregunta no se duplica
func test_registrar_error_no_duplica():
	repo.registrar_error(rid(1))
	repo.registrar_error(rid(1))
	assert_eq(repo.obtener_errores_pendientes().size(), 1)

# UT-09-03: un reactivo inexistente no se registra
func test_registrar_error_reactivo_inexistente_no_hace_nada():
	repo.registrar_error(999999)
	assert_eq(repo.bd["errores"].size(), 0)

# UT-09-04: el resumen agrupa por tema (paso 2)
func test_resumen_agrupa_por_tema():
	repo.registrar_error(rid(1, 0))
	repo.registrar_error(rid(1, 1))
	repo.registrar_error(rid(7, 0))
	var resumen = repo.obtener_resumen_errores()
	assert_eq(resumen.map(func(g): return [g["id_tema"], g["total"]]), [[1, 2], [7, 1]])
	assert_eq(repo.obtener_errores_pendientes(7).size(), 1)

# UT-09-05: acertar en el repaso la saca; fallar la deja (paso 6)
func test_registrar_repaso_acierto_corrige_fallo_permanece():
	repo.registrar_error(rid(2, 0))
	repo.registrar_error(rid(2, 1))
	repo.registrar_repaso(rid(2, 0), true)
	repo.registrar_repaso(rid(2, 1), false)
	assert_eq(repo.obtener_errores_pendientes().map(func(e): return int(e["id_reactivo"])), [rid(2, 1)])

# UT-09-06: el repaso no otorga puntos ni cambia el mejor puntaje (regla)
func test_repaso_no_otorga_puntos():
	repo.registrar_intento(101, 4)
	repo.registrar_error(rid(1))
	var puntos = repo.obtener_puntos_totales()
	repo.registrar_repaso(rid(1), true)
	repo.terminar_repaso()
	assert_eq(repo.obtener_puntos_totales(), puntos)
	assert_eq(int(repo.obtener_modulo(101)["mejor_puntaje"]), 80)

# UT-09-07: volver a fallar una pregunta corregida la regresa a la lista (regla)
func test_fallar_de_nuevo_regresa_a_la_lista():
	repo.registrar_error(rid(1))
	repo.registrar_repaso(rid(1), true)
	repo.registrar_error(rid(1))
	assert_eq(repo.obtener_errores_pendientes().size(), 1)

# UT-09-08: corregir 5 preguntas da "Repasador" en bronce
func test_corregir_5_preguntas_otorga_repasador():
	for k in 5:
		repo.registrar_error(rid(3, k))
		repo.registrar_repaso(rid(3, k), true)
	var ids = repo.terminar_repaso().map(func(i): return i["id"])
	assert_has(ids, "repasador")
