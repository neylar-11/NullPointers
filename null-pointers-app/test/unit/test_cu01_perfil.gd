# res://test/unit/test_cu01_perfil.gd
# Pruebas unitarias del CU-01 Editar perfil (RF-01) sobre JuegoRepository.gd
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


# UT-01-01: alias válido de 3 a 20 caracteres (RF-01)
func test_actualizar_nombre_con_alias_valido_lo_guarda():
	# Ejecutar
	var ok = repo.actualizar_nombre("DevNull")
	# Verificar
	assert_true(ok, "Debe aceptar un alias de 7 caracteres")
	assert_eq(repo.obtener_perfil()["alias"], "DevNull")


# UT-01-02: alias de 2 caracteres, debajo del mínimo (RF-01)
func test_actualizar_nombre_con_2_caracteres_lo_rechaza():
	var alias_antes = repo.obtener_perfil()["alias"]
	var ok = repo.actualizar_nombre("ab")
	assert_false(ok, "Un alias de 2 caracteres debe rechazarse")
	assert_eq(repo.obtener_perfil()["alias"], alias_antes, "El alias no debe cambiar")


# UT-01-03: alias de 21 caracteres, arriba del máximo (RF-01)
func test_actualizar_nombre_con_21_caracteres_lo_rechaza():
	var alias_antes = repo.obtener_perfil()["alias"]
	var ok = repo.actualizar_nombre("a".repeat(21))
	assert_false(ok, "Un alias de 21 caracteres debe rechazarse")
	assert_eq(repo.obtener_perfil()["alias"], alias_antes, "El alias no debe cambiar")


# UT-01-04: alias de solo espacios cuenta como vacío (RF-01)
func test_actualizar_nombre_solo_espacios_lo_rechaza():
	var ok = repo.actualizar_nombre("   ")
	assert_false(ok, "Un alias de solo espacios debe tratarse como vacío")


# UT-01-05: contraseñas que no coinciden (RF-01)
func test_actualizar_contrasena_que_no_coinciden_la_rechaza():
	var ok = repo.actualizar_contrasena("1234", "9999")
	assert_false(ok, "Si las contraseñas no coinciden debe rechazarse")
	assert_false(repo.tiene_contrasena(), "No debe quedar contraseña guardada")


# UT-01-06: contraseña con letras (solo se permiten dígitos) (RF-01)
func test_actualizar_contrasena_con_letras_la_rechaza():
	var ok = repo.actualizar_contrasena("12a4", "12a4")
	assert_false(ok, "La contraseña solo admite dígitos")


# UT-01-07: contraseña fuera del rango de 4 a 8 dígitos (RF-01)
func test_actualizar_contrasena_fuera_de_4_a_8_la_rechaza():
	var ok_corta = repo.actualizar_contrasena("123", "123")
	var ok_larga = repo.actualizar_contrasena("123456789", "123456789")
	assert_false(ok_corta, "3 dígitos está debajo del mínimo")
	assert_false(ok_larga, "9 dígitos está arriba del máximo")


# UT-01-08: avatar que no está en el catálogo (RF-01)
func test_actualizar_avatar_fuera_de_catalogo_lo_rechaza():
	var ok = repo.actualizar_avatar("avatar_99")
	assert_false(ok, "Un avatar fuera del catálogo debe rechazarse")
	assert_eq(repo.obtener_perfil()["avatar_id"], "avatar_01", "El avatar debe seguir siendo el inicial")
