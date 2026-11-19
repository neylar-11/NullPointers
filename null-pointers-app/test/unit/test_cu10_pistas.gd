# res://test/unit/test_cu10_pistas.gd
# Pruebas unitarias del CU-10 Pedir una pista (RF-10)
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


# UT-10-01: costo de cada tipo de pista (regla del CU-10)
func test_costo_de_pistas():
	assert_eq(repo.costo_pista("recordar"), 0.25)
	assert_eq(repo.costo_pista("descartar"), 0.50)
	assert_eq(repo.costo_pista("otra"), 0.0, "Un tipo desconocido no cuesta")


# UT-10-02: «Descartar» nunca elimina la respuesta correcta
func test_opcion_a_descartar_nunca_es_la_correcta():
	var correcta = int(repo.obtener_reactivo(1)["respuesta_correcta"])
	for i in 30:
		var d = repo.opcion_a_descartar(1)
		assert_ne(d, correcta, "No debe descartar la respuesta correcta")
		assert_between(d, 0, 3)


# UT-10-03: pregunta de dos opciones no permite descartar (CU-10 flujo alterno 3)
func test_opcion_a_descartar_con_dos_opciones_regresa_menos_uno():
	repo.obtener_reactivo(1)["opciones"] = ["Sí", "No"]
	assert_eq(repo.opcion_a_descartar(1), -1)


# UT-10-04: «Recordar el concepto» da texto; sin concepto da vacío (CU-10 flujo alterno 2)
func test_texto_pista_concepto():
	assert_ne(repo.texto_pista_concepto(1), "", "El reactivo 1 tiene concepto")
	repo.obtener_reactivo(1)["id_concepto"] = ""
	assert_eq(repo.texto_pista_concepto(1), "")


# UT-10-05: los puntos del intento reflejan el descuento por pistas (postcondición del CU-10)
func test_registrar_intento_con_pistas_descuenta_puntos_y_las_guarda():
	# Ejecutar: 5/5 pero con 75 puntos tras pistas
	var r = repo.registrar_intento(1, 5, 75, 2)
	# Verificar
	assert_eq(r["puntos"], 75)
	assert_eq(repo.obtener_puntos_totales(), 75)
	assert_eq(int(repo.obtener_intentos(1)[0]["pistas"]), 2, "El intento registra las pistas usadas")


# UT-10-06: completar sin pistas otorga «Sin ayuda»; con pistas no
func test_insignia_sin_ayuda():
	var r = repo.registrar_intento(1, 5, 75, 1)
	assert_does_not_have(r["insignias_nuevas"].map(func(i): return i["id"]), "sin_pistas")
	r = repo.registrar_intento(2, 5)
	assert_has(r["insignias_nuevas"].map(func(i): return i["id"]), "sin_pistas")
