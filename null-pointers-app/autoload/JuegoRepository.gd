# res://autoload/JuegoRepository.gd
# Base de datos local (Autoload / Singleton) de NullPointers-AppGamificada.
# Persiste en user:// (memoria interna de la app) como JSON → 100 % offline (RNF-01, RNF-02).
#
# Tablas (SDS): perfil_jugador, materias, modulos, reactivos, intentos_modulo, conceptos,
#               insignias, errores (CU-09), practicas e intentos_practica (CU-11)
# Casos de uso cubiertos: CU-01 (perfil), CU-02 (mapa), CU-03 (actividad),
#                         CU-04 (teoría), CU-05 (insignias), CU-06 (progreso),
#                         CU-08 (materias), CU-09 (repaso de errores),
#                         CU-10 (pistas), CU-11 (práctica de ingeniero)
#
# Uso desde cualquier escena:
#   JuegoRepository.crear_perfil("estudiante_7421")
#   JuegoRepository.obtener_materias()               # CU-08
#   JuegoRepository.obtener_modulos(id_materia)      # CU-02 / CU-08
#   JuegoRepository.registrar_intento(3, 4)   # módulo 3, 4 aciertos de 5
#   JuegoRepository.obtener_concepto(id_reactivo)   # CU-04
#   JuegoRepository.obtener_insignias()             # CU-05
#   JuegoRepository.obtener_progreso()              # CU-06
#   JuegoRepository.obtener_errores_pendientes()    # CU-09
#   JuegoRepository.costo_pista("recordar")         # CU-10
#   JuegoRepository.obtener_practica(id_materia)    # CU-11

extends Node

const RUTA_BD := "user://nullpointers_bd.json"
const PORCENTAJE_MINIMO := 70        # % necesario para completar un módulo (mockups / CU-03)

var bd: Dictionary = {}
var modulo_seleccionado: int = 1      # lo pone el mapa (CU-02) antes de abrir la actividad
## CU-08: materia cuyo mapa se muestra (la pone la pantalla de materias antes de abrir el mapa).
var materia_seleccionada: int = 1
## CU-11: materia cuya práctica se va a resolver (la pone el mapa antes de abrir la práctica).
var practica_materia: int = 1
## CU-09: estado de la sesión de repaso mientras se consulta la teoría (CU-04). Vacío = ninguna.
var repaso_en_pausa: Dictionary = {}
## CU-04: escena a la que debe regresar la teoría ("" = al reto en pausa o al mapa).
var teoria_regreso: String = ""

## CU-04: la actividad (CU-03) deja aquí su estado antes de abrir la teoría,
## para regresar exactamente al punto donde se detuvo (paso 4 del CU-03).
## Vacío = no hay reto en pausa.
var reto_en_pausa: Dictionary = {}
## CU-04: id del reactivo cuya teoría se va a mostrar.
var reactivo_teoria: int = -1

func _ready() -> void:
	cargar_bd()


# =====================================================================
#  PERSISTENCIA (RNF-02: no perder progreso ante cierres inesperados)
# =====================================================================
func cargar_bd() -> void:
	if FileAccess.file_exists(RUTA_BD):
		var archivo := FileAccess.open(RUTA_BD, FileAccess.READ)
		var datos = JSON.parse_string(archivo.get_as_text())
		archivo.close()
		if datos is Dictionary and datos.has("modulos"):
			bd = datos
			# Migración de BD creadas con versiones anteriores
			var p: Dictionary = bd["perfil_jugador"]
			if not p.has("avatar_id"): p["avatar_id"] = "avatar_01"
			if not p.has("contrasena"): p["contrasena"] = ""
			if p["alias"] == "": p["alias"] = "estudiante_%04d" % (randi() % 10000)
			# Sprint 2: tablas nuevas (CU-04 / CU-05) para BD creadas en Sprint 1
			var inicial := _bd_inicial()
			# Los reactivos no guardan progreso: se refrescan para traer id_concepto
			if not bd["reactivos"].is_empty() and not bd["reactivos"][0].has("id_concepto"):
				bd["reactivos"] = inicial["reactivos"]
			if not bd.has("conceptos"): bd["conceptos"] = inicial["conceptos"]
			if not bd.has("insignias"): bd["insignias"] = inicial["insignias"]
			if not bd.has("teoria_consultas"): bd["teoria_consultas"] = 0
			_migrar_sprint3(inicial)
			evaluar_insignias()
			return
	# Primera vez (o archivo corrupto): crear BD inicial
	bd = _bd_inicial()
	guardar_bd()

func guardar_bd() -> void:
	var archivo := FileAccess.open(RUTA_BD, FileAccess.WRITE)
	archivo.store_string(JSON.stringify(bd, "\t"))
	archivo.close()

## Borra todo el progreso (útil para pruebas del Líder de Calidad).
func reiniciar_bd() -> void:
	bd = _bd_inicial()
	guardar_bd()


## Sprint 3: lleva una BD de Sprint 1/2 al esquema con materias, errores,
## pistas y prácticas SIN perder el progreso ya guardado.
func _migrar_sprint3(inicial: Dictionary) -> void:
	# CU-08: catálogo de materias y módulos nuevos (los 8 originales son de la materia 1)
	if not bd.has("materias"):
		bd["materias"] = inicial["materias"]
		bd["ultima_materia"] = 1
	for m in bd["modulos"]:
		if not m.has("id_materia"):
			m["id_materia"] = 1
	for m_ini in inicial["modulos"]:
		if obtener_modulo(int(m_ini["id"])).is_empty():
			bd["modulos"].append(m_ini)
	# Reactivos y conceptos no guardan progreso: se completan con los nuevos
	for r in inicial["reactivos"]:
		if obtener_reactivo(int(r["id"])).is_empty():
			bd["reactivos"].append(r)
	for c in inicial["conceptos"]:
		var existe := false
		for c2 in bd["conceptos"]:
			if c2["id"] == c["id"]:
				existe = true
				break
		if not existe:
			bd["conceptos"].append(c)
	# CU-05: insignias nuevas y textos actualizados (se conserva si ya se obtuvo)
	for ins_ini in inicial["insignias"]:
		var encontrada: Dictionary = {}
		for ins in bd["insignias"]:
			if ins["id"] == ins_ini["id"]:
				encontrada = ins
				break
		if encontrada.is_empty():
			bd["insignias"].append(ins_ini)
		else:
			encontrada["titulo"] = ins_ini["titulo"]
			encontrada["descripcion"] = ins_ini["descripcion"]
			encontrada["condicion"] = ins_ini["condicion"]
	# CU-09 / CU-10 / CU-11
	if not bd.has("errores"): bd["errores"] = []
	for i in bd["intentos_modulo"]:
		if not i.has("pistas"): i["pistas"] = 0
	if not bd.has("practicas"): bd["practicas"] = inicial["practicas"]
	if not bd.has("intentos_practica"): bd["intentos_practica"] = []
	guardar_bd()


# =====================================================================
#  CU-08: ELEGIR MATERIA
# =====================================================================
func obtener_materias() -> Array:
	return bd["materias"]

func obtener_materia(id_materia: int) -> Dictionary:
	for mat in bd["materias"]:
		if int(mat["id"]) == id_materia:
			return mat
	return {}

## Módulos de una materia (en orden). Con id_materia = -1 regresa todos.
func obtener_modulos_materia(id_materia: int) -> Array:
	var lista: Array = []
	for m in bd["modulos"]:
		if id_materia < 0 or int(m.get("id_materia", 1)) == id_materia:
			lista.append(m)
	return lista

func modulos_completados_materia(id_materia: int) -> int:
	var total := 0
	for m in obtener_modulos_materia(id_materia):
		if m["estado"] == "completado":
			total += 1
	return total

## Resumen de cada materia para el catálogo (paso 2 del CU-08):
## nombre, módulos completados/total, porcentaje de avance y si está dominada.
func obtener_catalogo_materias() -> Array:
	var catalogo: Array = []
	for mat in bd["materias"]:
		var id_mat := int(mat["id"])
		var mods := obtener_modulos_materia(id_mat)
		var completados := modulos_completados_materia(id_mat)
		var porcentaje := 0
		if not mods.is_empty():
			porcentaje = int(round(float(completados) / float(mods.size()) * 100.0))
		var fila: Dictionary = mat.duplicate()
		fila["modulos_totales"] = mods.size()
		fila["modulos_completados"] = completados
		fila["porcentaje"] = porcentaje
		fila["sin_iniciar"] = completados == 0 and not _materia_tiene_intentos(id_mat)
		fila["dominada"] = materia_dominada(id_mat)
		fila["es_ultima"] = id_mat == int(bd.get("ultima_materia", 1))
		catalogo.append(fila)
	return catalogo

func _materia_tiene_intentos(id_materia: int) -> bool:
	for i in bd["intentos_modulo"]:
		var m := obtener_modulo(int(i["id_modulo"]))
		if not m.is_empty() and int(m.get("id_materia", 1)) == id_materia:
			return true
	return false

## La materia visitada por última vez ("Continuar en…", flujo alternativo 2 del CU-08).
func obtener_ultima_materia() -> Dictionary:
	return obtener_materia(int(bd.get("ultima_materia", 1)))

## Paso 4 del CU-08: el estudiante eligió una materia; se recuerda para la próxima vez.
func seleccionar_materia(id_materia: int) -> void:
	materia_seleccionada = id_materia
	bd["ultima_materia"] = id_materia
	guardar_bd()

## El siguiente módulo jugable (desbloqueado) de una materia, para el menú.
func siguiente_modulo_materia(id_materia: int) -> Dictionary:
	for m in obtener_modulos_materia(id_materia):
		if m["estado"] == "desbloqueado":
			return m
	return {}

## Siguiente módulo de la misma materia (o {} si es el último).
func siguiente_modulo_de(id_modulo: int) -> Dictionary:
	var actual := obtener_modulo(id_modulo)
	if actual.is_empty():
		return {}
	var mods := obtener_modulos_materia(int(actual.get("id_materia", 1)))
	for k in mods.size():
		if int(mods[k]["id"]) == id_modulo:
			return mods[k + 1] if k + 1 < mods.size() else {}
	return {}


# =====================================================================
#  CU-01: EDITAR PERFIL (SRS 1.1: el perfil se crea automáticamente)
# =====================================================================
const ALIAS_MIN := 3
const ALIAS_MAX := 20
const CONTRASENA_MIN := 4
const CONTRASENA_MAX := 8
const AVATARES := ["avatar_01", "avatar_02", "avatar_03", "avatar_04", "avatar_05", "avatar_06"]

func existe_perfil() -> bool:
	return bd["perfil_jugador"]["alias"] != ""

func obtener_perfil() -> Dictionary:
	return bd["perfil_jugador"]

## Valida el alias según el SRS: no vacío, de 3 a 20 caracteres.
func alias_valido(alias: String) -> bool:
	var n := alias.strip_edges().length()
	return n >= ALIAS_MIN and n <= ALIAS_MAX

## Valida la contraseña: solo dígitos, de 4 a 8.
func contrasena_valida(c: String) -> bool:
	return c.length() >= CONTRASENA_MIN and c.length() <= CONTRASENA_MAX and c.is_valid_int() and not c.begins_with("-")

## Compatibilidad: crea/renombra el perfil (el perfil ya existe por defecto).
func crear_perfil(alias: String) -> bool:
	return actualizar_nombre(alias)

## Cambia el alias. Regresa false si no cumple 3-20 caracteres.
func actualizar_nombre(nuevo_alias: String) -> bool:
	nuevo_alias = nuevo_alias.strip_edges()
	if not alias_valido(nuevo_alias):
		return false
	bd["perfil_jugador"]["alias"] = nuevo_alias
	guardar_bd()
	return true

## Cambia el avatar (debe ser uno del catálogo Avatar.CATALOGO).
func actualizar_avatar(avatar_id: String) -> bool:
	if not avatar_id in AVATARES:
		return false
	bd["perfil_jugador"]["avatar_id"] = avatar_id
	guardar_bd()
	return true

## Guarda la contraseña si ambas coinciden y son válidas (4-8 dígitos).
func actualizar_contrasena(c1: String, c2: String) -> bool:
	if c1 != c2 or not contrasena_valida(c1):
		return false
	bd["perfil_jugador"]["contrasena"] = c1
	guardar_bd()
	return true

func tiene_contrasena() -> bool:
	return bd["perfil_jugador"].get("contrasena", "") != ""

func obtener_puntos_totales() -> int:
	return int(bd["perfil_jugador"]["puntos_totales"])


# =====================================================================
#  CU-02: SELECCIONAR MÓDULO DE APRENDIZAJE (mapa 2D)
# =====================================================================
func obtener_modulos() -> Array:
	return bd["modulos"]

func obtener_modulo(id_modulo: int) -> Dictionary:
	for m in bd["modulos"]:
		if int(m["id"]) == id_modulo:
			return m
	return {}

func modulos_completados() -> int:
	var total := 0
	for m in bd["modulos"]:
		if m["estado"] == "completado":
			total += 1
	return total

## El siguiente módulo que el alumno puede jugar (para "Siguiente: Módulo 3" del menú).
func siguiente_modulo() -> Dictionary:
	for m in bd["modulos"]:
		if m["estado"] == "desbloqueado":
			return m
	return {}


# =====================================================================
#  CU-03: RESOLVER ACTIVIDAD DE APRENDIZAJE
# =====================================================================
func obtener_reactivos(id_modulo: int) -> Array:
	var lista: Array = []
	for r in bd["reactivos"]:
		if int(r["id_modulo"]) == id_modulo:
			lista.append(r)
	return lista

func obtener_intentos(id_modulo: int) -> Array:
	var lista: Array = []
	for i in bd["intentos_modulo"]:
		if int(i["id_modulo"]) == id_modulo:
			lista.append(i)
	return lista

## Registra un intento terminado. Regresa un Dictionary con todo lo que
## necesita la pantalla de resultados de los mockups.
##   puntos_reto  = puntos acumulados en el intento ya con los descuentos de pistas (CU-10);
##                  -1 = calcularlos a partir de los aciertos (sin pistas).
##   pistas       = número de pistas usadas en el intento (CU-10).
func registrar_intento(id_modulo: int, aciertos: int, puntos_reto: int = -1, pistas: int = 0) -> Dictionary:
	var modulo := obtener_modulo(id_modulo)
	if modulo.is_empty():
		push_error("Módulo %d no existe" % id_modulo)
		return {}

	var total_preguntas := obtener_reactivos(id_modulo).size()
	if total_preguntas == 0:
		total_preguntas = int(modulo["num_preguntas"])

	var porcentaje := int(round(float(aciertos) / float(total_preguntas) * 100.0))
	var puntos_maximos := int(modulo["puntos_maximos"])
	var puntos := int(round(float(aciertos) / float(total_preguntas) * puntos_maximos))
	if puntos_reto >= 0:
		puntos = mini(puntos_reto, puntos)        # CU-10: los puntos del intento reflejan los descuentos
	var completado := porcentaje >= PORCENTAJE_MINIMO
	var mejor_previo := int(modulo["mejor_puntaje"])          # -1 = sin intentos
	var puntos_previos := int(modulo["puntos_obtenidos"])

	# 1) Guardar el intento en la tabla intentos_modulo
	bd["intentos_modulo"].append({
		"id": bd["intentos_modulo"].size() + 1,
		"id_modulo": id_modulo,
		"fecha": Time.get_datetime_string_from_system(),
		"aciertos": aciertos,
		"total": total_preguntas,
		"porcentaje": porcentaje,
		"puntos": puntos,
		"completado": completado,
		"pistas": pistas,                 # CU-10: postcondición "el intento registra las pistas usadas"
	})

	# 2) Conservar el mejor puntaje ("Se conserva tu mejor puntaje")
	var puntos_sumados := 0
	if porcentaje > mejor_previo:
		modulo["mejor_puntaje"] = porcentaje
	if completado and puntos > puntos_previos:
		puntos_sumados = puntos - puntos_previos      # solo la mejora cuenta al total
		modulo["puntos_obtenidos"] = puntos
		bd["perfil_jugador"]["puntos_totales"] = obtener_puntos_totales() + puntos_sumados

	# 3) Marcar completado y desbloquear el siguiente DE LA MISMA MATERIA (regla del CU-08)
	var siguiente_desbloqueado: Dictionary = {}
	if completado:
		modulo["estado"] = "completado"
		var siguiente := siguiente_modulo_de(id_modulo)
		if not siguiente.is_empty() and siguiente["estado"] == "bloqueado":
			siguiente["estado"] = "desbloqueado"
			siguiente_desbloqueado = siguiente

	# 4) CU-11 paso 1: la práctica se desbloquea al completar todos los módulos de la materia
	var id_materia := int(modulo.get("id_materia", 1))
	var practica_desbloqueada := completado and siguiente_desbloqueado.is_empty() \
		and practica_disponible(id_materia) and int(obtener_practica_estado(id_materia)["intentos"]) == 0

	# 5) Insignias que se desbloquean con este intento (CU-05)
	var insignias_nuevas := evaluar_insignias()
	guardar_bd()

	return {
		"porcentaje": porcentaje,
		"puntos": puntos,
		"puntos_maximos": puntos_maximos,
		"intentos": obtener_intentos(id_modulo).size(),
		"completado": completado,
		"mejor_previo": mejor_previo,
		"puntos_sumados": puntos_sumados,
		"puntos_totales": obtener_puntos_totales(),
		"siguiente_desbloqueado": siguiente_desbloqueado,
		"insignias_nuevas": insignias_nuevas,
		"practica_desbloqueada": practica_desbloqueada,
	}


# =====================================================================
#  CU-09: REPASAR MIS ERRORES
# =====================================================================
const REPASO_MAXIMO := 10            # máximo de preguntas por sesión de repaso (regla del CU-09)

## Paso 6 (alt.) del CU-03: una pregunta respondida incorrectamente entra a la
## lista de errores. Si ya estaba corregida en un repaso, vuelve a la lista.
func registrar_error(id_reactivo: int) -> void:
	var r := obtener_reactivo(id_reactivo)
	if r.is_empty():
		return
	for e in bd["errores"]:
		if int(e["id_reactivo"]) == id_reactivo:
			e["corregida"] = false
			e["fecha_fallo"] = Time.get_datetime_string_from_system()
			guardar_bd()
			return
	bd["errores"].append({
		"id_reactivo": id_reactivo,
		"id_modulo": int(r["id_modulo"]),
		"fecha_fallo": Time.get_datetime_string_from_system(),
		"corregida": false,
		"fecha_repaso": "",
	})
	guardar_bd()

## Preguntas pendientes de repaso (falladas y aún no acertadas en repaso).
## Con id_materia >= 0 solo las de esa materia.
func obtener_errores_pendientes(id_materia: int = -1) -> Array:
	var lista: Array = []
	for e in bd["errores"]:
		if e["corregida"]:
			continue
		var m := obtener_modulo(int(e["id_modulo"]))
		if m.is_empty():
			continue
		if id_materia >= 0 and int(m.get("id_materia", 1)) != id_materia:
			continue
		lista.append(e)
	return lista

## Paso 2 del CU-09: errores agrupados por materia y módulo, con conteos.
func obtener_resumen_errores() -> Array:
	var resumen: Array = []
	for mat in bd["materias"]:
		var id_mat := int(mat["id"])
		var pendientes := obtener_errores_pendientes(id_mat)
		if pendientes.is_empty():
			continue
		var por_modulo: Dictionary = {}
		for e in pendientes:
			var id_mod := int(e["id_modulo"])
			por_modulo[id_mod] = int(por_modulo.get(id_mod, 0)) + 1
		var modulos_fila: Array = []
		for id_mod in por_modulo.keys():
			var m := obtener_modulo(int(id_mod))
			modulos_fila.append({"id": int(id_mod), "nombre": m.get("nombre", ""), "errores": por_modulo[id_mod]})
		resumen.append({
			"id_materia": id_mat,
			"materia": mat["nombre"],
			"color": mat["color"],
			"total": pendientes.size(),
			"modulos": modulos_fila,
		})
	return resumen

## Paso 6 del CU-09: resultado de una pregunta repasada.
## Acierto → la pregunta se marca "corregida" y sale de la lista; fallo → permanece.
## NO otorga puntos ni toca el mejor puntaje del módulo (regla del CU-09).
func registrar_repaso(id_reactivo: int, acierto: bool) -> void:
	for e in bd["errores"]:
		if int(e["id_reactivo"]) == id_reactivo:
			e["fecha_repaso"] = Time.get_datetime_string_from_system()
			if acierto:
				e["corregida"] = true
			break
	guardar_bd()

## Paso 9 del CU-09: cierra la sesión de repaso (persistir + insignia si la lista quedó vacía).
func terminar_repaso() -> Array:
	var nuevas := evaluar_insignias()
	guardar_bd()
	return nuevas


# =====================================================================
#  CU-10: PEDIR UNA PISTA
# =====================================================================
## Costo de cada pista como fracción de los puntos de la pregunta (regla del CU-10).
const COSTO_PISTAS := {"recordar": 0.25, "descartar": 0.50}

func costo_pista(tipo: String) -> float:
	return float(COSTO_PISTAS.get(tipo, 0.0))

## Texto de la pista "Recordar el concepto": una frase del concepto asociado.
## Regresa "" si el reactivo no tiene concepto (flujo alternativo 2 del CU-10).
func texto_pista_concepto(id_reactivo: int) -> String:
	var c := obtener_concepto(id_reactivo)
	if c.is_empty():
		return ""
	var truco: String = str(c.get("truco", ""))
	if truco != "":
		return truco
	var expl: String = str(c.get("explicacion", ""))
	var punto := expl.find(". ")
	return expl.substr(0, punto + 1) if punto > 0 else expl

## Índice de una opción incorrecta que se puede descartar (-1 si no aplica:
## pregunta de dos opciones, flujo alternativo 3 del CU-10).
func opcion_a_descartar(id_reactivo: int) -> int:
	var r := obtener_reactivo(id_reactivo)
	if r.is_empty() or r["opciones"].size() <= 2:
		return -1
	var correcta := int(r["respuesta_correcta"])
	var candidatas: Array = []
	for i in r["opciones"].size():
		if i != correcta:
			candidatas.append(i)
	return candidatas[randi() % candidatas.size()]


# =====================================================================
#  CU-04: VER TEORÍA
# =====================================================================
func obtener_reactivo(id_reactivo: int) -> Dictionary:
	for r in bd["reactivos"]:
		if int(r["id"]) == id_reactivo:
			return r
	return {}

## Busca en almacenamiento local el concepto asociado a la pregunta o puzzle.
## Regresa {} si no hay concepto asociado (flujo alternativo "sin concepto").
func obtener_concepto(id_reactivo: int) -> Dictionary:
	var r := obtener_reactivo(id_reactivo)
	if r.is_empty() or r.get("id_concepto", "") == "":
		return {}
	for c in bd["conceptos"]:
		if c["id"] == r["id_concepto"]:
			return c
	return {}

## Concepto por su id (CU-11: "Ver teoría" dentro de la práctica).
func obtener_concepto_por_id(id_concepto: String) -> Dictionary:
	for c in bd["conceptos"]:
		if c["id"] == id_concepto:
			return c
	return {}

## Cuenta las consultas de teoría (solo para la insignia "Estudioso";
## no altera puntaje ni intentos, como exige la postcondición del CU-04).
func registrar_consulta_teoria() -> void:
	bd["teoria_consultas"] = int(bd.get("teoria_consultas", 0)) + 1
	evaluar_insignias()
	guardar_bd()


# =====================================================================
#  CU-05: VER INSIGNIAS
# =====================================================================
func obtener_insignias() -> Array:
	return bd["insignias"]

func insignias_obtenidas() -> int:
	var n := 0
	for i in bd["insignias"]:
		if i["obtenida"]:
			n += 1
	return n

## Revisa la condición de cada insignia contra el progreso actual y marca
## las que se acaban de cumplir. Regresa la lista de insignias recién obtenidas.
## No se usa guardar_bd aquí: lo hace quien llama (registrar_intento / cargar_bd).
func evaluar_insignias() -> Array:
	var nuevas: Array = []
	var completados := modulos_completados()
	var intentos: Array = bd["intentos_modulo"]
	var total_modulos: int = bd["modulos"].size()

	var hay_perfecto := false        # algún intento con 100 %
	var hay_puzzle_perfecto := false
	var hay_requerimientos := false
	for i in intentos:
		if int(i["porcentaje"]) >= 100:
			hay_perfecto = true
			var m := obtener_modulo(int(i["id_modulo"]))
			if not m.is_empty() and m["tipo"] == "puzzle":
				hay_puzzle_perfecto = true
	var m3 := obtener_modulo(3)
	hay_requerimientos = not m3.is_empty() and m3["estado"] == "completado"

	var todos_perfectos := total_modulos > 0
	for m in bd["modulos"]:
		if int(m["mejor_puntaje"]) < 100:
			todos_perfectos = false

	var racha := 0      # módulos consecutivos completados desde el 1 (materia 1)
	for m in obtener_modulos_materia(1):
		if m["estado"] == "completado":
			racha += 1
		else:
			break

	# Sprint 3 ---------------------------------------------------------
	# CU-10: algún módulo completado sin usar pistas
	var hay_sin_pistas := false
	for i in intentos:
		if bool(i["completado"]) and int(i.get("pistas", 0)) == 0:
			hay_sin_pistas = true
			break
	# CU-09: hubo errores y la lista de pendientes quedó vacía
	var errores: Array = bd.get("errores", [])
	var lista_vaciada := not errores.is_empty() and obtener_errores_pendientes().is_empty()
	# CU-11: al menos una materia dominada
	var hay_dominada := materias_dominadas() >= 1

	for ins in bd["insignias"]:
		if ins["obtenida"]:
			continue
		var cumple := false
		match ins["id"]:
			"primer_paso":     cumple = completados >= 1
			"punteria":        cumple = hay_perfecto
			"armador":         cumple = hay_puzzle_perfecto
			"estudioso":       cumple = int(bd.get("teoria_consultas", 0)) >= 5
			"racha":           cumple = racha >= 3
			"constante":       cumple = intentos.size() >= 10
			"analista":        cumple = hay_requerimientos
			"ingeniero":       cumple = completados >= total_modulos
			"perfeccionista":  cumple = todos_perfectos
			"repasador":       cumple = lista_vaciada            # CU-09
			"sin_pistas":      cumple = hay_sin_pistas           # CU-10
			"dominio":         cumple = hay_dominada             # CU-11
		if cumple:
			ins["obtenida"] = true
			ins["fecha_obtencion"] = Time.get_datetime_string_from_system()
			nuevas.append(ins)
	return nuevas


# =====================================================================
#  CU-11: RESOLVER PRÁCTICA DE INGENIERO
# =====================================================================
const PUNTOS_PRACTICA := 100

## Definición (escenario + ejercicios) de la práctica de una materia; {} si no tiene.
func obtener_practica(id_materia: int) -> Dictionary:
	for p in bd["practicas"]:
		if int(p["id_materia"]) == id_materia:
			return p
	return {}

## Progreso guardado de la práctica: intentos, mejor porcentaje/puntos y si la materia está dominada.
func obtener_practica_estado(id_materia: int) -> Dictionary:
	var p := obtener_practica(id_materia)
	if p.is_empty():
		return {"intentos": 0, "mejor_porcentaje": -1, "mejor_puntos": 0, "dominada": false}
	return {
		"intentos": int(p.get("intentos", 0)),
		"mejor_porcentaje": int(p.get("mejor_porcentaje", -1)),
		"mejor_puntos": int(p.get("mejor_puntos", 0)),
		"dominada": bool(p.get("dominada", false)),
	}

## Precondición del CU-11: todos los módulos de la materia completados (≥ 70 %).
func practica_disponible(id_materia: int) -> bool:
	var mods := obtener_modulos_materia(id_materia)
	if mods.is_empty() or obtener_practica(id_materia).is_empty():
		return false
	return modulos_completados_materia(id_materia) >= mods.size()

func materia_dominada(id_materia: int) -> bool:
	return bool(obtener_practica_estado(id_materia)["dominada"])

func materias_dominadas() -> int:
	var n := 0
	for p in bd["practicas"]:
		if p.get("dominada", false):
			n += 1
	return n

## Paso 9 del CU-11: guarda el intento de la práctica, actualiza la puntuación
## total y, si el porcentaje es ≥ 70 %, marca la materia como "Dominada".
## Al rejugar una práctica dominada, el intento solo se guarda si supera al mejor (alt. 4).
func registrar_intento_practica(id_materia: int, piezas_correctas: int, piezas_totales: int) -> Dictionary:
	var p := obtener_practica(id_materia)
	if p.is_empty():
		push_error("La materia %d no tiene práctica" % id_materia)
		return {}
	var porcentaje := int(round(float(piezas_correctas) / float(maxi(piezas_totales, 1)) * 100.0))
	var puntos := int(round(float(piezas_correctas) / float(maxi(piezas_totales, 1)) * PUNTOS_PRACTICA))
	var aprobada := porcentaje >= PORCENTAJE_MINIMO
	var mejor_previo := int(p.get("mejor_porcentaje", -1))
	var puntos_previos := int(p.get("mejor_puntos", 0))
	var ya_dominada := bool(p.get("dominada", false))
	var supera := porcentaje > mejor_previo

	var guardado := not ya_dominada or supera
	if guardado:
		bd["intentos_practica"].append({
			"id": bd["intentos_practica"].size() + 1,
			"id_materia": id_materia,
			"fecha": Time.get_datetime_string_from_system(),
			"correctas": piezas_correctas,
			"total": piezas_totales,
			"porcentaje": porcentaje,
			"puntos": puntos,
			"aprobada": aprobada,
		})
		p["intentos"] = int(p.get("intentos", 0)) + 1

	var puntos_sumados := 0
	if supera:
		p["mejor_porcentaje"] = porcentaje
	if aprobada and puntos > puntos_previos:
		puntos_sumados = puntos - puntos_previos
		p["mejor_puntos"] = puntos
		bd["perfil_jugador"]["puntos_totales"] = obtener_puntos_totales() + puntos_sumados
	var recien_dominada := aprobada and not ya_dominada
	if aprobada:
		p["dominada"] = true

	var insignias_nuevas := evaluar_insignias()
	guardar_bd()
	return {
		"porcentaje": porcentaje,
		"puntos": puntos,
		"puntos_maximos": PUNTOS_PRACTICA,
		"aprobada": aprobada,
		"dominada": bool(p["dominada"]),
		"recien_dominada": recien_dominada,
		"mejor_previo": mejor_previo,
		"guardado": guardado,
		"intentos": int(p.get("intentos", 0)),
		"puntos_sumados": puntos_sumados,
		"puntos_totales": obtener_puntos_totales(),
		"insignias_nuevas": insignias_nuevas,
	}


# =====================================================================
#  CU-06: VER PROGRESO
# =====================================================================
## Lee el historial de intentos y regresa todo lo que muestra la pantalla
## "Mi progreso": puntuación total, módulos completados/total, conceptos
## dominados (mejor puntaje >= 70 %) y áreas de mejora (intentados con < 70 %).
func obtener_progreso() -> Dictionary:
	var dominados: Array = []
	var mejora: Array = []
	for m in bd["modulos"]:
		var mejor := int(m["mejor_puntaje"])
		if mejor < 0:
			continue                       # sin intentos: no aparece en ninguna lista
		var intentos_mod := obtener_intentos(int(m["id"]))
		var mejor_puntos := 0              # puntos del mejor intento (aunque no haya completado)
		for i in intentos_mod:
			mejor_puntos = maxi(mejor_puntos, int(i["puntos"]))
		var materia := obtener_materia(int(m.get("id_materia", 1)))
		var fila := {
			"id": int(m["id"]),
			"nombre": m["nombre"],
			"materia": materia.get("nombre", ""),
			"mejor_porcentaje": mejor,
			"mejor_puntos": mejor_puntos,
			"intentos": intentos_mod.size(),
		}
		if mejor >= PORCENTAJE_MINIMO:
			dominados.append(fila)
		else:
			mejora.append(fila)
	return {
		"puntuacion_total": obtener_puntos_totales(),
		"modulos_completados": modulos_completados(),
		"modulos_totales": bd["modulos"].size(),
		"total_intentos": bd["intentos_modulo"].size(),
		"tiene_intentos": not bd["intentos_modulo"].is_empty(),
		"dominados": dominados,
		"areas_mejora": mejora,
		"errores_pendientes": obtener_errores_pendientes().size(),     # CU-09
		"materias_dominadas": materias_dominadas(),                      # CU-11
		"materias_totales": bd["materias"].size(),
	}


# =====================================================================
#  DATOS INICIALES (los 8 módulos y preguntas de los Mockups)
# =====================================================================
func _bd_inicial() -> Dictionary:
	return {
		"perfil_jugador": {
			"alias": "estudiante_%04d" % (randi() % 10000),   # perfil creado automáticamente (CU-01, SRS 1.1)
			"avatar_id": "avatar_01",
			"contrasena": "",
			"puntos_totales": 0,
			"fecha_creacion": Time.get_datetime_string_from_system(),
		},
		# ---- CU-08: catálogo de materias del área de ingeniería de software ----
		"materias": [
			_materia(1, "Introducción a la Ingeniería de Software", "Intro. a Ing. de Software",
				"Fundamentos, ciclo de vida, requerimientos, UML, diseño, pruebas, métricas y Scrum.", "libro", "#2F55E6"),
			_materia(2, "Proceso de Software en Equipo", "Proceso en Equipo (TSP)",
				"Roles, lanzamiento, planeación, estimación y seguimiento con valor ganado.", "grafica", "#178A4C"),
			_materia(3, "Arquitectura y Diseño de Software", "Arquitectura y Diseño",
				"Estilos arquitectónicos, patrones de diseño y principios SOLID.", "puzzle", "#7C3AED"),
		],
		"ultima_materia": 1,
		"modulos": [
			# Materia 1 · Introducción a la Ingeniería de Software (Sprint 1 y 2)
			_modulo(1, "Fundamentos", "quiz", "5 preguntas sobre qué es la ingeniería de software.", "desbloqueado"),
			_modulo(2, "Ciclo de vida", "quiz", "5 preguntas sobre modelos de ciclo de vida."),
			_modulo(3, "Requerimientos de software", "quiz", "5 preguntas sobre requerimientos funcionales y no funcionales."),
			_modulo(4, "Modelado con UML", "quiz", "5 preguntas sobre diagramas UML."),
			_modulo(5, "Diseño", "puzzle", "Acertijos de diseño y arquitectura."),
			_modulo(6, "Pruebas", "quiz", "5 preguntas sobre pruebas de software."),
			_modulo(7, "Métricas", "puzzle", "Acertijos sobre métricas y estimación."),
			_modulo(8, "Gestión ágil", "quiz", "5 preguntas sobre Scrum y metodologías ágiles."),
			# Materia 2 · Proceso de Software en Equipo (Sprint 3, CU-08)
			_modulo(9, "Roles y lanzamiento", "quiz", "5 preguntas sobre el TSP, sus roles y el lanzamiento del equipo.", "desbloqueado", 2),
			_modulo(10, "Planeación y estimación", "quiz", "5 preguntas sobre horas de tarea, valor planeado y estimación.", "bloqueado", 2),
			_modulo(11, "Valor ganado", "quiz", "5 preguntas sobre seguimiento del plan con EV, PV, SPI y CPI.", "bloqueado", 2),
			# Materia 3 · Arquitectura y Diseño de Software (Sprint 3, CU-08)
			_modulo(12, "Estilos arquitectónicos", "quiz", "5 preguntas sobre monolitos, cliente-servidor, capas y microservicios.", "desbloqueado", 3),
			_modulo(13, "Patrones de diseño", "quiz", "5 preguntas sobre Observador, Estrategia, Fábrica y Adaptador.", "bloqueado", 3),
			_modulo(14, "Principios SOLID", "quiz", "5 preguntas sobre los cinco principios SOLID.", "bloqueado", 3),
		],
		"reactivos": [
			# ---- Módulo 1 · Fundamentos ----
			_reactivo(1, 1, "¿Qué es la ingeniería de software?",
				["Programar rápido sin planear", "Aplicar un enfoque sistemático y disciplinado al desarrollo de software", "Instalar sistemas operativos", "Diseñar hardware"], 1,
				"La ingeniería de software aplica principios de ingeniería al desarrollo, operación y mantenimiento del software.", "ing_software"),
			_reactivo(2, 1, "¿Cuál NO es una característica del software?",
				["Se desarrolla, no se fabrica", "No se desgasta físicamente", "Se oxida con el tiempo", "La mayoría se construye a la medida"], 2,
				"El software no se desgasta físicamente, pero sí se deteriora por cambios y falta de mantenimiento.", "caract_software"),
			_reactivo(3, 1, "¿Qué documento define QUÉ debe hacer el sistema?",
				["SRS", "Manual de usuario", "Plan de pruebas", "Diagrama de clases"], 0,
				"El SRS (Especificación de Requisitos de Software) describe qué debe hacer el sistema.", "srs"),
			_reactivo(4, 1, "La fase donde se corrige y mejora el software ya entregado se llama:",
				["Análisis", "Diseño", "Mantenimiento", "Codificación"], 2,
				"El mantenimiento ocurre después de la entrega e incluye correcciones y mejoras.", "mantenimiento"),
			_reactivo(5, 1, "¿Cuál es un estándar para procesos de software en equipos pequeños?",
				["ISO/IEC 29110", "HTML5", "IEEE 802.11", "USB 3.0"], 0,
				"ISO/IEC 29110 define perfiles de proceso para Very Small Entities (VSE).", "iso29110"),
			# ---- Módulo 3 · Requerimientos (del mockup) ----
			_reactivo(6, 3, "¿Qué es un requerimiento funcional?",
				["Una acción o servicio que el sistema debe realizar", "El color de la interfaz", "El tiempo de respuesta del sistema", "El presupuesto del proyecto"], 0,
				"Un requerimiento funcional describe lo que el sistema debe hacer.", "req_funcional"),
			_reactivo(7, 3, "¿Quién es la fuente principal de los requerimientos?",
				["El compilador", "Los stakeholders / cliente", "El servidor", "El sistema operativo"], 1,
				"Los requerimientos se obtienen de los interesados (stakeholders) del sistema.", "stakeholders"),
			_reactivo(8, 3, "¿Cuál de estos es un requerimiento no funcional?",
				["Responder en menos de 2 segundos", "Registrar un nuevo pedido", "Enviar correo al confirmar la compra", "Generar el reporte mensual de ventas"], 0,
				"Un requerimiento no funcional describe una cualidad del sistema (rendimiento, seguridad, usabilidad), no una acción.", "req_no_funcional"),
			_reactivo(9, 3, "La característica de un requerimiento de poder ser probado se llama:",
				["Ambigüedad", "Verificabilidad", "Redundancia", "Volatilidad"], 1,
				"Un requerimiento verificable puede comprobarse mediante una prueba.", "verificabilidad"),
			_reactivo(10, 3, "¿Qué actividad consiste en obtener los requerimientos del cliente?",
				["Elicitación", "Compilación", "Despliegue", "Refactorización"], 0,
				"La elicitación es la actividad de descubrir y recolectar los requerimientos.", "elicitacion"),
			# ---- Módulo 2 · Ciclo de vida ----
			_reactivo(11, 2, "¿Cuál es la primera fase del modelo en cascada?",
				["Pruebas", "Análisis de requerimientos", "Implementación", "Mantenimiento"], 1,
				"El modelo en cascada inicia con el análisis de requerimientos y avanza secuencialmente.", "cascada"),
			_reactivo(12, 2, "¿Qué modelo repite ciclos cortos entregando versiones funcionales?",
				["Cascada", "Iterativo e incremental", "Big Bang", "Modelo V"], 1,
				"Los modelos iterativos e incrementales entregan versiones funcionales en ciclos cortos.", "iterativo"),
			_reactivo(13, 2, "¿En qué modelo se construye un prototipo para validar requerimientos con el cliente?",
				["Prototipado", "Cascada", "Espiral puro", "RAD"], 0,
				"El modelo de prototipado construye versiones preliminares para validar con el usuario.", "prototipado"),
			_reactivo(14, 2, "El modelo en espiral se caracteriza por enfocarse en:",
				["La documentación", "El análisis de riesgos", "La velocidad de entrega", "Las pruebas unitarias"], 1,
				"Cada vuelta de la espiral incluye un análisis explícito de riesgos (Boehm).", "espiral"),
			_reactivo(15, 2, "¿Cuál de estos es un marco de trabajo ágil?",
				["Scrum", "Cascada", "Modelo V", "CMMI"], 0,
				"Scrum es un marco ágil basado en sprints, roles y eventos definidos.", "agil"),
			# ---- Módulo 4 · Modelado con UML ----
			_reactivo(16, 4, "¿Qué diagrama UML muestra los actores y las funcionalidades del sistema?",
				["Diagrama de clases", "Diagrama de casos de uso", "Diagrama de despliegue", "Diagrama de paquetes"], 1,
				"El diagrama de casos de uso representa actores y las funciones que el sistema les ofrece.", "casos_uso"),
			_reactivo(17, 4, "¿Qué diagrama representa la estructura estática con atributos y métodos?",
				["Diagrama de clases", "Diagrama de secuencia", "Diagrama de actividad", "Diagrama de estados"], 0,
				"El diagrama de clases describe la estructura estática: clases, atributos, métodos y relaciones.", "diag_clases"),
			_reactivo(18, 4, "¿Qué diagrama muestra el intercambio de mensajes entre objetos en el tiempo?",
				["Diagrama de componentes", "Diagrama de secuencia", "Diagrama de objetos", "Diagrama de clases"], 1,
				"El diagrama de secuencia ordena en el tiempo los mensajes entre objetos.", "diag_secuencia"),
			_reactivo(19, 4, "En UML, la relación 'es un tipo de' se modela con:",
				["Asociación", "Dependencia", "Herencia (generalización)", "Agregación"], 2,
				"La generalización (herencia) expresa que una clase es un tipo especializado de otra.", "herencia"),
			_reactivo(20, 4, "¿Qué diagrama describe el flujo de trabajo paso a paso con decisiones?",
				["Diagrama de actividad", "Diagrama de despliegue", "Diagrama de clases", "Diagrama de paquetes"], 0,
				"El diagrama de actividad modela flujos de trabajo con acciones, decisiones y bifurcaciones.", "diag_actividad"),
			# ---- Módulo 5 · Diseño ----
			_reactivo(21, 5, "¿Qué principio busca que cada módulo tenga una sola responsabilidad?",
				["Acoplamiento", "Responsabilidad única", "Redundancia", "Herencia múltiple"], 1,
				"El principio de responsabilidad única (SRP) dice que un módulo debe tener una sola razón para cambiar.", "srp"),
			_reactivo(22, 5, "Un diseño con bajo acoplamiento y alta cohesión es:",
				["Difícil de mantener", "Deseable", "Imposible", "Más lento"], 1,
				"Bajo acoplamiento y alta cohesión facilitan el mantenimiento y la reutilización.", "acoplamiento"),
			_reactivo(23, 5, "¿Qué patrón separa la interfaz, la lógica y los datos?",
				["Singleton", "MVC / MVVM", "Observador", "Fábrica"], 1,
				"MVC y MVVM separan la vista, la lógica y el modelo de datos.", "mvc"),
			_reactivo(24, 5, "¿Qué patrón garantiza una única instancia de una clase?",
				["Singleton", "Adaptador", "Decorador", "Estrategia"], 0,
				"Singleton restringe la instanciación a un único objeto (como un Autoload en Godot).", "singleton"),
			_reactivo(25, 5, "La arquitectura en capas organiza el sistema en:",
				["Procesos paralelos", "Niveles con responsabilidades definidas", "Un solo archivo", "Hilos"], 1,
				"Cada capa (presentación, lógica, datos) tiene responsabilidades claras y se comunica con la adyacente.", "capas"),
			# ---- Módulo 6 · Pruebas ----
			_reactivo(26, 6, "¿Qué prueba verifica una función o clase de forma aislada?",
				["Prueba de sistema", "Prueba unitaria", "Prueba de aceptación", "Prueba de carga"], 1,
				"Las pruebas unitarias validan la unidad más pequeña de código de forma aislada.", "prueba_unitaria"),
			_reactivo(27, 6, "Las pruebas de caja negra se basan en:",
				["El código fuente", "Las entradas y salidas esperadas", "La cobertura de ramas", "El compilador"], 1,
				"La caja negra prueba el comportamiento externo sin conocer la implementación interna.", "caja_negra"),
			_reactivo(28, 6, "¿Qué prueba realiza el cliente para validar que el sistema cumple sus necesidades?",
				["Prueba de aceptación", "Prueba unitaria", "Prueba de integración", "Prueba de regresión"], 0,
				"La prueba de aceptación la realiza el cliente o usuario final antes de aprobar la entrega.", "aceptacion"),
			_reactivo(29, 6, "¿Qué prueba comprueba que un cambio no rompió lo que ya funcionaba?",
				["Prueba de humo", "Prueba de regresión", "Prueba alfa", "Prueba de estrés"], 1,
				"Las pruebas de regresión se repiten tras cada cambio para detectar errores reintroducidos.", "regresion"),
			_reactivo(30, 6, "Un caso de prueba debe incluir al menos:",
				["Entrada y resultado esperado", "El nombre del programador", "El costo", "El diagrama de Gantt"], 0,
				"Todo caso de prueba define datos de entrada, pasos y el resultado esperado.", "caso_prueba"),
			# ---- Módulo 7 · Métricas ----
			_reactivo(31, 7, "¿Qué mide la métrica 'líneas de código' (LOC)?",
				["La calidad", "El tamaño del software", "La seguridad", "La usabilidad"], 1,
				"LOC es una métrica de tamaño; no mide calidad ni complejidad por sí sola.", "loc"),
			_reactivo(32, 7, "La complejidad ciclomática mide:",
				["El número de caminos independientes del código", "El tamaño del equipo", "El tiempo de compilación", "La memoria usada"], 0,
				"McCabe definió la complejidad ciclomática como el número de caminos linealmente independientes.", "ciclomatica"),
			_reactivo(33, 7, "¿Qué técnica estima el tamaño funcional desde el punto de vista del usuario?",
				["Puntos de función", "Horas-hombre", "Velocidad de CPU", "Bugs por día"], 0,
				"Los puntos de función miden funcionalidad entregada al usuario, independiente del lenguaje.", "puntos_funcion"),
			_reactivo(34, 7, "El 'valor ganado' compara:",
				["Trabajo planificado contra trabajo realizado", "Salarios", "Versiones", "Errores"], 0,
				"El valor ganado (EV) relaciona el avance real contra lo planeado y lo gastado.", "valor_ganado"),
			_reactivo(35, 7, "¿Qué métrica ayuda a estimar la densidad de defectos?",
				["Defectos por KLOC", "Pulgadas de pantalla", "Número de reuniones", "Ancho de banda"], 0,
				"Defectos por cada mil líneas de código (KLOC) es una métrica clásica de calidad.", "densidad_defectos"),
			# ---- Módulo 8 · Gestión ágil ----
			_reactivo(36, 8, "¿Cómo se llama la iteración de tiempo fijo en Scrum?",
				["Fase", "Sprint", "Hito", "Release"], 1,
				"El sprint es la iteración de duración fija (1-4 semanas) en Scrum.", "sprint"),
			_reactivo(37, 8, "¿Quién prioriza el Product Backlog?",
				["Scrum Master", "Product Owner", "El equipo de pruebas", "El cliente final directamente"], 1,
				"El Product Owner es responsable de ordenar y priorizar el Product Backlog.", "product_owner"),
			_reactivo(38, 8, "¿Qué evento diario dura máximo 15 minutos?",
				["Sprint Review", "Daily Scrum", "Sprint Planning", "Retrospectiva"], 1,
				"El Daily Scrum es una reunión corta diaria para sincronizar al equipo.", "daily"),
			_reactivo(39, 8, "¿Qué tablero visualiza el flujo de trabajo en columnas (Por hacer, En curso, Hecho)?",
				["Gantt", "Kanban", "PERT", "Ishikawa"], 1,
				"El tablero Kanban muestra el flujo de trabajo y limita el trabajo en curso.", "kanban"),
			_reactivo(40, 8, "¿Qué evento sirve para que el equipo mejore su forma de trabajar?",
				["Sprint Retrospective", "Sprint Review", "Refinamiento", "Daily Scrum"], 0,
				"En la retrospectiva el equipo reflexiona sobre su proceso y acuerda mejoras.", "retrospectiva"),
			# ---- Módulo 9 · Roles y lanzamiento (TSP) ----
			_reactivo(41, 9, "¿Qué es el TSP (Team Software Process)?",
				["Un lenguaje de programación", "Un proceso para que equipos autodirigidos planeen, midan y mejoren su trabajo", "Una herramienta de control de versiones", "Un tipo de prueba de software"], 1,
				"El TSP guía a equipos pequeños para planear, dar seguimiento y mejorar su proceso con datos.", "tsp"),
			_reactivo(42, 9, "¿Qué rol del TSP coordina al equipo y da seguimiento al plan semana a semana?",
				["Líder de equipo", "Gerente de desarrollo", "Gerente de calidad", "Gerente de soporte"], 0,
				"El líder de equipo dirige las reuniones, motiva al equipo y vigila el avance del plan.", "roles_tsp"),
			_reactivo(43, 9, "¿Qué rol vigila que se cumplan los estándares y que se hagan las inspecciones?",
				["Gerente de planeación", "Gerente de calidad y proceso", "Gerente de desarrollo", "Líder de equipo"], 1,
				"El gerente de calidad y proceso cuida que el equipo siga el proceso y registre los defectos.", "roles_tsp"),
			_reactivo(44, 9, "El evento donde el equipo define metas, roles y plan al inicio del ciclo se llama:",
				["Retrospectiva", "Postmortem", "Lanzamiento (launch)", "Daily Scrum"], 2,
				"En el lanzamiento el equipo acuerda metas, asigna roles, estima y construye el plan del ciclo.", "lanzamiento"),
			_reactivo(45, 9, "¿Qué documento firma el equipo para fijar sus reglas de trabajo y compromisos?",
				["Manual de usuario", "Acuerdo de equipo", "Diagrama de Gantt", "Plan de pruebas"], 1,
				"El acuerdo de equipo (team agreement) establece horarios, comunicación, roles y sanciones.", "acuerdo_equipo"),
			# ---- Módulo 10 · Planeación y estimación ----
			_reactivo(46, 10, "¿En qué unidad se estima el esfuerzo de cada tarea en el plan del TSP?",
				["Horas de tarea", "Líneas de documentación", "Número de reuniones", "Puntos de historia"], 0,
				"Cada tarea del plan se estima en horas de tarea; con ellas se construye el calendario.", "horas_tarea"),
			_reactivo(47, 10, "¿Qué es el valor planeado (PV) de una tarea?",
				["Las horas reales que tomó", "El porcentaje del esfuerzo total del plan que representa", "El dinero que cuesta", "Su fecha de entrega"], 1,
				"PV = horas estimadas de la tarea / horas totales del plan × 100.", "valor_planeado"),
			_reactivo(48, 10, "Un equipo de 3 personas dispone de 10 h por semana cada una. Si el plan son 90 h, ¿cuántas semanas dura?",
				["1", "2", "3", "9"], 2,
				"30 h disponibles por semana × 3 semanas = 90 h.", "horas_tarea"),
			_reactivo(49, 10, "¿Qué método del PSP/TSP usa datos históricos para estimar tamaño y tiempo?",
				["PROBE", "SCRUM", "UML", "KLOC"], 0,
				"PROBE (PROxy Based Estimating) estima a partir de datos de proyectos anteriores.", "probe"),
			_reactivo(50, 10, "El diagrama de Gantt y el tablero de tareas sirven para:",
				["Compilar el código", "Visualizar el calendario y el avance de las tareas", "Medir la complejidad", "Probar la interfaz"], 1,
				"Gantt muestra tareas contra tiempo; el tablero muestra qué está por hacer, en curso y hecho.", "gantt"),
			# ---- Módulo 11 · Valor ganado ----
			_reactivo(51, 11, "¿Qué es el valor ganado (EV)?",
				["La suma del valor planeado de las tareas terminadas", "Las horas trabajadas", "El dinero recibido", "El número de tareas pendientes"], 0,
				"EV acumula el PV de cada tarea cuando ésta se termina al 100 %.", "valor_ganado_tsp"),
			_reactivo(52, 11, "Si al final de la semana PV = 60 % y EV = 45 %, el proyecto va:",
				["Adelantado", "Retrasado", "En tiempo", "Terminado"], 1,
				"EV < PV significa que se ha ganado menos valor del planeado: hay retraso.", "valor_ganado_tsp"),
			_reactivo(53, 11, "SPI = EV / PV. Un SPI de 1.2 significa que el equipo:",
				["Avanza más rápido de lo planeado", "Va retrasado", "Gasta de más", "Terminó el proyecto"], 0,
				"SPI > 1 indica más valor ganado que planeado: el equipo va adelantado.", "spi_cpi"),
			_reactivo(54, 11, "CPI = EV / AC. Un CPI menor que 1 significa que:",
				["Sobran horas", "Se gasta más esfuerzo del planeado por cada unidad de valor", "El plan es perfecto", "No hay defectos"], 1,
				"CPI < 1: el costo real (horas) supera lo planeado para el valor obtenido.", "spi_cpi"),
			_reactivo(55, 11, "¿Cuándo se registra el valor ganado de una tarea en el TSP?",
				["Al empezarla", "Cuando lleva 50 %", "Solo cuando está 100 % terminada", "Al final del proyecto"], 2,
				"En TSP una tarea aporta su valor solo al terminarse por completo; no hay crédito parcial.", "valor_ganado_tsp"),
			# ---- Módulo 12 · Estilos arquitectónicos ----
			_reactivo(56, 12, "¿Qué es la arquitectura de software?",
				["El código de la interfaz", "La estructura de alto nivel: componentes y sus relaciones", "La lista de requerimientos", "El manual de instalación"], 1,
				"La arquitectura define los componentes principales del sistema y cómo se comunican.", "arquitectura"),
			_reactivo(57, 12, "¿Qué estilo divide el sistema en un cliente que pide servicios y un servidor que responde?",
				["Cliente-servidor", "Monolito", "Tubería y filtros", "Pizarra"], 0,
				"En cliente-servidor los clientes hacen peticiones y el servidor centraliza datos y lógica.", "cliente_servidor"),
			_reactivo(58, 12, "¿Qué estilo divide la aplicación en servicios pequeños, independientes y desplegables por separado?",
				["Capas", "Monolito", "Microservicios", "Cliente-servidor"], 2,
				"Los microservicios son servicios pequeños con su propia base de datos y despliegue.", "microservicios"),
			_reactivo(59, 12, "Un monolito es:",
				["Una aplicación que se despliega como una sola unidad", "Un conjunto de servicios", "Una base de datos", "Un patrón de diseño"], 0,
				"En un monolito toda la funcionalidad vive en un solo ejecutable; es simple pero difícil de escalar.", "monolito"),
			_reactivo(60, 12, "¿Qué atributo de calidad mide qué tan fácil es modificar el sistema?",
				["Rendimiento", "Mantenibilidad", "Disponibilidad", "Seguridad"], 1,
				"La mantenibilidad es la facilidad para corregir, adaptar y mejorar el software.", "atributos_calidad"),
			# ---- Módulo 13 · Patrones de diseño ----
			_reactivo(61, 13, "Los patrones de diseño son:",
				["Soluciones probadas a problemas recurrentes de diseño", "Plantillas de interfaz", "Lenguajes de programación", "Pruebas automatizadas"], 0,
				"Un patrón describe una solución reutilizable a un problema de diseño que aparece una y otra vez.", "patrones"),
			_reactivo(62, 13, "¿Qué patrón notifica a varios objetos cuando otro cambia de estado?",
				["Singleton", "Observador", "Fábrica", "Adaptador"], 1,
				"El Observador mantiene una lista de suscriptores y les avisa de cada cambio.", "observador"),
			_reactivo(63, 13, "¿Qué patrón permite intercambiar algoritmos en tiempo de ejecución?",
				["Estrategia", "Decorador", "Singleton", "Compuesto"], 0,
				"Estrategia encapsula cada algoritmo en una clase intercambiable con la misma interfaz.", "estrategia"),
			_reactivo(64, 13, "¿Qué patrón crea objetos sin exponer al cliente la lógica de creación?",
				["Observador", "Adaptador", "Fábrica", "Estrategia"], 2,
				"La Fábrica centraliza la creación de objetos y devuelve la clase concreta adecuada.", "fabrica"),
			_reactivo(65, 13, "¿Qué patrón convierte la interfaz de una clase en otra que el cliente espera?",
				["Adaptador", "Singleton", "Observador", "Fachada"], 0,
				"El Adaptador envuelve una clase incompatible para que funcione con la interfaz esperada.", "adaptador"),
			# ---- Módulo 14 · Principios SOLID ----
			_reactivo(66, 14, "El principio abierto/cerrado (O de SOLID) dice que una clase debe estar:",
				["Abierta a la modificación y cerrada a la extensión", "Abierta a la extensión y cerrada a la modificación", "Siempre abierta", "Siempre cerrada"], 1,
				"Se agrega comportamiento extendiendo (herencia, interfaces), no modificando el código existente.", "ocp"),
			_reactivo(67, 14, "El principio de sustitución de Liskov (L) dice que:",
				["Una subclase debe poder usarse en lugar de su clase base sin romper el programa", "Toda clase debe tener un constructor", "Las clases no deben heredar", "Los métodos deben ser estáticos"], 0,
				"Si una subclase cambia el comportamiento esperado de la base, viola Liskov.", "lsp"),
			_reactivo(68, 14, "La segregación de interfaces (I) recomienda:",
				["Una sola interfaz gigante", "Interfaces pequeñas y específicas para cada cliente", "No usar interfaces", "Interfaces solo en la vista"], 1,
				"Ningún cliente debe depender de métodos que no usa.", "isp"),
			_reactivo(69, 14, "La inversión de dependencias (D) dice que los módulos de alto nivel deben depender de:",
				["Clases concretas", "La base de datos", "Abstracciones (interfaces)", "El sistema operativo"], 2,
				"Alto y bajo nivel dependen de abstracciones; así se puede cambiar la implementación sin tocar la lógica.", "dip"),
			_reactivo(70, 14, "¿Qué 'code smell' indica que una clase hace demasiadas cosas (viola la S de SOLID)?",
				["Método corto", "Clase Dios (God class)", "Nombre descriptivo", "Prueba unitaria"], 1,
				"Una clase Dios concentra demasiadas responsabilidades y es difícil de mantener y probar.", "srp"),
		],
		"intentos_modulo": [],
		"teoria_consultas": 0,
		# ---- CU-04: conceptos de teoría (uno por tema; los reactivos apuntan por id_concepto) ----
		"conceptos": [
			_concepto("ing_software", 1, "¿Qué es la ingeniería de software?",
				"La ingeniería de software es la aplicación de un enfoque sistemático, disciplinado y cuantificable al desarrollo, operación y mantenimiento del software. No se trata solo de programar: incluye planear, analizar, diseñar, probar y mantener.",
				["Enfoque sistemático", "Disciplina", "Calidad", "Mantenimiento"],
				"Si una actividad se hace con método, se mide y se puede repetir, es ingeniería; si se improvisa, no."),
			_concepto("caract_software", 1, "Características del software",
				"El software se desarrolla, no se fabrica; no se desgasta físicamente pero sí se deteriora por cambios mal hechos y falta de mantenimiento; y la mayoría se construye a la medida en vez de ensamblarse con piezas estándar.",
				["Se desarrolla", "No se desgasta", "Se deteriora", "A la medida"],
				"El hardware falla por uso; el software falla por cambios."),
			_concepto("srs", 1, "El documento SRS",
				"La Especificación de Requisitos de Software (SRS) describe QUÉ debe hacer el sistema y bajo qué restricciones, sin decir CÓMO se construye. Es el acuerdo entre el cliente y el equipo de desarrollo.",
				["Qué, no cómo", "Acuerdo con el cliente", "Base de las pruebas"],
				"Si una frase del SRS describe código o pantallas concretas, probablemente es diseño, no requisito."),
			_concepto("mantenimiento", 1, "Fase de mantenimiento",
				"El mantenimiento ocurre después de la entrega. Incluye corregir errores (correctivo), adaptarse a nuevos entornos (adaptativo), mejorar funciones (perfectivo) y prevenir fallas futuras (preventivo). Suele ser la fase más larga y costosa.",
				["Correctivo", "Adaptativo", "Perfectivo", "Preventivo"],
				"Todo lo que pasa después de que el cliente ya usa el sistema es mantenimiento."),
			_concepto("iso29110", 1, "ISO/IEC 29110",
				"ISO/IEC 29110 es un estándar de procesos de software para Entidades Muy Pequeñas (VSE, hasta 25 personas). Su perfil Básico define dos procesos: Gestión de Proyecto (PM) e Implementación de Software (SI).",
				["VSE", "Perfil Básico", "Proceso PM", "Proceso SI"],
				"Es un estándar pensado para equipos pequeños como el de esta materia."),
			_concepto("cascada", 2, "Modelo en cascada",
				"El modelo en cascada organiza el desarrollo en fases secuenciales: análisis de requerimientos, diseño, implementación, pruebas y mantenimiento. Cada fase inicia cuando termina la anterior, por lo que es rígido ante cambios.",
				["Requerimientos", "Diseño", "Implementación", "Pruebas", "Mantenimiento"],
				"Recuerda el orden pensando en que no puedes probar lo que no has programado ni programar lo que no has diseñado."),
			_concepto("iterativo", 2, "Modelos iterativos e incrementales",
				"En lugar de entregar todo al final, el sistema se construye en ciclos cortos. Cada iteración agrega un incremento funcional que el cliente puede usar y evaluar, lo que reduce el riesgo de construir algo que nadie quiere.",
				["Ciclos cortos", "Entregas funcionales", "Retroalimentación temprana"],
				"Iterativo = repetir el ciclo; incremental = cada vuelta suma algo usable."),
			_concepto("prototipado", 2, "Modelo de prototipado",
				"Se construye una versión preliminar (prototipo) para que el cliente la vea y valide los requerimientos antes de desarrollar el sistema definitivo. Es útil cuando los requisitos no están claros.",
				["Validar requisitos", "Requisitos poco claros", "Prototipo desechable"],
				"Si el cliente dice 'lo sabré cuando lo vea', necesitas un prototipo."),
			_concepto("espiral", 2, "Modelo en espiral",
				"Propuesto por Boehm, combina iteraciones con un análisis explícito de riesgos en cada vuelta: planear, analizar riesgos, desarrollar y evaluar. Es adecuado para proyectos grandes y con incertidumbre.",
				["Boehm", "Análisis de riesgos", "Iteraciones"],
				"Espiral = iterativo + riesgos."),
			_concepto("agil", 2, "Marcos de trabajo ágiles",
				"Los marcos ágiles (Scrum, Kanban, XP) priorizan entregas frecuentes, colaboración con el cliente y respuesta al cambio sobre seguir un plan rígido. Scrum organiza el trabajo en sprints con roles y eventos definidos.",
				["Scrum", "Kanban", "XP", "Manifiesto ágil"],
				"Cascada, Modelo V y CMMI no son ágiles: son modelos secuenciales o de madurez."),
			_concepto("req_funcional", 3, "Requerimientos funcionales",
				"Un requerimiento funcional describe QUÉ hace el sistema: una acción o servicio que ofrece al usuario, como registrar un pedido o generar un reporte. Se escribe normalmente con un verbo de acción.",
				["Acción del sistema", "Verbo de acción", "Servicio al usuario"],
				"Si puedes decir 'el sistema debe permitir…', es funcional."),
			_concepto("stakeholders", 3, "Fuentes de los requerimientos",
				"Los requerimientos se obtienen de los interesados o stakeholders: clientes, usuarios finales, expertos del dominio, reguladores y el propio equipo. Identificarlos a todos evita descubrir necesidades tarde.",
				["Cliente", "Usuarios", "Expertos", "Reguladores"],
				"Stakeholder = cualquiera a quien le afecte el sistema."),
			_concepto("req_no_funcional", 3, "Requerimientos no funcionales",
				"Un requerimiento no funcional describe CÓMO debe comportarse el sistema: una cualidad o restricción que aplica a todo el producto. Ejemplos: responder en menos de 2 segundos, funcionar sin internet, cifrar las contraseñas.",
				["Rendimiento", "Seguridad", "Usabilidad", "Disponibilidad", "Portabilidad"],
				"Si el requerimiento describe una medida, un límite o una cualidad, es no funcional; si describe una acción del usuario, es funcional."),
			_concepto("verificabilidad", 3, "Características de un buen requerimiento",
				"Un buen requerimiento es verificable (se puede probar), no ambiguo (una sola interpretación), completo, consistente y rastreable. 'El sistema debe ser rápido' no es verificable; 'responde en menos de 2 s' sí.",
				["Verificable", "No ambiguo", "Completo", "Consistente", "Rastreable"],
				"Pregúntate: ¿cómo escribiría la prueba de este requerimiento? Si no puedes, no es verificable."),
			_concepto("elicitacion", 3, "Elicitación de requerimientos",
				"La elicitación es la actividad de descubrir y recolectar los requerimientos con los stakeholders mediante entrevistas, cuestionarios, observación, talleres y análisis de documentos. Es el primer paso de la ingeniería de requerimientos.",
				["Entrevistas", "Cuestionarios", "Observación", "Talleres"],
				"Elicitar = sacar a la luz lo que el cliente necesita, aunque él mismo no lo sepa expresar."),
			_concepto("casos_uso", 4, "Diagrama de casos de uso",
				"Muestra los actores (personas o sistemas externos) y las funcionalidades que el sistema les ofrece (casos de uso). Las relaciones include y extend indican comportamiento compartido u opcional.",
				["Actor", "Caso de uso", "include", "extend"],
				"Responde a la pregunta: ¿quién usa el sistema y para qué?"),
			_concepto("diag_clases", 4, "Diagrama de clases",
				"Describe la estructura estática del sistema: clases con sus atributos y métodos, y las relaciones entre ellas (asociación, agregación, composición, herencia). Es la base del diseño orientado a objetos.",
				["Atributos", "Métodos", "Asociación", "Herencia"],
				"Es la 'foto' del sistema: qué hay, no qué pasa."),
			_concepto("diag_secuencia", 4, "Diagrama de secuencia",
				"Ordena en el tiempo los mensajes que intercambian los objetos para realizar un escenario. Cada participante tiene una línea de vida y las flechas muestran las llamadas y respuestas.",
				["Línea de vida", "Mensaje", "Orden temporal"],
				"Se lee de arriba hacia abajo: lo de arriba pasa primero."),
			_concepto("herencia", 4, "Relaciones en UML",
				"La generalización (herencia) expresa 'es un tipo de'. La asociación indica que dos clases se conocen; la agregación y la composición son relaciones 'tiene un', siendo la composición la más fuerte (las partes no viven sin el todo).",
				["Generalización", "Asociación", "Agregación", "Composición"],
				"'Es un' → herencia (triángulo); 'tiene un' → agregación o composición (rombo)."),
			_concepto("diag_actividad", 4, "Diagrama de actividad",
				"Modela un flujo de trabajo paso a paso: acciones, decisiones (rombos), bifurcaciones y uniones. Es el diagrama ideal para representar el flujo de un caso de uso con sus caminos alternativos.",
				["Acción", "Decisión", "Bifurcación", "Flujo"],
				"Es un diagrama de flujo con notación UML."),
			_concepto("srp", 5, "Principio de responsabilidad única",
				"Cada módulo o clase debe tener una sola razón para cambiar. Si una clase hace demasiadas cosas, un cambio en una de ellas puede romper las demás. Es la S de los principios SOLID.",
				["Una razón para cambiar", "SOLID", "Cohesión"],
				"Si para describir una clase necesitas la palabra 'y', probablemente tiene más de una responsabilidad."),
			_concepto("acoplamiento", 5, "Acoplamiento y cohesión",
				"La cohesión mide qué tan relacionados están los elementos dentro de un módulo (alta es mejor). El acoplamiento mide cuánto depende un módulo de otros (bajo es mejor). Bajo acoplamiento y alta cohesión facilitan mantener y reutilizar el código.",
				["Alta cohesión", "Bajo acoplamiento", "Mantenibilidad"],
				"Cohesión: lo de adentro va junto. Acoplamiento: lo de afuera no se entromete."),
			_concepto("mvc", 5, "Patrones de arquitectura: MVC y MVVM",
				"MVC separa el Modelo (datos y lógica), la Vista (interfaz) y el Controlador (coordina ambos). MVVM hace algo similar con un ViewModel que expone los datos listos para la vista. Ambos evitan mezclar interfaz con lógica.",
				["Modelo", "Vista", "Controlador", "ViewModel"],
				"En esta app: las escenas son la vista y JuegoRepository es el modelo."),
			_concepto("singleton", 5, "Patrón Singleton",
				"Garantiza que una clase tenga una única instancia y un punto de acceso global a ella. Es útil para recursos compartidos (configuración, acceso a datos), aunque usarlo en exceso dificulta las pruebas.",
				["Única instancia", "Acceso global", "Autoload en Godot"],
				"JuegoRepository es un Singleton: un Autoload de Godot."),
			_concepto("capas", 5, "Arquitectura en capas",
				"Organiza el sistema en niveles con responsabilidades definidas (presentación, lógica de negocio, datos). Cada capa solo se comunica con la adyacente, lo que permite cambiar una sin afectar a las demás.",
				["Presentación", "Lógica", "Datos"],
				"Piensa en un edificio: cada piso se apoya solo en el de abajo."),
			_concepto("prueba_unitaria", 6, "Pruebas unitarias",
				"Verifican la unidad más pequeña de código (una función o clase) de forma aislada, con entradas controladas y resultados esperados. Son rápidas, automatizables y la base de la pirámide de pruebas.",
				["Función o clase", "Aislada", "Automatizable"],
				"Si la prueba necesita base de datos o red, ya no es unitaria."),
			_concepto("caja_negra", 6, "Pruebas de caja negra y caja blanca",
				"Las pruebas de caja negra se basan en las entradas y salidas esperadas sin conocer el código interno. Las de caja blanca examinan la estructura del código (ramas, caminos). Ambas se complementan.",
				["Entradas y salidas", "Sin ver el código", "Cobertura de ramas"],
				"Caja negra = el usuario; caja blanca = el programador."),
			_concepto("aceptacion", 6, "Niveles de prueba",
				"Unitarias (una unidad), de integración (varias unidades juntas), de sistema (el producto completo) y de aceptación (el cliente valida que cumple sus necesidades antes de aprobar la entrega).",
				["Unitaria", "Integración", "Sistema", "Aceptación"],
				"Van de lo más pequeño a lo más grande; la aceptación la hace el cliente."),
			_concepto("regresion", 6, "Pruebas de regresión",
				"Se repiten después de cada cambio para comprobar que lo que ya funcionaba sigue funcionando. Por eso conviene automatizarlas: corren en cada entrega sin esfuerzo manual.",
				["Después de cada cambio", "Automatizar", "No romper lo que funcionaba"],
				"Regresión = volver atrás; la prueba evita que el sistema retroceda."),
			_concepto("caso_prueba", 6, "Casos de prueba",
				"Un caso de prueba define al menos: identificador, precondiciones, datos de entrada, pasos y resultado esperado. Sin resultado esperado no se puede decidir si la prueba pasó o falló.",
				["Entrada", "Pasos", "Resultado esperado"],
				"Entrada + resultado esperado es lo mínimo; lo demás ayuda a repetir la prueba."),
			_concepto("loc", 7, "Métricas de tamaño: LOC",
				"Las líneas de código (LOC) miden el tamaño del software. Son fáciles de contar pero dependen del lenguaje y del estilo, y no miden calidad ni complejidad por sí solas.",
				["Tamaño", "Depende del lenguaje", "No mide calidad"],
				"Más líneas no significa mejor software."),
			_concepto("ciclomatica", 7, "Complejidad ciclomática",
				"Definida por McCabe, cuenta el número de caminos linealmente independientes de un programa (aproximadamente, decisiones + 1). A mayor complejidad, más casos de prueba se necesitan y más difícil es mantener el código.",
				["McCabe", "Caminos independientes", "Decisiones + 1"],
				"Cada if, while o case suma un camino más que probar."),
			_concepto("puntos_funcion", 7, "Puntos de función",
				"Estiman el tamaño funcional desde el punto de vista del usuario: entradas, salidas, consultas, archivos y interfaces. Son independientes del lenguaje de programación.",
				["Entradas", "Salidas", "Consultas", "Archivos"],
				"Miden lo que el usuario recibe, no cuánto código hay detrás."),
			_concepto("valor_ganado", 7, "Valor ganado",
				"El valor ganado (EV) compara el trabajo planificado contra el realizado y lo gastado. Permite saber si el proyecto va retrasado o sobre presupuesto antes de que sea tarde.",
				["Planificado", "Realizado", "Gastado"],
				"Tres números: lo que debía estar hecho, lo que está hecho y lo que costó."),
			_concepto("densidad_defectos", 7, "Densidad de defectos",
				"Defectos por cada mil líneas de código (KLOC) es una métrica clásica de calidad. Permite comparar módulos y detectar cuáles necesitan más pruebas o refactorización.",
				["Defectos / KLOC", "Calidad", "Comparar módulos"],
				"Un módulo con muchos defectos por KLOC es un foco rojo."),
			_concepto("sprint", 8, "El sprint en Scrum",
				"El sprint es la iteración de duración fija (1 a 4 semanas) en la que el equipo construye un incremento del producto. Inicia con la planificación y termina con la revisión y la retrospectiva.",
				["Duración fija", "1 a 4 semanas", "Incremento"],
				"Un sprint no se alarga: si algo no cabe, pasa al siguiente."),
			_concepto("product_owner", 8, "Roles de Scrum",
				"El Product Owner prioriza el Product Backlog y representa al cliente; el Scrum Master facilita el proceso y elimina impedimentos; el Equipo de Desarrollo construye el incremento.",
				["Product Owner", "Scrum Master", "Equipo de desarrollo"],
				"El Product Owner decide QUÉ; el equipo decide CÓMO; el Scrum Master cuida el proceso."),
			_concepto("daily", 8, "Eventos de Scrum",
				"Sprint Planning (planear), Daily Scrum (sincronización diaria de 15 minutos), Sprint Review (mostrar el incremento) y Sprint Retrospective (mejorar el proceso).",
				["Planning", "Daily", "Review", "Retrospective"],
				"El Daily es corto porque es para coordinarse, no para resolver problemas."),
			_concepto("kanban", 8, "Tablero Kanban",
				"Visualiza el flujo de trabajo en columnas (Por hacer, En curso, Hecho) y limita el trabajo en curso (WIP) para que el equipo termine tareas antes de empezar otras.",
				["Columnas", "Flujo", "Límite WIP"],
				"Gantt muestra tiempo; Kanban muestra flujo."),
			_concepto("retrospectiva", 8, "Sprint Retrospective",
				"Al final de cada sprint el equipo reflexiona: qué salió bien, qué salió mal y qué va a mejorar. Es el evento de mejora continua de Scrum.",
				["Qué salió bien", "Qué mejorar", "Mejora continua"],
				"Review = mejorar el producto; Retrospective = mejorar al equipo."),
			# ---- Materia 2 · Proceso de Software en Equipo ----
			_concepto("tsp", 9, "Team Software Process (TSP)",
				"El TSP es un proceso para equipos pequeños y autodirigidos: el equipo planea su trabajo, mide su avance con datos (horas, tamaño, defectos) y mejora su proceso en cada ciclo. Se apoya en el PSP, la disciplina personal de cada integrante.",
				["Equipo autodirigido", "Datos", "Ciclos", "PSP"],
				"TSP = el equipo decide, mide y mejora; nadie lo hace por él."),
			_concepto("roles_tsp", 9, "Roles del TSP",
				"Cada integrante asume un rol además de desarrollar: líder de equipo (coordina y da seguimiento), gerente de desarrollo (diseño y producto), gerente de planeación (plan y valor ganado), gerente de calidad y proceso (estándares, inspecciones, defectos) y gerente de soporte (herramientas y configuración).",
				["Líder", "Desarrollo", "Planeación", "Calidad", "Soporte"],
				"Pregunta '¿quién cuida el plan?' → planeación; '¿quién cuida el proceso?' → calidad; '¿quién coordina?' → líder."),
			_concepto("lanzamiento", 9, "El lanzamiento (launch)",
				"Al inicio de cada ciclo el equipo se reúne para fijar metas, asignar roles, estimar las tareas, construir el calendario, evaluar riesgos y presentar el plan. Sin lanzamiento no hay plan compartido.",
				["Metas", "Roles", "Estimación", "Calendario", "Riesgos"],
				"Lanzamiento = planear juntos antes de empezar."),
			_concepto("acuerdo_equipo", 9, "Acuerdo de equipo",
				"El acuerdo de equipo (team agreement) es el documento firmado por todos con las reglas de trabajo: horarios, canales de comunicación, cómo se toman decisiones, responsabilidades de cada rol y qué pasa si alguien incumple.",
				["Reglas", "Comunicación", "Decisiones", "Sanciones"],
				"Es el 'contrato' interno del equipo."),
			_concepto("horas_tarea", 10, "Horas de tarea y disponibilidad",
				"Cada tarea del plan se estima en horas de tarea. La duración del proyecto resulta de dividir las horas totales entre las horas disponibles por semana del equipo (no todas las horas de la semana son horas de tarea).",
				["Horas de tarea", "Disponibilidad semanal", "Calendario"],
				"Semanas = horas del plan ÷ horas disponibles por semana."),
			_concepto("valor_planeado", 10, "Valor planeado (PV)",
				"El valor planeado de una tarea es el porcentaje del esfuerzo total del plan que representa: sus horas estimadas entre las horas totales por cien. Sumando el PV de las tareas de cada semana se obtiene el PV acumulado esperado.",
				["Porcentaje del plan", "Horas estimadas", "Acumulado por semana"],
				"PV responde: ¿qué tanto del proyecto debería estar hecho para esta fecha?"),
			_concepto("probe", 10, "Estimación PROBE",
				"PROBE (PROxy Based Estimating) estima el tamaño y el tiempo de una tarea nueva a partir de datos históricos de tareas parecidas. Mientras más datos propios tenga el equipo, mejores serán sus estimaciones.",
				["Datos históricos", "Tareas similares", "Mejora con el tiempo"],
				"Estimar sin datos es adivinar; PROBE usa lo que ya mediste."),
			_concepto("gantt", 10, "Gantt y tablero de tareas",
				"El diagrama de Gantt muestra las tareas contra el tiempo (cuándo empieza y termina cada una). El tablero de tareas muestra el estado actual: por hacer, en curso y hecho. Juntos permiten ver el calendario y el avance.",
				["Tareas vs tiempo", "Estado actual", "Avance"],
				"Gantt = cuándo; tablero = cómo va."),
			_concepto("valor_ganado_tsp", 11, "Valor ganado (EV)",
				"El valor ganado acumula el valor planeado de las tareas que ya están terminadas al 100 %. No hay crédito parcial: una tarea a medias no suma nada. Comparar EV con PV dice si el proyecto va en tiempo.",
				["Tareas terminadas", "Sin crédito parcial", "EV vs PV"],
				"EV < PV = retraso; EV = PV = en tiempo; EV > PV = adelantado."),
			_concepto("spi_cpi", 11, "Índices SPI y CPI",
				"SPI = EV / PV mide el desempeño en calendario (mayor que 1 es adelantado). CPI = EV / AC mide el desempeño en costo, usando las horas reales (AC): menor que 1 significa que cuesta más esfuerzo del planeado obtener el valor.",
				["SPI calendario", "CPI costo", "1 es el punto de equilibrio"],
				"S de schedule (tiempo), C de cost (horas reales)."),
			# ---- Materia 3 · Arquitectura y Diseño de Software ----
			_concepto("arquitectura", 12, "Arquitectura de software",
				"La arquitectura es la estructura de alto nivel del sistema: sus componentes principales, cómo se relacionan y las decisiones difíciles de cambiar después. Se elige según los atributos de calidad que importan.",
				["Componentes", "Relaciones", "Decisiones difíciles de cambiar"],
				"Si cambiarlo después duele mucho, es arquitectura."),
			_concepto("cliente_servidor", 12, "Cliente-servidor",
				"Los clientes (apps, navegadores) hacen peticiones y un servidor centraliza los datos y la lógica para responderlas. Es el estilo de casi todas las aplicaciones web y móviles con backend.",
				["Petición", "Respuesta", "Servidor central"],
				"El cliente pregunta, el servidor contesta."),
			_concepto("microservicios", 12, "Microservicios",
				"La aplicación se divide en servicios pequeños e independientes, cada uno con su propia responsabilidad, base de datos y despliegue. Escalan por separado pero aumentan la complejidad de operación.",
				["Servicios pequeños", "Independientes", "Despliegue separado"],
				"Muchos servicios chicos en vez de uno grande."),
			_concepto("monolito", 12, "Monolito",
				"Toda la funcionalidad vive en una sola unidad que se construye y despliega junta. Es simple de empezar y probar, pero cuesta escalar partes por separado y un error puede tirar todo el sistema.",
				["Una sola unidad", "Simple al inicio", "Difícil de escalar"],
				"Monolito = una sola pieza."),
			_concepto("atributos_calidad", 12, "Atributos de calidad",
				"Los atributos de calidad (mantenibilidad, rendimiento, disponibilidad, seguridad, escalabilidad, usabilidad) son las cualidades que la arquitectura debe garantizar. Elegir una arquitectura es priorizar unos atributos sobre otros.",
				["Mantenibilidad", "Rendimiento", "Disponibilidad", "Seguridad"],
				"Mantenibilidad = qué tan fácil es cambiarlo."),
			_concepto("patrones", 13, "Patrones de diseño",
				"Un patrón de diseño es una solución probada y reutilizable a un problema de diseño que aparece una y otra vez. Tiene nombre, problema, solución y consecuencias; los popularizó el libro de la 'Banda de los Cuatro' (GoF).",
				["Problema recurrente", "Solución probada", "Nombre común"],
				"Un patrón es una receta con nombre; no es código que se copia."),
			_concepto("observador", 13, "Patrón Observador",
				"Un objeto (sujeto) mantiene una lista de observadores y les notifica automáticamente cuando cambia su estado. Desacopla a quien produce el cambio de quienes reaccionan a él. Las señales de Godot son un ejemplo.",
				["Sujeto", "Observadores", "Notificación"],
				"Si un cambio debe avisar a varios, usa Observador."),
			_concepto("estrategia", 13, "Patrón Estrategia",
				"Define una familia de algoritmos, encapsula cada uno en una clase con la misma interfaz y permite intercambiarlos en tiempo de ejecución sin cambiar al cliente que los usa.",
				["Familia de algoritmos", "Misma interfaz", "Intercambiables"],
				"Si tienes un 'switch' para elegir cómo calcular algo, probablemente quieres Estrategia."),
			_concepto("fabrica", 13, "Patrón Fábrica",
				"Centraliza la creación de objetos: el cliente pide un objeto a la fábrica y ésta decide qué clase concreta construir. Así el cliente no depende de las clases concretas.",
				["Creación centralizada", "Clase concreta oculta", "Menos acoplamiento"],
				"El cliente pide, la fábrica construye."),
			_concepto("adaptador", 13, "Patrón Adaptador",
				"Envuelve una clase con una interfaz incompatible para que funcione con la interfaz que el cliente espera, sin modificar ninguna de las dos. Es el 'convertidor de enchufe' del software.",
				["Interfaz incompatible", "Envoltura", "Sin modificar"],
				"Adaptador = convertidor de enchufe."),
			_concepto("ocp", 14, "Principio abierto/cerrado",
				"Las clases deben estar abiertas a la extensión y cerradas a la modificación: para agregar comportamiento se añade código nuevo (herencia, interfaces, composición) en lugar de modificar el que ya funciona y está probado.",
				["Abierto a extensión", "Cerrado a modificación", "Agregar, no cambiar"],
				"Si cada función nueva te obliga a editar un 'switch' viejo, violas OCP."),
			_concepto("lsp", 14, "Sustitución de Liskov",
				"Una subclase debe poder usarse donde se espera la clase base sin que el programa se rompa ni cambie su comportamiento esperado. Si al sustituir hay sorpresas, la herencia está mal planteada.",
				["Sustituible", "Sin sorpresas", "Herencia correcta"],
				"Si 'es un' pero no se comporta como tal, no debería heredar."),
			_concepto("isp", 14, "Segregación de interfaces",
				"Es mejor tener varias interfaces pequeñas y específicas que una gigante: ningún cliente debe verse obligado a implementar o depender de métodos que no usa.",
				["Interfaces pequeñas", "Específicas", "Nada que no se use"],
				"Si implementas métodos vacíos solo para cumplir la interfaz, violas ISP."),
			_concepto("dip", 14, "Inversión de dependencias",
				"Los módulos de alto nivel (lógica de negocio) no deben depender de los de bajo nivel (base de datos, red): ambos deben depender de abstracciones. Así se puede cambiar la implementación sin tocar la lógica.",
				["Abstracciones", "Alto nivel", "Bajo nivel"],
				"La lógica habla con una interfaz, nunca con MySQL directamente."),
		],
		# ---- CU-05: catálogo de insignias (la condición se evalúa en evaluar_insignias) ----
		"insignias": [
			_insignia("primer_paso", "Primer paso", "Diste el primer paso en tu formación como ingeniero de software.", "Completa tu primer módulo con al menos 70 %.", "estrella", "#2F55E6"),
			_insignia("punteria", "Puntería", "Reconoce la precisión: resolviste un reto completo sin fallar una sola pregunta.", "Acierta todas las preguntas de un reto (100 % en un solo intento).", "check", "#178A4C"),
			_insignia("armador", "Armador", "Armaste un puzzle completo sin errores.", "Completa un módulo tipo puzzle con 100 %.", "puzzle", "#7C3AED"),
			_insignia("estudioso", "Estudioso", "Repasar la teoría es de ingenieros: consultaste los conceptos varias veces.", "Consulta la teoría 5 veces desde un reto.", "libro", "#0E7490"),
			_insignia("racha", "Racha", "Tres módulos seguidos completados sin dejar huecos en el mapa.", "Completa los módulos 1, 2 y 3 de forma consecutiva.", "play", "#C2410C"),
			_insignia("constante", "Constante", "La práctica hace al ingeniero: acumulaste diez intentos.", "Termina 10 retos (cuentan todos los intentos).", "reiniciar", "#D97706"),
			_insignia("analista", "Analista", "Dominas los requerimientos funcionales y no funcionales.", "Completa el módulo 3 · Requerimientos de software.", "quiz", "#2F55E6"),
			_insignia("ingeniero", "Ingeniero", "Recorriste todos los mapas: completaste los módulos de todas las materias.", "Completa todos los módulos de todas las materias con al menos 70 %.", "mapa", "#B45309"),
			_insignia("perfeccionista", "Perfeccionista", "Nada se te escapó: 100 % en todos los módulos.", "Alcanza 100 % como mejor puntaje en todos los módulos.", "estrella", "#14633A"),
			# Sprint 3
			_insignia("repasador", "Repasador", "Corregiste todos tus errores: la lista de repaso quedó vacía.", "Deja en cero la lista de Repasar mis errores.", "reiniciar", "#0E7490"),
			_insignia("sin_pistas", "Sin ayuda", "Completaste un módulo sin pedir ninguna pista.", "Completa un módulo (≥ 70 %) sin usar pistas.", "ojo", "#7C3AED"),
			_insignia("dominio", "Dominio", "Resolviste la práctica de ingeniero y dominaste una materia.", "Aprueba (≥ 70 %) la práctica de ingeniero de una materia.", "puzzle", "#C2410C"),
		],
		# ---- CU-09: preguntas falladas pendientes de repaso ----
		"errores": [],
		# ---- CU-11: una práctica de ingeniero por materia (escenario + ejercicios de manipulación) ----
		"practicas": [
			_practica(1, "Biblioteca escolar",
				"El cliente, la biblioteca de una preparatoria, pide una app para registrar préstamos de libros. Vas a aplicar lo aprendido en la materia para analizar y planear el proyecto.",
				[
					_ej_clasificar("Clasifica cada requerimiento del cliente.", ["Funcional", "No funcional"], [
						["Registrar el préstamo de un libro", "Funcional"],
						["Responder en menos de 2 segundos", "No funcional"],
						["Enviar recordatorio de devolución", "Funcional"],
						["Funcionar sin conexión a internet", "No funcional"],
						["Cifrar las contraseñas de los usuarios", "No funcional"],
						["Generar el reporte mensual de préstamos", "Funcional"],
					], "Funcional = una acción que el sistema hace; no funcional = una cualidad o límite (tiempo, seguridad, disponibilidad).", "req_no_funcional"),
					_ej_construir("Arma el diagrama de casos de uso: coloca cada elemento donde va.", ["Actor", "Caso de uso"], [
						["Bibliotecario", "Actor"],
						["Prestar libro", "Caso de uso"],
						["Alumno", "Actor"],
						["Devolver libro", "Caso de uso"],
						["Consultar catálogo", "Caso de uso"],
						["Sistema de correo", "Actor"],
					], "Los actores son personas o sistemas externos; los casos de uso son las funciones que el sistema les ofrece.", "casos_uso"),
					_ej_ordenar("Ordena las fases del modelo en cascada, de la primera a la última.", [
						"Análisis de requerimientos", "Diseño", "Implementación", "Pruebas", "Mantenimiento",
					], "No puedes probar lo que no has programado ni programar lo que no has diseñado.", "cascada"),
					_ej_seleccionar("El primer sprint tiene 20 h disponibles. Elige las tareas que caben sin exceder las horas, priorizando primero las de prioridad alta y luego las de media.", 20, [
						["Registrar préstamo · prioridad alta", 8, true],
						["Buscar libro por título · prioridad alta", 6, true],
						["Recordatorio por correo · prioridad media", 5, true],
						["Modo oscuro · prioridad baja", 6, false],
						["Estadísticas con gráficas · prioridad baja", 10, false],
					], "Alta + alta + media = 19 h; cualquier tarea de prioridad baja ya no cabe en las 20 h.", "sprint"),
				]),
			_practica(2, "Lanzamiento del Sprint 3",
				"Tu equipo de tres personas inicia el Sprint 3 de su proyecto escolar. Vas a aplicar el TSP: repartir roles, planear el ciclo, elegir tareas y leer el valor ganado.",
				[
					_ej_clasificar("¿A qué rol del TSP le corresponde cada tarea?", ["Líder de equipo", "Gerente de calidad", "Gerente de planeación"], [
						["Dirigir la reunión semanal", "Líder de equipo"],
						["Revisar que las inspecciones se hagan", "Gerente de calidad"],
						["Armar el Gantt del sprint", "Gerente de planeación"],
						["Registrar los defectos encontrados", "Gerente de calidad"],
						["Calcular el valor ganado semanal", "Gerente de planeación"],
						["Resolver conflictos entre integrantes", "Líder de equipo"],
					], "Líder = coordina; calidad = proceso y defectos; planeación = plan y valor ganado.", "roles_tsp"),
					_ej_ordenar("Ordena los pasos del lanzamiento (launch) del TSP.", [
						"Definir las metas del equipo", "Asignar los roles", "Estimar tamaño y horas de las tareas",
						"Construir el calendario", "Evaluar los riesgos", "Presentar el plan al profesor",
					], "Primero el qué (metas) y el quién (roles); luego el cuánto (estimar), el cuándo (calendario) y los riesgos; al final se presenta.", "lanzamiento"),
					_ej_seleccionar("Esta semana el equipo tiene 24 h disponibles. Elige las tareas del plan que caben, priorizando alta y luego media.", 24, [
						["Codificar CU-08 · prioridad alta", 10, true],
						["Pruebas de CU-08 · prioridad alta", 6, true],
						["Actualizar el SRS · prioridad media", 4, true],
						["Manual de usuario · prioridad media", 8, false],
						["Rediseñar el logo · prioridad baja", 6, false],
					], "10 + 6 + 4 = 20 h; el manual (8 h) ya no cabe y el logo es prioridad baja.", "horas_tarea"),
					_ej_clasificar("Al cierre de la semana: PV = 50 %, EV = 40 % y AC = 55 h de 50 h planeadas. Clasifica cada afirmación.", ["Verdadero", "Falso"], [
						["El proyecto va retrasado", "Verdadero"],
						["SPI = 0.8", "Verdadero"],
						["Se ha gastado menos esfuerzo del planeado", "Falso"],
						["CPI es menor que 1", "Verdadero"],
						["El equipo va adelantado", "Falso"],
					], "EV < PV → retraso; SPI = 40/50 = 0.8; AC (55 h) > planeado (50 h) → CPI < 1.", "spi_cpi"),
				]),
			_practica(3, "App de pedidos en línea",
				"Una fonda quiere una app para recibir pedidos y pagos. Vas a decidir su arquitectura, elegir patrones de diseño y detectar violaciones a SOLID.",
				[
					_ej_ordenar("Ordena las capas de la arquitectura, de la más cercana al usuario a la más lejana.", [
						"Interfaz de usuario", "Lógica de negocio", "Acceso a datos", "Base de datos",
					], "Presentación arriba, datos abajo; cada capa solo habla con la adyacente.", "capas"),
					_ej_clasificar("Elige el patrón de diseño adecuado para cada necesidad.", ["Observador", "Singleton", "Estrategia", "Adaptador"], [
						["Una sola conexión a la base de datos", "Singleton"],
						["Avisar a la pantalla cuando cambie el carrito", "Observador"],
						["Cambiar el cálculo de envío según el país", "Estrategia"],
						["Usar una librería de pagos con otra interfaz", "Adaptador"],
						["Elegir entre varios algoritmos de descuento", "Estrategia"],
						["Un único registro de configuración global", "Singleton"],
					], "Uno solo → Singleton; avisar cambios → Observador; algoritmos intercambiables → Estrategia; interfaz incompatible → Adaptador.", "patrones"),
					_ej_clasificar("¿Qué principio SOLID se viola en cada caso?", ["SRP", "OCP", "DIP"], [
						["Una clase calcula el total, imprime el ticket y envía el correo", "SRP"],
						["Para agregar un método de pago hay que modificar un switch gigante", "OCP"],
						["La lógica de negocio crea directamente una conexión MySQL", "DIP"],
						["La clase Pedido también guarda archivos en disco", "SRP"],
						["El módulo de reportes depende de una clase concreta de Excel", "DIP"],
					], "Muchas responsabilidades → SRP; modificar para extender → OCP; depender de clases concretas → DIP.", "srp"),
					_ej_seleccionar("Tienes 12 h para refactorizar antes de la entrega. Elige las mejoras que caben, priorizando las de prioridad alta y luego media.", 12, [
						["Extraer la lógica de pago a su propia clase · prioridad alta", 5, true],
						["Agregar una interfaz para el acceso a datos · prioridad alta", 4, true],
						["Renombrar variables confusas · prioridad media", 2, true],
						["Cambiar los colores de la app · prioridad baja", 3, false],
						["Reescribir todo en otro lenguaje · prioridad baja", 40, false],
					], "5 + 4 + 2 = 11 h; lo demás es prioridad baja o no cabe.", "ocp"),
				]),
		],
		"intentos_practica": [],
	}

func _materia(id: int, nombre: String, corto: String, descripcion: String, icono: String, color: String) -> Dictionary:
	return {
		"id": id,
		"nombre": nombre,
		"corto": corto,            # nombre corto para chips y etiquetas
		"descripcion": descripcion,
		"icono": icono,            # tipo de Icono.gd
		"color": color,
	}

func _practica(id_materia: int, titulo: String, escenario: String, ejercicios: Array) -> Dictionary:
	return {
		"id_materia": id_materia,
		"titulo": titulo,
		"escenario": escenario,
		"ejercicios": ejercicios,
		"intentos": 0,
		"mejor_porcentaje": -1,
		"mejor_puntos": 0,
		"dominada": false,
	}

## Ejercicio "clasificar": arrastrar (tocar) tarjetas a categorías.
func _ej_clasificar(instruccion: String, categorias: Array, piezas: Array, justificacion: String, concepto: String = "") -> Dictionary:
	var lista: Array = []
	for p in piezas:
		lista.append({"texto": p[0], "categoria": p[1]})
	return {"tipo": "clasificar", "instruccion": instruccion, "categorias": categorias, "piezas": lista,
		"justificacion": justificacion, "concepto": concepto}

## Ejercicio "construir": colocar actores y casos de uso en el diagrama (misma mecánica que clasificar).
func _ej_construir(instruccion: String, zonas: Array, piezas: Array, justificacion: String, concepto: String = "") -> Dictionary:
	var ej := _ej_clasificar(instruccion, zonas, piezas, justificacion, concepto)
	ej["tipo"] = "construir"
	return ej

## Ejercicio "ordenar": construir una secuencia tocando las piezas en orden.
func _ej_ordenar(instruccion: String, piezas_en_orden: Array, justificacion: String, concepto: String = "") -> Dictionary:
	return {"tipo": "ordenar", "instruccion": instruccion, "piezas": piezas_en_orden, "justificacion": justificacion, "concepto": concepto}

## Ejercicio "seleccionar": elegir qué tareas caben sin exceder el límite de horas.
func _ej_seleccionar(instruccion: String, limite: int, piezas: Array, justificacion: String, concepto: String = "") -> Dictionary:
	var lista: Array = []
	for p in piezas:
		lista.append({"texto": p[0], "horas": p[1], "correcta": p[2]})
	return {"tipo": "seleccionar", "instruccion": instruccion, "limite": limite, "piezas": lista,
		"justificacion": justificacion, "concepto": concepto}

func _concepto(id: String, id_modulo: int, titulo: String, explicacion: String, claves: Array, truco: String) -> Dictionary:
	return {
		"id": id,
		"id_modulo": id_modulo,
		"titulo": titulo,
		"explicacion": explicacion,
		"claves": claves,          # chips de "categorías / ideas clave" del mockup
		"truco": truco,            # "Truco rápido" del mockup
	}

func _insignia(id: String, titulo: String, descripcion: String, condicion: String, icono: String, color: String) -> Dictionary:
	return {
		"id": id,
		"titulo": titulo,
		"descripcion": descripcion,
		"condicion": condicion,
		"icono": icono,            # tipo de Icono.gd
		"color": color,
		"obtenida": false,
		"fecha_obtencion": "",
	}

func _modulo(id: int, nombre: String, tipo: String, descripcion: String, estado: String = "bloqueado", id_materia: int = 1) -> Dictionary:
	return {
		"id": id,
		"id_materia": id_materia,     # CU-08: materia a la que pertenece el módulo
		"nombre": nombre,
		"tipo": tipo,                 # "quiz" o "puzzle"
		"descripcion": descripcion,
		"num_preguntas": 5,
		"puntos_maximos": 100,
		"estado": estado,             # "bloqueado" | "desbloqueado" | "completado"
		"mejor_puntaje": -1,          # % del mejor intento; -1 = sin intentos
		"puntos_obtenidos": 0,        # puntos que ya aportó al total del perfil
	}

func _reactivo(id: int, id_modulo: int, pregunta: String, opciones: Array, correcta: int, retro: String, id_concepto: String = "") -> Dictionary:
	return {
		"id": id,
		"id_modulo": id_modulo,
		"pregunta": pregunta,
		"opciones": opciones,
		"respuesta_correcta": correcta,   # índice (0-3) dentro de opciones
		"retroalimentacion": retro,       # texto corto en la pantalla de respuesta incorrecta
		"id_concepto": id_concepto,       # CU-04: concepto de teoría asociado ("" = sin concepto)
	}
