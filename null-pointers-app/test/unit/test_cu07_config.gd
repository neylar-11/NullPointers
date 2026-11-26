# res://test/unit/test_cu07_config.gd
# Pruebas unitarias del CU-07 Configurar juego (modo claro/oscuro y paletas desbloqueables)
extends GutTest

const Repo = preload("res://autoload/JuegoRepository.gd")
var repo

func before_each():
	repo = Repo.new()
	repo.ruta_bd = "user://test_bd.json"
	repo.bd = repo._bd_inicial()

func after_each():
	repo.free()
	for sufijo in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_bd.json" + sufijo))

# UT-07-01: valores por defecto: claro y azul
func test_configuracion_inicial():
	var c = repo.obtener_configuracion()
	assert_eq(c["modo"], "claro")
	assert_eq(c["paleta"], "azul")

# UT-07-02: cambiar el modo se guarda y se vuelve a leer del archivo (RNF-02)
func test_cambiar_modo_persiste():
	assert_true(repo.actualizar_modo("oscuro"))
	assert_false(repo.actualizar_modo("sepia"))
	var otro = Repo.new()
	otro.ruta_bd = "user://test_bd.json"
	otro.cargar_bd()
	assert_eq(otro.obtener_configuracion()["modo"], "oscuro")
	otro.free()

# UT-07-03: una paleta bloqueada no se puede elegir; al cumplir su condición sí
func test_paleta_se_desbloquea_con_avance():
	assert_false(repo.paleta_disponible("verde"))
	assert_false(repo.actualizar_paleta("verde"))
	assert_eq(repo.obtener_configuracion()["paleta"], "azul")
	repo.registrar_intento(101, 5, -1, 0, 5)           # primer módulo completado
	assert_true(repo.paleta_disponible("verde"))
	assert_true(repo.actualizar_paleta("verde"))
	assert_eq(repo.obtener_configuracion()["paleta"], "verde")

# UT-07-04: el catálogo trae disponible/progreso/meta y una paleta inexistente se rechaza
func test_catalogo_de_paletas():
	var cat = repo.obtener_catalogo_paletas()
	assert_eq(cat.size(), repo.PALETAS.size())
	assert_true(cat[0]["disponible"])
	assert_eq(int(cat[1]["meta"]), 1)
	assert_false(repo.actualizar_paleta("arcoiris"))

# UT-07-05: restablecer regresa a claro / azul
func test_restablecer_configuracion():
	repo.actualizar_modo("oscuro")
	repo.restablecer_configuracion()
	assert_eq(repo.obtener_configuracion()["modo"], "claro")
	assert_eq(repo.obtener_configuracion()["paleta"], "azul")

# UT-07-06: un archivo guardado antes de CU-07 (sin "config") carga con los valores por defecto
func test_archivo_viejo_sin_config_carga_con_defecto():
	repo.bd.erase("config")
	repo.guardar_bd()
	var otro = Repo.new()
	otro.ruta_bd = "user://test_bd.json"
	otro.cargar_bd()
	assert_eq(otro.obtener_configuracion()["modo"], "claro")
	otro.free()
