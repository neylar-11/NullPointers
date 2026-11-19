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
	for sufijo in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_bd.json" + sufijo))

# Completa con 100 % todos los módulos de un tema
func completar_tema(id_tema: int) -> void:
	for m in repo.obtener_modulos_tema(id_tema):
		repo.registrar_intento(int(m["id"]), int(m["num_preguntas"]), -1, 0, int(m["num_preguntas"]))


func rid(tema: int, k: int = 0) -> int:
	return int(repo.obtener_reactivos_tema(tema)[k]["id"])

# UT-10-01: costo de cada pista
func test_costo_de_pistas():
	assert_eq(repo.costo_pista("recordar"), 0.25)
	assert_eq(repo.costo_pista("descartar"), 0.50)
	assert_eq(repo.costo_pista("otra"), 0.0)

# UT-10-02: "Descartar" nunca elimina la respuesta correcta, en ninguna pregunta del banco
func test_opcion_a_descartar_nunca_es_la_correcta():
	for r in repo.bd["reactivos"]:
		var d = repo.opcion_a_descartar(int(r["id"]))
		assert_ne(d, int(r["respuesta_correcta"]))
		assert_between(d, 0, r["opciones"].size() - 1)

# UT-10-03: con dos opciones no se puede descartar (alt. 3)
func test_opcion_a_descartar_con_dos_opciones_regresa_menos_uno():
	repo.obtener_reactivo(rid(1))["opciones"] = ["Sí", "No"]
	assert_eq(repo.opcion_a_descartar(rid(1)), -1)

# UT-10-04: "Recordar el concepto" da texto; sin concepto da vacío (alt. 2)
func test_texto_pista_concepto():
	assert_ne(repo.texto_pista_concepto(rid(1)), "")
	repo.obtener_reactivo(rid(1))["id_concepto"] = ""
	assert_eq(repo.texto_pista_concepto(rid(1)), "")

# UT-10-05: los puntos del intento reflejan los descuentos y se guardan las pistas (postcondición)
func test_registrar_intento_con_pistas_descuenta_puntos_y_las_guarda():
	var r = repo.registrar_intento(101, 5, 75, 2)
	assert_eq(r["puntos"], 75)
	assert_eq(repo.obtener_puntos_totales(), 75)
	assert_eq(int(repo.obtener_intentos(101)[0]["pistas"]), 2)

# UT-10-06: completar un módulo sin pistas da "Sin ayuda"; con pistas no
func test_insignia_sin_ayuda():
	var r = repo.registrar_intento(101, 5, 75, 1)
	assert_does_not_have(r["insignias_nuevas"].map(func(i): return i["id"]), "sin_pistas")
	r = repo.registrar_intento(201, 5)
	assert_has(r["insignias_nuevas"].map(func(i): return i["id"]), "sin_pistas")
