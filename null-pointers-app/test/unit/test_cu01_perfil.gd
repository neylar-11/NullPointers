# res://test/unit/test_cu01_perfil.gd
# Pruebas unitarias del CU-01 Editar perfil (RF-01)
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


# UT-01-01: alias válido se guarda
func test_actualizar_nombre_con_alias_valido_lo_guarda():
	assert_true(repo.actualizar_nombre("DevNull"))
	assert_eq(repo.obtener_perfil()["alias"], "DevNull")

# UT-01-02: alias de 2 caracteres se rechaza
func test_actualizar_nombre_con_2_caracteres_lo_rechaza():
	var antes = repo.obtener_perfil()["alias"]
	assert_false(repo.actualizar_nombre("ab"))
	assert_eq(repo.obtener_perfil()["alias"], antes)

# UT-01-03: alias de 21 caracteres se rechaza
func test_actualizar_nombre_con_21_caracteres_lo_rechaza():
	var antes = repo.obtener_perfil()["alias"]
	assert_false(repo.actualizar_nombre("a".repeat(21)))
	assert_eq(repo.obtener_perfil()["alias"], antes)

# UT-01-04: solo espacios cuenta como vacío
func test_actualizar_nombre_solo_espacios_lo_rechaza():
	assert_false(repo.actualizar_nombre("   "))

# UT-01-05: contraseñas que no coinciden
func test_actualizar_contrasena_que_no_coinciden_la_rechaza():
	assert_false(repo.actualizar_contrasena("1234", "9999"))
	assert_false(repo.tiene_contrasena())

# UT-01-06: contraseña con letras
func test_actualizar_contrasena_con_letras_la_rechaza():
	assert_false(repo.actualizar_contrasena("12a4", "12a4"))

# UT-01-07: contraseña fuera de 4 a 8 dígitos
func test_actualizar_contrasena_fuera_de_4_a_8_la_rechaza():
	assert_false(repo.actualizar_contrasena("123", "123"))
	assert_false(repo.actualizar_contrasena("123456789", "123456789"))

# UT-01-08: avatar fuera del catálogo
func test_actualizar_avatar_fuera_de_catalogo_lo_rechaza():
	assert_false(repo.actualizar_avatar("avatar_99"))
	assert_eq(repo.obtener_perfil()["avatar_id"], "avatar_01")

# UT-01-09 (Sprint 3): un avatar bloqueado no se puede elegir hasta cumplir su requisito
func test_avatar_bloqueado_se_desbloquea_al_completar_un_tema():
	assert_false(repo.actualizar_avatar("avatar_07"), "Búho pide completar un tema")
	completar_tema(1)
	assert_true(repo.actualizar_avatar("avatar_07"))
	assert_eq(repo.obtener_perfil()["avatar_id"], "avatar_07")
