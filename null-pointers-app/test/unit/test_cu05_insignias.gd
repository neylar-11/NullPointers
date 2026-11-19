# res://test/unit/test_cu05_insignias.gd
# Pruebas unitarias del CU-05 Ver insignias (RF-05)
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


# UT-05-01: catálogo inicial de 24 insignias (12 de logro + 12 medallas de tema), ninguna obtenida
func test_catalogo_inicial_24_insignias_ninguna_obtenida():
	assert_eq(repo.obtener_insignias().size(), 24)
	assert_eq(repo.obtener_insignias_tipo("logro").size(), 12)
	assert_eq(repo.obtener_insignias_tipo("tema").size(), 12)
	assert_eq(repo.insignias_obtenidas(), 0)

# UT-05-02: completar el primer módulo da "Primer paso" en bronce, con fecha
func test_completar_primer_modulo_otorga_primer_paso_bronce():
	var r = repo.registrar_intento(101, 4)
	var ids = r["insignias_nuevas"].map(func(i): return i["id"])
	assert_has(ids, "primer_paso")
	for i in repo.obtener_insignias():
		if i["id"] == "primer_paso":
			assert_eq(int(i["nivel"]), 1)
			assert_ne(str(i["fecha"]), "")

# UT-05-03: 5 consultas de teoría dan "Estudioso"
func test_registrar_consulta_teoria_5_veces_otorga_estudioso():
	for k in 5:
		repo.registrar_consulta_teoria()
	assert_true(repo.obtener_insignias().any(func(i): return i["id"] == "estudioso" and i["obtenida"]))

# UT-05-04: la medalla de un tema sube a oro con 100 % de promedio en sus tres módulos
func test_medalla_de_tema_en_oro_con_100_en_los_tres_modulos():
	completar_tema(4)
	for i in repo.obtener_insignias_tipo("tema"):
		if int(i["id_tema"]) == 4:
			assert_eq(int(i["nivel"]), 3, "Oro")

# UT-05-05: "Constante" cuenta todos los retos terminados, aunque el intento no se guarde (CU-03 alt. 4)
func test_constante_cuenta_retos_aunque_no_se_guarden():
	for k in 10:
		repo.registrar_intento(101, 5)
	assert_eq(repo.obtener_intentos(101).size(), 1, "Solo se guarda el primer 100 %")
	assert_true(repo.obtener_insignias().any(func(i): return i["id"] == "constante" and i["obtenida"]))
