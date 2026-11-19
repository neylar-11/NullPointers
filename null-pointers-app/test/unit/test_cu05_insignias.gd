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
	DirAccess.remove_absolute("user://test_bd.json")

func _buscar_insignia(id: String) -> Dictionary:
	for ins in repo.obtener_insignias():
		if ins["id"] == id:
			return ins
	return {}


# UT-05-01: catálogo inicial de 12 insignias (9 + 3 del Sprint 3), ninguna obtenida (RF-05)
func test_obtener_insignias_inicial_12_y_ninguna_obtenida():
	assert_eq(repo.obtener_insignias().size(), 12, "Deben existir 12 insignias")
	assert_eq(repo.insignias_obtenidas(), 0, "Al inicio no hay insignias obtenidas")


# UT-05-02: completar el primer módulo otorga "primer_paso" (RF-05)
func test_registrar_intento_completado_otorga_primer_paso():
	repo.registrar_intento(1, 4)
	var ins = _buscar_insignia("primer_paso")
	assert_true(ins["obtenida"], "La insignia primer_paso debe quedar obtenida")
	assert_ne(ins["fecha_obtencion"], "", "Debe registrar la fecha de obtención")


# UT-05-03: 5 consultas de teoría otorgan "estudioso" (RF-05)
func test_registrar_consulta_teoria_5_veces_otorga_estudioso():
	for i in 5:
		repo.registrar_consulta_teoria()
	assert_true(_buscar_insignia("estudioso")["obtenida"], "La insignia estudioso debe quedar obtenida")
