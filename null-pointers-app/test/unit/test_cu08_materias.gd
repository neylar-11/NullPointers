# res://test/unit/test_cu08_materias.gd
# Pruebas unitarias del CU-08 Elegir materia (RF-08)
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


# UT-08-01: catálogo inicial de 3 materias, todas sin iniciar (CU-08 paso 2)
func test_catalogo_inicial_3_materias_sin_iniciar():
	var cat = repo.obtener_catalogo_materias()
	assert_eq(cat.size(), 3, "Deben existir 3 materias")
	for fila in cat:
		assert_true(fila["sin_iniciar"], "La materia %d debe estar sin iniciar" % fila["id"])
		assert_eq(fila["porcentaje"], 0)
		assert_false(fila["dominada"])
	assert_eq(cat[0]["modulos_totales"], 8)
	assert_eq(cat[1]["modulos_totales"], 3)
	assert_eq(cat[2]["modulos_totales"], 3)


# UT-08-02: el avance de una materia se calcula con sus módulos completados (CU-08 paso 2)
func test_catalogo_calcula_porcentaje_de_avance():
	# Preparar: 1 de 3 módulos de la materia 2
	repo.registrar_intento(9, 5)
	# Ejecutar
	var fila = repo.obtener_catalogo_materias()[1]
	# Verificar
	assert_eq(fila["modulos_completados"], 1)
	assert_eq(fila["porcentaje"], 33, "1 de 3 módulos = 33 %")
	assert_false(fila["sin_iniciar"])


# UT-08-03: elegir una materia la recuerda como la última (CU-08 paso 4 y flujo alterno 2)
func test_seleccionar_materia_la_recuerda_como_ultima():
	repo.seleccionar_materia(3)
	assert_eq(repo.materia_seleccionada, 3)
	assert_eq(int(repo.obtener_ultima_materia()["id"]), 3)
	var cat = repo.obtener_catalogo_materias()
	assert_true(cat[2]["es_ultima"], "La materia 3 debe marcarse como «Continuar en…»")
	assert_false(cat[0]["es_ultima"])


# UT-08-04: completar un módulo desbloquea el siguiente de LA MISMA materia (regla del CU-08)
func test_completar_ultimo_modulo_de_materia_no_desbloquea_otra_materia():
	# Preparar
	repo.registrar_intento(9, 5)
	repo.registrar_intento(10, 5)
	# Ejecutar: módulo 11 es el último de la materia 2
	var r = repo.registrar_intento(11, 5)
	# Verificar
	assert_true(r["siguiente_desbloqueado"].is_empty(), "No hay siguiente módulo en la materia 2")
	assert_eq(repo.obtener_modulo(13)["estado"], "bloqueado", "La materia 3 no se ve afectada")
	assert_eq(repo.obtener_modulo(2)["estado"], "bloqueado", "La materia 1 no se ve afectada")


# UT-08-05: el siguiente módulo jugable se busca dentro de la materia (CU-08 paso 5)
func test_siguiente_modulo_materia():
	assert_eq(int(repo.siguiente_modulo_materia(2)["id"]), 9)
	repo.registrar_intento(9, 5)
	assert_eq(int(repo.siguiente_modulo_materia(2)["id"]), 10)
