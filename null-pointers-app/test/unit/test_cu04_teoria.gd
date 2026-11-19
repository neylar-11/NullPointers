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
	DirAccess.remove_absolute("user://test_bd.json")


# UT-04-01: un reactivo con concepto devuelve su teoría (RF-04)
func test_obtener_concepto_de_reactivo_8_devuelve_req_no_funcional():
	var c = repo.obtener_concepto(8)
	assert_false(c.is_empty(), "El reactivo 8 tiene concepto asociado")
	assert_eq(c["id"], "req_no_funcional")
	assert_true(c.has("titulo") and c["titulo"] != "", "Debe tener título")
	assert_true(c.has("explicacion") and c["explicacion"] != "", "Debe tener explicación")


# UT-04-02: reactivo sin concepto devuelve vacío (CU-04 flujo alterno)
func test_obtener_concepto_sin_concepto_devuelve_vacio():
	# Preparar
	repo.bd["reactivos"][0]["id_concepto"] = ""
	# Ejecutar
	var c = repo.obtener_concepto(1)
	# Verificar
	assert_true(c.is_empty(), "Sin concepto asociado debe regresar un diccionario vacío")


# UT-04-03: consultar la teoría no cambia puntos ni intentos (CU-04 postcondición)
func test_registrar_consulta_teoria_no_altera_puntos_ni_intentos():
	# Preparar
	repo.registrar_intento(1, 3)
	var puntos_antes = repo.obtener_puntos_totales()
	var intentos_antes = repo.obtener_intentos(1).size()
	# Ejecutar
	repo.registrar_consulta_teoria()
	# Verificar
	assert_eq(repo.obtener_puntos_totales(), puntos_antes, "Los puntos no deben cambiar")
	assert_eq(repo.obtener_intentos(1).size(), intentos_antes, "Los intentos no deben cambiar")
