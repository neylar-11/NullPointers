# res://test/unit/test_cu03_actividad.gd
# Pruebas unitarias del CU-03 Resolver actividad de aprendizaje (RF-03)
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


# UT-03-01: 4 de 5 aciertos (80 %) completa el módulo y desbloquea el siguiente (RF-03)
func test_registrar_intento_con_80_completa_y_desbloquea_siguiente():
	var r = repo.registrar_intento(1, 4)
	assert_eq(r["porcentaje"], 80)
	assert_true(r["completado"], "80 % supera el mínimo de 70 %")
	assert_eq(repo.obtener_modulo(2)["estado"], "desbloqueado", "El módulo 2 debe desbloquearse")
	assert_eq(repo.obtener_puntos_totales(), 80)


# UT-03-02: 3 de 5 aciertos (60 %) no completa ni desbloquea (RF-03)
func test_registrar_intento_con_60_no_completa():
	var r = repo.registrar_intento(1, 3)
	assert_eq(r["porcentaje"], 60)
	assert_false(r["completado"], "60 % no alcanza el mínimo de 70 %")
	assert_eq(repo.obtener_modulo(2)["estado"], "bloqueado", "El módulo 2 debe seguir bloqueado")


# UT-03-03: repetir con menor puntaje conserva el mejor (CU-03 flujo alterno 2)
func test_registrar_intento_peor_conserva_mejor_puntaje():
	# Preparar
	repo.registrar_intento(1, 5)
	# Ejecutar
	repo.registrar_intento(1, 4)
	# Verificar
	assert_eq(repo.obtener_puntos_totales(), 100, "Los puntos totales no deben bajar")
	assert_eq(int(repo.obtener_modulo(1)["mejor_puntaje"]), 100, "El mejor puntaje debe seguir en 100")


# UT-03-04: un intento que no mejora no se guarda (CU-03 flujo alterno 4)
# Se espera que FALLE con el código actual: registrar_intento() guarda todos los intentos.
func test_registrar_intento_que_no_mejora_no_se_guarda():
	# Preparar
	repo.registrar_intento(1, 5)
	# Ejecutar
	repo.registrar_intento(1, 4)
	# Verificar
	assert_eq(repo.obtener_intentos(1).size(), 1, "Solo debe guardarse el intento si mejora el puntaje")
