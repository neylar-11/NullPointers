# res://test/unit/test_cu12_sesion.gd
# Pruebas unitarias del CU-12 Iniciar sesión / perfiles (varios estudiantes por teléfono)
extends GutTest

const Repo = preload("res://autoload/JuegoRepository.gd")
var repo

func _limpiar() -> void:
	for ruta in ["user://test_perfiles.json", "user://test_bd.json", "user://test_bd.json.bak",
			"user://test_bd.json.tmp", "user://perfil_p1.json", "user://perfil_p2.json", "user://perfil_p3.json",
			"user://perfil_p1.json.bak", "user://perfil_p2.json.bak", "user://perfil_p3.json.bak", "user://sin_sesion.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ruta))

func before_each():
	_limpiar()
	repo = Repo.new()
	repo.ruta_indice = "user://test_perfiles.json"
	repo.ruta_bd = "user://test_bd.json"
	repo.indice = {"activo": "", "perfiles": [], "siguiente": 1}

func after_each():
	repo.free()
	_limpiar()


# UT-12-01: crear un perfil lo deja como sesión activa con su alias
func test_crear_perfil_abre_sesion():
	var e = repo.crear_perfil_nuevo("Ana")
	assert_eq(e["alias"], "Ana")
	assert_true(repo.sesion_activa())
	assert_eq(repo.obtener_perfil()["alias"], "Ana")
	assert_eq(repo.obtener_perfiles().size(), 1)

# UT-12-02: alias inválido o repetido no crea perfil
func test_crear_perfil_rechaza_alias_invalido_o_repetido():
	repo.crear_perfil_nuevo("Ana")
	assert_true(repo.crear_perfil_nuevo("ab").is_empty())
	assert_true(repo.crear_perfil_nuevo("ana").is_empty())
	assert_true(repo.crear_perfil_nuevo("Luis", "12").is_empty())    # contraseña inválida
	assert_eq(repo.obtener_perfiles().size(), 1)

# UT-12-03: alias vacío genera un nombre automático (perfil por defecto)
func test_crear_perfil_sin_alias_usa_nombre_automatico():
	var e = repo.crear_perfil_nuevo("")
	assert_true(str(e["alias"]).begins_with("estudiante_"))

# UT-12-04: cerrar sesión conserva el progreso y deja la app sin perfil
func test_cerrar_sesion_conserva_progreso():
	repo.crear_perfil_nuevo("Ana")
	repo.registrar_intento(101, 5, -1, 0, 5)
	var puntos = repo.obtener_puntos_totales()
	repo.cerrar_sesion()
	assert_false(repo.sesion_activa())
	assert_eq(repo.obtener_puntos_totales(), 0)
	assert_true(repo.iniciar_sesion("p1"))
	assert_eq(repo.obtener_puntos_totales(), puntos)

# UT-12-05: un perfil con contraseña solo abre con la correcta
func test_iniciar_sesion_pide_contrasena():
	repo.crear_perfil_nuevo("Ana", "1234")
	repo.cerrar_sesion()
	assert_false(repo.iniciar_sesion("p1", "0000"))
	assert_false(repo.sesion_activa())
	assert_true(repo.iniciar_sesion("p1", "1234"))
	assert_eq(repo.obtener_perfil()["alias"], "Ana")

# UT-12-06: cada perfil tiene su propio progreso
func test_cada_perfil_tiene_su_progreso():
	repo.crear_perfil_nuevo("Ana")
	repo.registrar_intento(101, 5, -1, 0, 5)
	repo.crear_perfil_nuevo("Luis")
	assert_eq(repo.obtener_puntos_totales(), 0)
	assert_eq(repo.modulos_completados(), 0)
	repo.iniciar_sesion("p1")
	assert_eq(repo.modulos_completados(), 1)

# UT-12-07: cambiar nombre, avatar o contraseña actualiza el índice de perfiles
func test_cambios_del_perfil_se_reflejan_en_el_indice():
	repo.crear_perfil_nuevo("Ana")
	repo.actualizar_nombre("Ana María")
	repo.actualizar_contrasena("4321", "4321")
	var e = repo.obtener_perfiles()[0]
	assert_eq(e["alias"], "Ana María")
	assert_true(e["con_contrasena"])
	repo.quitar_contrasena()
	assert_false(repo.obtener_perfiles()[0]["con_contrasena"])

# UT-12-08: eliminar un perfil borra su archivo; sin perfiles se crea uno por defecto
func test_eliminar_perfil_borra_archivo_y_crea_defecto():
	var e = repo.crear_perfil_nuevo("Ana")
	var archivo = ProjectSettings.globalize_path(str(e["archivo"]))
	assert_true(FileAccess.file_exists(archivo))
	assert_true(repo.eliminar_perfil("p1"))
	assert_false(FileAccess.file_exists(archivo))
	assert_eq(repo.obtener_perfiles().size(), 1)        # el perfil por defecto nuevo
	assert_ne(repo.obtener_perfiles()[0]["id"], "p1")

# UT-12-09: el índice se guarda y se vuelve a leer (otro arranque de la app)
func test_indice_persiste_entre_arranques():
	repo.crear_perfil_nuevo("Ana", "1234")
	repo.crear_perfil_nuevo("Luis")
	var otro = Repo.new()
	otro.ruta_indice = "user://test_perfiles.json"
	otro.cargar_perfiles()
	assert_eq(otro.obtener_perfiles().size(), 2)
	assert_true(otro.sesion_activa())                   # Luis (sin contraseña) entra directo
	assert_eq(otro.obtener_perfil()["alias"], "Luis")
	otro.free()
	var tercero = Repo.new()
	tercero.ruta_indice = "user://test_perfiles.json"
	tercero.indice = {}
	# Si el activo tiene contraseña, el arranque no abre sesión
	var datos = JSON.parse_string(FileAccess.get_file_as_string("user://test_perfiles.json"))
	datos["activo"] = "p1"
	var f = FileAccess.open("user://test_perfiles.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(datos)); f.close()
	tercero.cargar_perfiles()
	assert_false(tercero.sesion_activa())
	tercero.free()
