# res://test/unit/test_cu02_mapa.gd
# Pruebas unitarias del CU-02 Elegir módulo (RF-02)
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


# UT-02-01: cada tema tiene Quiz I, Quiz II y Puzzle; solo el Quiz I inicia desbloqueado
func test_mapa_de_cada_tema_inicia_con_solo_el_quiz_i_desbloqueado():
	assert_eq(repo.obtener_modulos().size(), 36, "12 temas × 3 módulos")
	for t in repo.obtener_temas():
		var mods = repo.obtener_modulos_tema(int(t["id"]))
		assert_eq(mods.size(), 3, "Tema %s con 3 módulos" % t["id"])
		assert_eq(mods.map(func(m): return m["tipo"]), ["quiz", "quiz", "puzzle"])
		assert_eq(mods.map(func(m): return m["estado"]), ["desbloqueado", "bloqueado", "bloqueado"])

# UT-02-02: el siguiente módulo jugable de un tema nuevo es su Quiz I
func test_siguiente_modulo_de_un_tema_nuevo_es_su_quiz_i():
	assert_eq(int(repo.siguiente_modulo_tema(3)["id"]), 301)
