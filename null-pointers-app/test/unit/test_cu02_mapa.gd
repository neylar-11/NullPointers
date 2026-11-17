# res://test/unit/test_cu02_mapa.gd
# Pruebas unitarias del CU-02 Seleccionar módulo de aprendizaje (RF-02)
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


# UT-02-01: estado inicial del mapa (RF-02). Sprint 3 (CU-08): 14 módulos en 3 materias;
# solo el primer módulo de cada materia (1, 9 y 12) inicia desbloqueado.
func test_obtener_modulos_inicial_solo_el_primero_de_cada_materia_desbloqueado():
	var modulos = repo.obtener_modulos()
	assert_eq(modulos.size(), 14, "Deben existir 14 módulos (8 + 3 + 3)")
	var primeros := [1, 9, 12]
	for m in modulos:
		var esperado = "desbloqueado" if int(m["id"]) in primeros else "bloqueado"
		assert_eq(m["estado"], esperado, "El módulo %d debe iniciar %s" % [m["id"], esperado])
	assert_eq(repo.obtener_modulos_materia(1).size(), 8, "La materia 1 conserva sus 8 módulos")


# UT-02-02: el siguiente módulo a jugar al inicio es el 1 (RF-02)
func test_siguiente_modulo_inicial_es_el_1():
	var siguiente = repo.siguiente_modulo()
	assert_false(siguiente.is_empty(), "Debe haber un módulo disponible")
	assert_eq(int(siguiente["id"]), 1)
