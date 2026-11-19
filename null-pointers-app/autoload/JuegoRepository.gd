# res://autoload/JuegoRepository.gd
# Repositorio de datos local (Autoload). Implementa la "base de datos local"
# del SRS con un archivo JSON en user:// (RNF-01: sin conexión a internet).
#
# Tablas (SDS): perfil_jugador, temas, modulos, reactivos, intentos_modulo, conceptos,
#               insignias, errores (CU-09), puzzles, practicas e intentos_practica (CU-11)
# Casos de uso cubiertos: CU-01 (perfil), CU-02 (mapa), CU-03 (actividad),
#                         CU-04 (teoría), CU-05 (insignias), CU-06 (progreso),
#                         CU-08 (temas), CU-09 (repaso de errores),
#                         CU-10 (pistas), CU-11 (práctica de ingeniero)
#
# Estructura (Sprint 3, esquema 4): la materia Introducción a la Ingeniería de
# Software se divide en 12 TEMAS. Cada tema tiene su propio mapa con tres módulos
# (Quiz I, Quiz II y Puzzle) y un nodo final "Práctica de ingeniero".
#   - Cada quiz sortea 5 preguntas al azar del banco de 15 del tema.
#   - El módulo Puzzle usa las mecánicas de manipulación (clasificar, construir,
#     ordenar, seleccionar) con los ejercicios del tema.
#   - La práctica toma 4 ejercicios al azar del tema y de lógica de programación.
#
# Uso desde cualquier escena:
#   JuegoRepository.obtener_temas()                  # CU-08
#   JuegoRepository.obtener_modulos_tema(id_tema)    # CU-02 / CU-08
#   JuegoRepository.sortear_reactivos(id_modulo)     # CU-03: 5 preguntas al azar
#   JuegoRepository.registrar_intento(101, 4)        # módulo 101, 4 aciertos de 5
#   JuegoRepository.obtener_concepto(id_reactivo)    # CU-04
#   JuegoRepository.obtener_insignias()              # CU-05
#   JuegoRepository.obtener_progreso()               # CU-06
#   JuegoRepository.obtener_errores_pendientes()     # CU-09
#   JuegoRepository.costo_pista("recordar")          # CU-10
#   JuegoRepository.sortear_practica(id_tema)        # CU-11

extends Node

var ruta_bd := "user://nullpointers_bd.json"   # variable para que las pruebas usen user://test_bd.json
const ESQUEMA := 5                   # versión del esquema de la BD (Sprint 3 · temas + niveles de insignias)
const PORCENTAJE_MINIMO := 70        # % necesario para completar un módulo (mockups / CU-03)
const PREGUNTAS_POR_QUIZ := 5        # preguntas que sortea cada intento de quiz
const EJERCICIOS_PRACTICA := 4       # ejercicios que sortea cada intento de práctica (CU-11)
const PUNTOS_PRACTICA := 100

var bd: Dictionary = {}
var modulo_seleccionado: int = 101    # lo pone el mapa (CU-02) antes de abrir la actividad
## CU-08: tema cuyo mapa se muestra (la pone la pantalla de temas antes de abrir el mapa).
var tema_seleccionado: int = 1
## CU-11: tema cuya práctica se va a resolver (la pone el mapa antes de abrir la práctica).
var practica_tema: int = 1
## Módulo tipo puzzle que se va a jugar en la escena de práctica (0 = es la práctica del tema).
var puzzle_modulo: int = 0
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
	# Si el archivo principal está dañado (p. ej. la app se cerró a la mitad de una
	# escritura), se intenta con la copia de respaldo antes de empezar de cero (RNF-02).
	for ruta in [ruta_bd, ruta_bd + ".bak"]:
		var datos = _leer_bd(ruta)
		if datos is Dictionary and datos.has("modulos"):
			if ruta != ruta_bd:
				push_warning("BD principal dañada; se recuperó la copia de respaldo")
			if int(datos.get("esquema", 1)) < 4:
				bd = _migrar_a_temas(datos)      # BD de Sprint 1, 2 o 3 (materias)
			else:
				bd = datos
				_refrescar_contenido()           # esquema 4 → 5: insignias con niveles, avatares
				bd["esquema"] = ESQUEMA
			evaluar_insignias()
			_evaluar_avatares()
			guardar_bd()
			return
	# Primera vez (o archivo y respaldo dañados): crear BD inicial
	bd = _bd_inicial()
	guardar_bd()

func _leer_bd(ruta: String) -> Variant:
	if not FileAccess.file_exists(ruta):
		return null
	var archivo := FileAccess.open(ruta, FileAccess.READ)
	if archivo == null:
		return null
	var texto := archivo.get_as_text()
	archivo.close()
	return JSON.parse_string(texto)

## Escritura segura (RNF-02): se escribe a un archivo temporal y luego se reemplaza
## el principal, así un cierre a la mitad nunca deja el archivo principal a medias.
## La versión anterior queda como respaldo (.bak) para cargar_bd().
func guardar_bd() -> void:
	var temporal := ruta_bd + ".tmp"
	var archivo := FileAccess.open(temporal, FileAccess.WRITE)
	if archivo == null:
		push_error("No se pudo guardar el progreso (%s)" % error_string(FileAccess.get_open_error()))
		return
	archivo.store_string(JSON.stringify(bd, "\t"))
	archivo.close()
	if FileAccess.file_exists(ruta_bd):
		DirAccess.copy_absolute(ruta_bd, ruta_bd + ".bak")
	if DirAccess.rename_absolute(temporal, ruta_bd) != OK:
		# Si la plataforma no permite reemplazar con rename, se escribe directo
		var directo := FileAccess.open(ruta_bd, FileAccess.WRITE)
		if directo != null:
			directo.store_string(JSON.stringify(bd, "\t"))
			directo.close()
		DirAccess.remove_absolute(temporal)

## Borra todo el progreso (útil para pruebas del Líder de Calidad).
func reiniciar_bd() -> void:
	bd = _bd_inicial()
	guardar_bd()


## El contenido (preguntas, conceptos, puzzles, textos de insignias) no guarda
## progreso: se refresca desde _bd_inicial() para que las correcciones del banco
## lleguen a quien ya tiene la app instalada. El progreso (módulos, intentos,
## errores, prácticas) se conserva.
func _refrescar_contenido() -> void:
	var inicial := _bd_inicial()
	bd["temas"] = inicial["temas"]
	bd["reactivos"] = inicial["reactivos"]
	bd["conceptos"] = inicial["conceptos"]
	bd["puzzles"] = inicial["puzzles"]
	# Módulos nuevos (por si el banco crece) y textos actualizados
	for m_ini in inicial["modulos"]:
		var m := obtener_modulo(int(m_ini["id"]))
		if m.is_empty():
			bd["modulos"].append(m_ini)
		else:
			for k in ["nombre", "tipo", "descripcion", "num_preguntas", "puntos_maximos", "id_tema"]:
				m[k] = m_ini[k]
	for ins_ini in inicial["insignias"]:
		var encontrada: Dictionary = {}
		for ins in bd["insignias"]:
			if ins["id"] == ins_ini["id"]:
				encontrada = ins
				break
		if encontrada.is_empty():
			bd["insignias"].append(ins_ini)
		else:
			for k in ["titulo", "descripcion", "condicion", "condiciones", "icono", "color", "tipo", "metrica", "niveles", "unidad"]:
				if ins_ini.has(k):
					encontrada[k] = ins_ini[k]
			if ins_ini.has("id_tema"):
				encontrada["id_tema"] = ins_ini["id_tema"]
			if not encontrada.has("nivel"):
				encontrada["nivel"] = 1 if encontrada.get("obtenida", false) else 0
	for p_ini in inicial["practicas"]:
		var p := obtener_practica(int(p_ini["id_tema"]))
		if p.is_empty():
			bd["practicas"].append(p_ini)
		else:
			p["titulo"] = p_ini["titulo"]
			p["escenario"] = p_ini["escenario"]


## Lleva una BD de Sprint 1/2 (8 módulos) o de Sprint 3 (materias) al esquema
## por temas SIN perder el progreso: los módulos 1-8 pasan a ser el Quiz I de los
## temas 1-8, los intentos se re-asocian, y perfil, puntos, insignias y errores
## se conservan. Los módulos de las materias 2 y 3 (ids 9-14) desaparecen, pero
## los puntos que dieron se quedan en el perfil.
func _migrar_a_temas(vieja: Dictionary) -> Dictionary:
	var nueva := _bd_inicial()
	# Perfil
	var p: Dictionary = vieja.get("perfil_jugador", {})
	for k in ["alias", "avatar_id", "contrasena", "puntos_totales", "fecha_creacion"]:
		if p.has(k):
			nueva["perfil_jugador"][k] = p[k]
	if str(nueva["perfil_jugador"]["alias"]) == "":
		nueva["perfil_jugador"]["alias"] = "estudiante_%04d" % (randi() % 10000)
	nueva["teoria_consultas"] = int(vieja.get("teoria_consultas", 0))
	# Progreso de los módulos 1-8 → Quiz I del tema correspondiente
	for m_vieja in vieja.get("modulos", []):
		var id_viejo := int(m_vieja["id"])
		if id_viejo < 1 or id_viejo > 8:
			continue
		var quiz1 := obtener_modulo_en(nueva, id_viejo * 100 + 1)
		if quiz1.is_empty():
			continue
		quiz1["estado"] = m_vieja.get("estado", "bloqueado")
		quiz1["mejor_puntaje"] = int(m_vieja.get("mejor_puntaje", -1))
		quiz1["puntos_obtenidos"] = int(m_vieja.get("puntos_obtenidos", 0))
		if quiz1["estado"] == "completado":
			var quiz2 := obtener_modulo_en(nueva, id_viejo * 100 + 2)
			if not quiz2.is_empty() and quiz2["estado"] == "bloqueado":
				quiz2["estado"] = "desbloqueado"
	# Intentos: solo los de los módulos 1-8, re-asociados
	for i in vieja.get("intentos_modulo", []):
		var id_viejo := int(i["id_modulo"])
		if id_viejo >= 1 and id_viejo <= 8:
			var copia: Dictionary = i.duplicate()
			copia["id_modulo"] = id_viejo * 100 + 1
			if not copia.has("pistas"): copia["pistas"] = 0
			copia["id"] = nueva["intentos_modulo"].size() + 1
			nueva["intentos_modulo"].append(copia)
	# Insignias obtenidas
	for ins_vieja in vieja.get("insignias", []):
		if ins_vieja.get("obtenida", false):
			for ins in nueva["insignias"]:
				if ins["id"] == ins_vieja["id"]:
					ins["obtenida"] = true
					ins["nivel"] = maxi(int(ins_vieja.get("nivel", 1)), 1)
					ins["fecha"] = ins_vieja.get("fecha", "")
	# Errores (CU-09): solo de preguntas que siguen existiendo
	for e in vieja.get("errores", []):
		var r := _buscar_reactivo_en(nueva, int(e["id_reactivo"]))
		if r.is_empty():
			continue
		var copia: Dictionary = e.duplicate()
		copia["id_tema"] = int(r["id_tema"])
		copia.erase("id_modulo")
		nueva["errores"].append(copia)
	return nueva

func obtener_modulo_en(base: Dictionary, id_modulo: int) -> Dictionary:
	for m in base["modulos"]:
		if int(m["id"]) == id_modulo:
			return m
	return {}

func _buscar_reactivo_en(base: Dictionary, id_reactivo: int) -> Dictionary:
	for r in base["reactivos"]:
		if int(r["id"]) == id_reactivo:
			return r
	return {}


# =====================================================================
#  CU-08: ELEGIR TEMA
# =====================================================================
func obtener_temas() -> Array:
	return bd["temas"]

func obtener_tema(id_tema: int) -> Dictionary:
	for t in bd["temas"]:
		if int(t["id"]) == id_tema:
			return t
	return {}

## Módulos de un tema (en orden). Con id_tema = -1 regresa todos.
func obtener_modulos_tema(id_tema: int) -> Array:
	var lista: Array = []
	for m in bd["modulos"]:
		if id_tema < 0 or int(m.get("id_tema", 1)) == id_tema:
			lista.append(m)
	return lista

func modulos_completados_tema(id_tema: int) -> int:
	var total := 0
	for m in obtener_modulos_tema(id_tema):
		if m["estado"] == "completado":
			total += 1
	return total

## Resumen de cada tema para el catálogo (paso 2 del CU-08):
## nombre, módulos completados/total, porcentaje de avance y si está dominado.
func obtener_catalogo_temas() -> Array:
	var catalogo: Array = []
	for t in bd["temas"]:
		var id_tema := int(t["id"])
		var mods := obtener_modulos_tema(id_tema)
		var completados := modulos_completados_tema(id_tema)
		var porcentaje := 0
		if not mods.is_empty():
			porcentaje = int(round(float(completados) / float(mods.size()) * 100.0))
		var fila: Dictionary = t.duplicate()
		fila["modulos_totales"] = mods.size()
		fila["modulos_completados"] = completados
		fila["porcentaje"] = porcentaje
		fila["sin_iniciar"] = completados == 0 and not _tema_tiene_intentos(id_tema)
		fila["dominado"] = tema_dominado(id_tema)
		fila["es_ultimo"] = id_tema == int(bd.get("ultimo_tema", 1))
		catalogo.append(fila)
	return catalogo

func _tema_tiene_intentos(id_tema: int) -> bool:
	for i in bd["intentos_modulo"]:
		var m := obtener_modulo(int(i["id_modulo"]))
		if not m.is_empty() and int(m.get("id_tema", 1)) == id_tema:
			return true
	return false

## El tema visitado por última vez ("Continuar en…", flujo alternativo 2 del CU-08).
func obtener_ultimo_tema() -> Dictionary:
	return obtener_tema(int(bd.get("ultimo_tema", 1)))

## Paso 4 del CU-08: el estudiante eligió un tema; se recuerda para la próxima vez.
func seleccionar_tema(id_tema: int) -> void:
	tema_seleccionado = id_tema
	bd["ultimo_tema"] = id_tema
	guardar_bd()

## El siguiente módulo jugable (desbloqueado) de un tema, para el menú.
func siguiente_modulo_tema(id_tema: int) -> Dictionary:
	for m in obtener_modulos_tema(id_tema):
		if m["estado"] == "desbloqueado":
			return m
	return {}

## Siguiente módulo del mismo tema (o {} si es el último).
func siguiente_modulo_de(id_modulo: int) -> Dictionary:
	var actual := obtener_modulo(id_modulo)
	if actual.is_empty():
		return {}
	var mods := obtener_modulos_tema(int(actual.get("id_tema", 1)))
	for k in mods.size():
		if int(mods[k]["id"]) == id_modulo:
			return mods[k + 1] if k + 1 < mods.size() else {}
	return {}

## Número del módulo dentro de su tema (1, 2, 3…).
func numero_en_tema(id_modulo: int) -> int:
	var actual := obtener_modulo(id_modulo)
	if actual.is_empty():
		return 0
	var mods := obtener_modulos_tema(int(actual.get("id_tema", 1)))
	for k in mods.size():
		if int(mods[k]["id"]) == id_modulo:
			return k + 1
	return 0


# =====================================================================
#  CU-01: PERFIL DE JUGADOR
# =====================================================================
const ALIAS_MIN := 3
const ALIAS_MAX := 20
const CONTRASENA_MIN := 4
const CONTRASENA_MAX := 8
## Catálogo de avatares: ver Avatar.CATALOGO (14; 8 se desbloquean al avanzar).

func existe_perfil() -> bool:
	return bd["perfil_jugador"]["alias"] != ""

func obtener_perfil() -> Dictionary:
	return bd["perfil_jugador"]

## Valida el alias según el SRS: no vacío, de 3 a 20 caracteres.
func alias_valido(alias: String) -> bool:
	var a := alias.strip_edges()
	return a.length() >= ALIAS_MIN and a.length() <= ALIAS_MAX

## Valida la contraseña: solo dígitos, de 4 a 8.
func contrasena_valida(c: String) -> bool:
	return c.is_valid_int() and c.length() >= CONTRASENA_MIN and c.length() <= CONTRASENA_MAX and not c.begins_with("-")

## Compatibilidad: crea/renombra el perfil (el perfil ya existe por defecto).
func crear_perfil(alias: String) -> bool:
	return actualizar_nombre(alias)

## Cambia el alias. Regresa false si no cumple 3-20 caracteres.
func actualizar_nombre(nuevo_alias: String) -> bool:
	var a := nuevo_alias.strip_edges()
	if not alias_valido(a):
		return false
	bd["perfil_jugador"]["alias"] = a
	guardar_bd()
	return true

## Cambia el avatar (debe ser uno del catálogo Avatar.CATALOGO y estar desbloqueado).
func actualizar_avatar(avatar_id: String) -> bool:
	if not Avatar.ids().has(avatar_id) or not avatar_disponible(avatar_id):
		return false
	bd["perfil_jugador"]["avatar_id"] = avatar_id
	guardar_bd()
	return true

## ¿El avatar ya se desbloqueó? Los 6 básicos siempre; los demás según su requisito
## (temas completos, temas dominados, módulos sin pistas, medallas de oro, retos terminados).
func avatar_disponible(avatar_id: String) -> bool:
	var info := Avatar.info(avatar_id)
	var req: Dictionary = info["requisito"]
	if str(req["tipo"]) == "":
		return true
	var m := _metricas()
	return int(m.get(str(req["tipo"]), 0)) >= int(req["valor"])

## Catálogo de avatares con su estado para la pantalla de perfil (CU-01).
func obtener_catalogo_avatares() -> Array:
	var lista: Array = []
	var m := _metricas()
	for a in Avatar.CATALOGO:
		var fila: Dictionary = a.duplicate(true)
		var req: Dictionary = a["requisito"]
		var valor: int = int(m.get(str(req["tipo"]), 0)) if str(req["tipo"]) != "" else 0
		fila["disponible"] = str(req["tipo"]) == "" or valor >= int(req["valor"])
		fila["progreso"] = valor
		fila["meta"] = int(req["valor"])
		lista.append(fila)
	return lista

## Avatares que se acaban de desbloquear (se llama después de evaluar insignias).
func _evaluar_avatares() -> Array:
	var nuevos: Array = []
	if not bd.has("avatares_desbloqueados"):
		bd["avatares_desbloqueados"] = []
	for a in Avatar.CATALOGO:
		var id: String = a["id"]
		if bd["avatares_desbloqueados"].has(id):
			continue
		if avatar_disponible(id):
			bd["avatares_desbloqueados"].append(id)
			if str(a["requisito"]["tipo"]) != "":
				nuevos.append(a)
	return nuevos

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
#  CU-02: MAPA DE MÓDULOS
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

## El siguiente módulo que el alumno puede jugar (para "Siguiente: …" del menú).
func siguiente_modulo() -> Dictionary:
	for m in bd["modulos"]:
		if m["estado"] == "desbloqueado":
			return m
	return {}


# =====================================================================
#  CU-03: RESOLVER ACTIVIDAD
# =====================================================================
## Banco completo de preguntas del tema al que pertenece el módulo.
func obtener_reactivos(id_modulo: int) -> Array:
	var m := obtener_modulo(id_modulo)
	if m.is_empty():
		return []
	return obtener_reactivos_tema(int(m.get("id_tema", 1)))

func obtener_reactivos_tema(id_tema: int) -> Array:
	var lista: Array = []
	for r in bd["reactivos"]:
		if int(r["id_tema"]) == id_tema:
			lista.append(r)
	return lista

## Sortea las preguntas de un intento: num_preguntas al azar del banco del tema,
## sin repetir (regla del Sprint 3: cada intento trae preguntas distintas).
func sortear_reactivos(id_modulo: int) -> Array:
	var m := obtener_modulo(id_modulo)
	var banco := obtener_reactivos(id_modulo)
	banco.shuffle()
	var n: int = int(m.get("num_preguntas", PREGUNTAS_POR_QUIZ)) if not m.is_empty() else PREGUNTAS_POR_QUIZ
	return banco.slice(0, mini(n, banco.size()))

func obtener_intentos(id_modulo: int) -> Array:
	var lista: Array = []
	for i in bd["intentos_modulo"]:
		if int(i["id_modulo"]) == id_modulo:
			lista.append(i)
	return lista

## Registra un intento terminado. Regresa un Dictionary con todo lo que
## necesita la pantalla de resultados de los mockups.
##   aciertos     = preguntas correctas (quiz) o piezas correctas (puzzle)
##   puntos_reto  = puntos acumulados en el intento ya con los descuentos de pistas (CU-10);
##                  -1 = calcularlos a partir de los aciertos (sin pistas).
##   pistas       = número de pistas usadas en el intento (CU-10).
##   total        = total de preguntas/piezas del intento; -1 = num_preguntas del módulo.
func registrar_intento(id_modulo: int, aciertos: int, puntos_reto: int = -1, pistas: int = 0, total: int = -1) -> Dictionary:
	var modulo := obtener_modulo(id_modulo)
	if modulo.is_empty():
		push_error("Módulo %d no existe" % id_modulo)
		return {}

	# El porcentaje se calcula sobre las preguntas del intento (5), no sobre el banco (15)
	var total_preguntas := total if total > 0 else int(modulo["num_preguntas"])

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

	# 3) Marcar completado y desbloquear el siguiente DEL MISMO TEMA (regla del CU-08)
	var siguiente_desbloqueado: Dictionary = {}
	if completado:
		modulo["estado"] = "completado"
		var siguiente := siguiente_modulo_de(id_modulo)
		if not siguiente.is_empty() and siguiente["estado"] == "bloqueado":
			siguiente["estado"] = "desbloqueado"
			siguiente_desbloqueado = siguiente

	# 4) CU-11 paso 1: la práctica se desbloquea al completar todos los módulos del tema
	var id_tema := int(modulo.get("id_tema", 1))
	var practica_desbloqueada := completado and siguiente_desbloqueado.is_empty() \
		and practica_disponible(id_tema) and int(obtener_practica_estado(id_tema)["intentos"]) == 0

	# 5) Insignias que suben de nivel y avatares que se desbloquean con este intento (CU-05 / CU-01)
	var insignias_nuevas := evaluar_insignias()
	var avatares_nuevos := _evaluar_avatares()
	guardar_bd()

	return {
		"aciertos": aciertos,
		"avatares_nuevos": avatares_nuevos,
		"total": total_preguntas,
		"porcentaje": porcentaje,
		"puntos": puntos,
		"puntos_maximos": puntos_maximos,
		"completado": completado,
		"mejor_previo": mejor_previo,
		"es_mejor": porcentaje > mejor_previo,
		"puntos_sumados": puntos_sumados,
		"puntos_totales": obtener_puntos_totales(),
		"siguiente_desbloqueado": siguiente_desbloqueado,
		"insignias_nuevas": insignias_nuevas,
		"practica_desbloqueada": practica_desbloqueada,
		"intentos": obtener_intentos(id_modulo).size(),     # la pantalla de resultados muestra "Intento N"
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
		"id_tema": int(r["id_tema"]),
		"fecha_fallo": Time.get_datetime_string_from_system(),
		"corregida": false,
		"fecha_repaso": "",
	})
	guardar_bd()

## Preguntas pendientes de repaso (falladas y aún no acertadas en repaso).
## Con id_tema >= 0 solo las de ese tema.
func obtener_errores_pendientes(id_tema: int = -1) -> Array:
	var lista: Array = []
	for e in bd["errores"]:
		if e["corregida"]:
			continue
		if obtener_reactivo(int(e["id_reactivo"])).is_empty():
			continue
		if id_tema >= 0 and int(e.get("id_tema", -1)) != id_tema:
			continue
		lista.append(e)
	return lista

## Paso 2 del CU-09: errores agrupados por tema, con conteos y los conceptos implicados.
func obtener_resumen_errores() -> Array:
	var resumen: Array = []
	for t in bd["temas"]:
		var id_tema := int(t["id"])
		var pendientes := obtener_errores_pendientes(id_tema)
		if pendientes.is_empty():
			continue
		var conceptos: Array = []
		for e in pendientes:
			var c := obtener_concepto(int(e["id_reactivo"]))
			if not c.is_empty() and not conceptos.has(c["titulo"]):
				conceptos.append(c["titulo"])
		resumen.append({
			"id_tema": id_tema,
			"tema": t["nombre"],
			"color": t["color"],
			"total": pendientes.size(),
			"conceptos": conceptos,
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
	_evaluar_avatares()
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
	return obtener_concepto_por_id(str(r["id_concepto"]))

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

## Insignias de un tipo: "logro" (12 generales) o "tema" (una medalla por tema).
func obtener_insignias_tipo(tipo: String) -> Array:
	var lista: Array = []
	for i in bd["insignias"]:
		if str(i.get("tipo", "logro")) == tipo:
			lista.append(i)
	return lista

func insignias_obtenidas() -> int:
	var n := 0
	for i in bd["insignias"]:
		if i["obtenida"]:
			n += 1
	return n

const NOMBRES_NIVEL := ["Bloqueada", "Bronce", "Plata", "Oro"]
const COLORES_NIVEL := ["#C9CDD9", "#B9722D", "#8E96A8", "#D9A21B"]

static func nombre_nivel(nivel: int) -> String:
	return NOMBRES_NIVEL[clampi(nivel, 0, 3)]

static func color_nivel(nivel: int) -> Color:
	return Color(COLORES_NIVEL[clampi(nivel, 0, 3)])

## Cuántas medallas de tema están en un nivel dado (3 = oro).
func medallas_en_nivel(nivel: int) -> int:
	var n := 0
	for i in obtener_insignias_tipo("tema"):
		if int(i.get("nivel", 0)) >= nivel:
			n += 1
	return n

## Todas las cifras del progreso que alimentan las insignias y los avatares.
func _metricas() -> Dictionary:
	var intentos: Array = bd["intentos_modulo"]
	var perfectos := 0            # intentos con 100 %
	var puzzles_perfectos := 0    # intentos con 100 % en módulos puzzle
	var sin_pistas_mods := {}     # módulos completados sin pistas (distintos)
	var primer_intento := 0       # módulos completados al primer intento
	var vistos := {}
	for i in intentos:
		var id_mod := int(i["id_modulo"])
		var m := obtener_modulo(id_mod)
		if int(i["porcentaje"]) >= 100:
			perfectos += 1
			if not m.is_empty() and m["tipo"] == "puzzle":
				puzzles_perfectos += 1
		if bool(i["completado"]) and int(i.get("pistas", 0)) == 0:
			sin_pistas_mods[id_mod] = true
		if not vistos.has(id_mod):
			vistos[id_mod] = true
			if bool(i["completado"]):
				primer_intento += 1
	var modulos_perfectos := 0
	for m in bd["modulos"]:
		if int(m["mejor_puntaje"]) >= 100:
			modulos_perfectos += 1
	var temas_completos := 0
	for t in bd["temas"]:
		var mods := obtener_modulos_tema(int(t["id"]))
		if not mods.is_empty() and modulos_completados_tema(int(t["id"])) >= mods.size():
			temas_completos += 1
	var corregidas := 0
	for e in bd.get("errores", []):
		if e["corregida"]:
			corregidas += 1
	# Analista: módulos completados del tema 3 (+1 si está dominado)
	var analista := modulos_completados_tema(3) + (1 if tema_dominado(3) else 0)
	var oros := 0
	for i in bd["insignias"]:
		if str(i.get("tipo", "logro")) == "tema" and int(i.get("nivel", 0)) >= 3:
			oros += 1
	return {
		"modulos_completados": modulos_completados(),
		"temas_completos": temas_completos,
		"temas_dominados": temas_dominados(),
		"retos_perfectos": perfectos,
		"puzzles_perfectos": puzzles_perfectos,
		"modulos_perfectos": modulos_perfectos,
		"sin_pistas": sin_pistas_mods.size(),
		"primer_intento": primer_intento,
		"teoria": int(bd.get("teoria_consultas", 0)),
		"intentos": intentos.size(),
		"corregidas": corregidas,
		"analista": analista,
		"oros": oros,
	}

## Promedio del mejor puntaje de los módulos de un tema (0 si falta alguno por completar).
func promedio_tema(id_tema: int) -> int:
	var mods := obtener_modulos_tema(id_tema)
	if mods.is_empty() or modulos_completados_tema(id_tema) < mods.size():
		return 0
	var suma := 0
	for m in mods:
		suma += int(m["mejor_puntaje"])
	return int(round(float(suma) / float(mods.size())))

## Revisa cada insignia contra el progreso y sube su nivel (bronce 1, plata 2, oro 3)
## cuando el valor de su métrica alcanza el siguiente umbral. Regresa las insignias
## que subieron de nivel (con el nivel nuevo). Las medallas de tema usan el promedio
## del mejor puntaje de sus tres módulos (70 / 85 / 100 %).
## No se usa guardar_bd aquí: lo hace quien llama (registrar_intento / cargar_bd).
func evaluar_insignias() -> Array:
	var nuevas: Array = []
	var m := _metricas()
	# Primero las medallas de tema (las de oro alimentan la métrica "oros")
	for pasada in 2:
		for ins in bd["insignias"]:
			var tipo := str(ins.get("tipo", "logro"))
			if (pasada == 0) != (tipo == "tema"):
				continue
			var valor := 0
			if tipo == "tema":
				valor = promedio_tema(int(ins["id_tema"]))
			else:
				valor = int(m.get(str(ins["metrica"]), 0))
			ins["progreso"] = valor
			var nivel := 0
			for umbral in ins["niveles"]:
				if valor >= int(umbral):
					nivel += 1
			if nivel > int(ins.get("nivel", 0)):
				ins["nivel"] = nivel
				ins["obtenida"] = true
				ins["fecha"] = Time.get_datetime_string_from_system()
				nuevas.append(ins)
		if pasada == 0:
			m = _metricas()
	return nuevas


# =====================================================================
#  CU-11: RESOLVER PRÁCTICA DE INGENIERO (y módulos tipo puzzle)
# =====================================================================
## Ejercicios de manipulación de un tema (banco del módulo Puzzle y de la práctica).
func obtener_puzzles_tema(id_tema: int) -> Array:
	var lista: Array = []
	for e in bd["puzzles"]:
		if int(e["id_tema"]) == id_tema:
			lista.append(e)
	return lista

## Ejercicios que juega un módulo tipo puzzle: los de su tema, barajados.
func obtener_ejercicios_modulo(id_modulo: int) -> Array:
	var m := obtener_modulo(id_modulo)
	if m.is_empty():
		return []
	var lista := obtener_puzzles_tema(int(m.get("id_tema", 1)))
	lista.shuffle()
	return lista

## Definición (escenario) de la práctica de un tema; {} si no tiene.
func obtener_practica(id_tema: int) -> Dictionary:
	for p in bd["practicas"]:
		if int(p["id_tema"]) == id_tema:
			return p
	return {}

## Sortea los ejercicios de un intento de práctica: EJERCICIOS_PRACTICA al azar,
## primero los del tema y, si faltan, los de lógica de programación (tema 1).
func sortear_practica(id_tema: int) -> Array:
	var propios := obtener_puzzles_tema(id_tema)
	propios.shuffle()
	var lista: Array = propios.slice(0, mini(EJERCICIOS_PRACTICA, propios.size()))
	if lista.size() < EJERCICIOS_PRACTICA and id_tema != 1:
		var generales := obtener_puzzles_tema(1)
		generales.shuffle()
		for e in generales:
			if lista.size() >= EJERCICIOS_PRACTICA:
				break
			lista.append(e)
	lista.shuffle()
	return lista

## Progreso guardado de la práctica: intentos, mejor porcentaje/puntos y si el tema está dominado.
func obtener_practica_estado(id_tema: int) -> Dictionary:
	var p := obtener_practica(id_tema)
	if p.is_empty():
		return {"intentos": 0, "mejor_porcentaje": -1, "mejor_puntos": 0, "dominada": false}
	return {
		"intentos": int(p.get("intentos", 0)),
		"mejor_porcentaje": int(p.get("mejor_porcentaje", -1)),
		"mejor_puntos": int(p.get("mejor_puntos", 0)),
		"dominada": bool(p.get("dominada", false)),
	}

## Precondición del CU-11: todos los módulos del tema completados (≥ 70 %).
func practica_disponible(id_tema: int) -> bool:
	var mods := obtener_modulos_tema(id_tema)
	if mods.is_empty() or obtener_practica(id_tema).is_empty():
		return false
	return modulos_completados_tema(id_tema) >= mods.size()

func tema_dominado(id_tema: int) -> bool:
	return bool(obtener_practica_estado(id_tema)["dominada"])

func temas_dominados() -> int:
	var n := 0
	for p in bd["practicas"]:
		if p.get("dominada", false):
			n += 1
	return n

## Paso 9 del CU-11: guarda el intento de la práctica, actualiza la puntuación
## total y, si el porcentaje es ≥ 70 %, marca el tema como "Dominado".
## Al rejugar una práctica dominada, el intento solo se guarda si supera al mejor (alt. 4).
func registrar_intento_practica(id_tema: int, piezas_correctas: int, piezas_totales: int) -> Dictionary:
	var p := obtener_practica(id_tema)
	if p.is_empty():
		push_error("El tema %d no tiene práctica" % id_tema)
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
			"id_tema": id_tema,
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
	var avatares_nuevos := _evaluar_avatares()
	guardar_bd()
	return {
		"avatares_nuevos": avatares_nuevos,
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
## Todo lo que necesita la pantalla "Mi progreso" (mockup CU-06):
## puntuación total, módulos completados, dominados y áreas de mejora.
func obtener_progreso() -> Dictionary:
	var dominados: Array = []
	var mejora: Array = []
	for m in bd["modulos"]:
		var intentos_mod := obtener_intentos(int(m["id"]))
		if intentos_mod.is_empty():
			continue
		var mejor := int(m["mejor_puntaje"])
		var mejor_puntos := 0
		for i in intentos_mod:
			mejor_puntos = maxi(mejor_puntos, int(i["puntos"]))
		var tema := obtener_tema(int(m.get("id_tema", 1)))
		var fila := {
			"id": int(m["id"]),
			"nombre": m["nombre"],
			"tema": tema.get("nombre", ""),
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
		"temas_dominados": temas_dominados(),                            # CU-11
		"temas_totales": bd["temas"].size(),
	}


# =====================================================================
#  DATOS INICIALES (contenido de la materia Introducción a la Ingeniería de Software)
# =====================================================================
func _bd_inicial() -> Dictionary:
	return {
		"esquema": ESQUEMA,
		"perfil_jugador": {
			"alias": "estudiante_%04d" % (randi() % 10000),   # perfil creado automáticamente (CU-01, SRS 1.1)
			"avatar_id": "avatar_01",
			"contrasena": "",
			"puntos_totales": 0,
			"fecha_creacion": Time.get_datetime_string_from_system(),
		},
		"teoria_consultas": 0,
		# ---- CU-08: temas de la materia Introducción a la Ingeniería de Software ----
		"temas": [
			_tema(1, "Fundamentos de la ingeniería de software", "Fundamentos",
				"Qué es la ingeniería de software, crisis del software, atributos y actividades del proceso; lógica de programación básica.", "libro", "#2F55E6"),
			_tema(2, "Ciclo de vida del software", "Ciclo de vida",
				"Cascada, modelo en V, incremental, prototipado, espiral y el Manifiesto Ágil.", "reiniciar", "#178A4C"),
			_tema(3, "Requerimientos de software", "Requerimientos",
				"Elicitación, requerimientos de usuario y de sistema, historias de usuario, validación y trazabilidad.", "lapiz", "#7C3AED"),
			_tema(4, "Modelado con UML", "Modelado UML",
				"Casos de uso, clases, secuencia, actividad, estados y despliegue.", "mapa", "#0E7490"),
			_tema(5, "Diseño de software", "Diseño",
				"Abstracción, encapsulamiento, modularidad, acoplamiento, MVC, DRY/KISS y refactorización.", "puzzle", "#C2410C"),
			_tema(6, "Pruebas de software", "Pruebas",
				"Niveles de prueba, caja negra, valores límite, particiones, TDD y pruebas no funcionales.", "check", "#14633A"),
			_tema(7, "Métricas y estimación", "Métricas",
				"LOC, complejidad ciclomática, densidad de defectos, productividad, COCOMO y GQM.", "quiz", "#D97706"),
			_tema(8, "Gestión ágil con Scrum", "Gestión ágil",
				"Roles, eventos, backlog, Definition of Done, estimación ágil, burndown y Kanban.", "play", "#B45309"),
			_tema(9, "Calidad de software", "Calidad",
				"Verificación y validación, ISO/IEC 25010, revisiones e inspecciones, QA y QC.", "estrella", "#2F55E6"),
			_tema(10, "Control de versiones", "Control de versiones",
				"Git: commits, ramas, merge, repositorio remoto y pull requests.", "guardar", "#178A4C"),
			_tema(11, "Gestión de proyectos y riesgos", "Proyectos y riesgos",
				"Triple restricción, WBS, hitos y Gantt, riesgos y estrategias para enfrentarlos.", "alerta", "#7C3AED"),
			_tema(12, "Ética profesional", "Ética",
				"Código de ética ACM/IEEE, honestidad, licencias y propiedad intelectual, privacidad.", "ojo", "#0E7490"),
		],
		"ultimo_tema": 1,
		# ---- Módulos: cada tema tiene Quiz I, Quiz II y Puzzle (ids = tema*100 + n) ----
		"modulos": [
			# Tema 1 · Fundamentos de la ingeniería de software
			_modulo(101, "Quiz I · Conceptos", "quiz", "5 preguntas al azar sobre fundamentos: lo básico del tema.", "desbloqueado", 1),
			_modulo(102, "Quiz II · Aplicación", "quiz", "Otras 5 preguntas al azar del tema, con escenarios y cálculos.", "bloqueado", 1),
			_modulo(103, "Puzzle · Manos a la obra", "puzzle", "6 ejercicios para clasificar, ordenar y armar con lo aprendido.", "bloqueado", 1, 6),
			# Tema 2 · Ciclo de vida del software
			_modulo(201, "Quiz I · Conceptos", "quiz", "5 preguntas al azar sobre ciclo de vida: lo básico del tema.", "desbloqueado", 2),
			_modulo(202, "Quiz II · Aplicación", "quiz", "Otras 5 preguntas al azar del tema, con escenarios y cálculos.", "bloqueado", 2),
			_modulo(203, "Puzzle · Manos a la obra", "puzzle", "3 ejercicios para clasificar, ordenar y armar con lo aprendido.", "bloqueado", 2, 3),
			# Tema 3 · Requerimientos de software
			_modulo(301, "Quiz I · Conceptos", "quiz", "5 preguntas al azar sobre requerimientos: lo básico del tema.", "desbloqueado", 3),
			_modulo(302, "Quiz II · Aplicación", "quiz", "Otras 5 preguntas al azar del tema, con escenarios y cálculos.", "bloqueado", 3),
			_modulo(303, "Puzzle · Manos a la obra", "puzzle", "4 ejercicios para clasificar, ordenar y armar con lo aprendido.", "bloqueado", 3, 4),
			# Tema 4 · Modelado con UML
			_modulo(401, "Quiz I · Conceptos", "quiz", "5 preguntas al azar sobre modelado UML: lo básico del tema.", "desbloqueado", 4),
			_modulo(402, "Quiz II · Aplicación", "quiz", "Otras 5 preguntas al azar del tema, con escenarios y cálculos.", "bloqueado", 4),
			_modulo(403, "Puzzle · Manos a la obra", "puzzle", "4 ejercicios para clasificar, ordenar y armar con lo aprendido.", "bloqueado", 4, 4),
			# Tema 5 · Diseño de software
			_modulo(501, "Quiz I · Conceptos", "quiz", "5 preguntas al azar sobre diseño: lo básico del tema.", "desbloqueado", 5),
			_modulo(502, "Quiz II · Aplicación", "quiz", "Otras 5 preguntas al azar del tema, con escenarios y cálculos.", "bloqueado", 5),
			_modulo(503, "Puzzle · Manos a la obra", "puzzle", "4 ejercicios para clasificar, ordenar y armar con lo aprendido.", "bloqueado", 5, 4),
			# Tema 6 · Pruebas de software
			_modulo(601, "Quiz I · Conceptos", "quiz", "5 preguntas al azar sobre pruebas: lo básico del tema.", "desbloqueado", 6),
			_modulo(602, "Quiz II · Aplicación", "quiz", "Otras 5 preguntas al azar del tema, con escenarios y cálculos.", "bloqueado", 6),
			_modulo(603, "Puzzle · Manos a la obra", "puzzle", "4 ejercicios para clasificar, ordenar y armar con lo aprendido.", "bloqueado", 6, 4),
			# Tema 7 · Métricas y estimación
			_modulo(701, "Quiz I · Conceptos", "quiz", "5 preguntas al azar sobre métricas: lo básico del tema.", "desbloqueado", 7),
			_modulo(702, "Quiz II · Aplicación", "quiz", "Otras 5 preguntas al azar del tema, con escenarios y cálculos.", "bloqueado", 7),
			_modulo(703, "Puzzle · Manos a la obra", "puzzle", "3 ejercicios para clasificar, ordenar y armar con lo aprendido.", "bloqueado", 7, 3),
			# Tema 8 · Gestión ágil con Scrum
			_modulo(801, "Quiz I · Conceptos", "quiz", "5 preguntas al azar sobre gestión ágil: lo básico del tema.", "desbloqueado", 8),
			_modulo(802, "Quiz II · Aplicación", "quiz", "Otras 5 preguntas al azar del tema, con escenarios y cálculos.", "bloqueado", 8),
			_modulo(803, "Puzzle · Manos a la obra", "puzzle", "3 ejercicios para clasificar, ordenar y armar con lo aprendido.", "bloqueado", 8, 3),
			# Tema 9 · Calidad de software
			_modulo(901, "Quiz I · Conceptos", "quiz", "5 preguntas al azar sobre calidad: lo básico del tema.", "desbloqueado", 9),
			_modulo(902, "Quiz II · Aplicación", "quiz", "Otras 5 preguntas al azar del tema, con escenarios y cálculos.", "bloqueado", 9),
			_modulo(903, "Puzzle · Manos a la obra", "puzzle", "3 ejercicios para clasificar, ordenar y armar con lo aprendido.", "bloqueado", 9, 3),
			# Tema 10 · Control de versiones
			_modulo(1001, "Quiz I · Conceptos", "quiz", "5 preguntas al azar sobre control de versiones: lo básico del tema.", "desbloqueado", 10),
			_modulo(1002, "Quiz II · Aplicación", "quiz", "Otras 5 preguntas al azar del tema, con escenarios y cálculos.", "bloqueado", 10),
			_modulo(1003, "Puzzle · Manos a la obra", "puzzle", "3 ejercicios para clasificar, ordenar y armar con lo aprendido.", "bloqueado", 10, 3),
			# Tema 11 · Gestión de proyectos y riesgos
			_modulo(1101, "Quiz I · Conceptos", "quiz", "5 preguntas al azar sobre proyectos y riesgos: lo básico del tema.", "desbloqueado", 11),
			_modulo(1102, "Quiz II · Aplicación", "quiz", "Otras 5 preguntas al azar del tema, con escenarios y cálculos.", "bloqueado", 11),
			_modulo(1103, "Puzzle · Manos a la obra", "puzzle", "3 ejercicios para clasificar, ordenar y armar con lo aprendido.", "bloqueado", 11, 3),
			# Tema 12 · Ética profesional
			_modulo(1201, "Quiz I · Conceptos", "quiz", "5 preguntas al azar sobre ética: lo básico del tema.", "desbloqueado", 12),
			_modulo(1202, "Quiz II · Aplicación", "quiz", "Otras 5 preguntas al azar del tema, con escenarios y cálculos.", "bloqueado", 12),
			_modulo(1203, "Puzzle · Manos a la obra", "puzzle", "2 ejercicios para clasificar, ordenar y armar con lo aprendido.", "bloqueado", 12, 2),
		],
		# ---- Banco de preguntas: 15 por tema (5 se sortean en cada intento) ----
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
			# ---- Tema 1 · banco Sprint 3 ----
			_reactivo(71, 1, "¿Qué fue la «crisis del software»?",
				["Una caída mundial de internet", "La falta de computadoras en las universidades", "Un virus que borró sistemas en los años 80", "Una época en que muchos proyectos se entregaban tarde, costaban de más y fallaban"], 3,
				"En los años 60 y 70 muchos proyectos se salían de tiempo y presupuesto; por eso nació la ingeniería de software.", "crisis_software"),
			_reactivo(72, 1, "¿En qué evento se popularizó el término «ingeniería de software»?",
				["Una conferencia de la OTAN en 1968", "La fundación de Google en 1998", "El lanzamiento de Windows en 1985", "La creación de la web en 1991"], 0,
				"La conferencia de la OTAN de 1968 propuso tratar el software con métodos de ingeniería.", "crisis_software"),
			_reactivo(73, 1, "Además del código, ¿qué forma parte de un producto de software?",
				["Solo el código fuente", "El salario de los programadores", "La documentación y los datos de configuración", "El celular donde se instala"], 2,
				"El software incluye el código, su documentación y los datos de configuración que necesita.", "producto_software"),
			_reactivo(74, 1, "Un procesador de textos que se vende a cualquier persona es un producto:",
				["Genérico", "Embebido", "Experimental", "A la medida"], 0,
				"Los productos genéricos se venden a muchos clientes; los a la medida se hacen para uno solo.", "producto_software"),
			_reactivo(75, 1, "¿Cuáles son las cuatro actividades básicas de todo proceso de software?",
				["Diseño, dibujo, impresión y entrega", "Compilar, ejecutar, depurar e instalar", "Venta, compra, cobro y soporte", "Especificación, desarrollo, validación y evolución"], 3,
				"Todo proceso define qué hacer, lo construye, lo comprueba y lo cambia con el tiempo.", "actividades_proceso"),
			_reactivo(76, 1, "Comprobar que el sistema hace lo que el cliente pidió corresponde a la actividad de:",
				["Especificación", "Validación", "Evolución", "Instalación"], 1,
				"La validación comprueba que el software cumple con lo que el cliente necesita.", "actividades_proceso"),
			_reactivo(77, 1, "Que el software se pueda modificar fácilmente cuando cambian las necesidades es:",
				["Aceptabilidad", "Eficiencia", "Mantenibilidad", "Portabilidad"], 2,
				"La mantenibilidad es la facilidad con que el software puede cambiar y evolucionar.", "atributos_software"),
			_reactivo(78, 1, "Que una app no desperdicie memoria ni batería se relaciona con:",
				["Eficiencia", "Confiabilidad", "Aceptabilidad", "Mantenibilidad"], 0,
				"La eficiencia es usar bien los recursos: procesador, memoria y batería.", "atributos_software"),
			_reactivo(79, 1, "En sistemas que se usan durante muchos años, ¿qué etapa suele costar más en total?",
				["La primera reunión con el cliente", "La instalación", "El mantenimiento y la evolución", "La elección del logotipo"], 2,
				"Los sistemas siguen cambiando años después de entregarse; esos cambios suelen costar más que el desarrollo inicial.", "mantenimiento"),
			_reactivo(80, 1, "¿En qué se diferencia la ingeniería de software de las ciencias de la computación?",
				["No tiene relación con la programación", "Se enfoca en las prácticas para construir y entregar software útil", "Solo estudia el hardware", "Se dedica únicamente a la teoría matemática"], 1,
				"Las ciencias de la computación estudian la teoría; la ingeniería de software, cómo desarrollar software de calidad en la práctica.", "ing_software"),
			# ---- Tema 2 · banco Sprint 3 ----
			_reactivo(81, 2, "¿Cuál es la principal desventaja del modelo en cascada?",
				["Solo sirve para videojuegos", "No incluye una fase de pruebas", "Es difícil responder a cambios en los requerimientos cuando el proyecto ya avanzó", "Obliga a entregar algo cada semana"], 2,
				"En cascada cada fase se cierra antes de la siguiente; volver atrás por un cambio es costoso.", "cascada"),
			_reactivo(82, 2, "¿Cuándo conviene usar el modelo en cascada?",
				["Cuando hay mucha incertidumbre técnica", "Cuando los requerimientos son claros y casi no van a cambiar", "Cuando se quiere entregar cada dos semanas", "Cuando el cliente no sabe qué quiere"], 1,
				"Cascada funciona bien si los requerimientos están definidos y estables desde el inicio.", "cascada"),
			_reactivo(83, 2, "En el modelo en V, cada fase de desarrollo se relaciona con:",
				["Una versión del sistema operativo", "Un nivel de prueba correspondiente", "Un lenguaje de programación", "Un integrante distinto del equipo"], 1,
				"El modelo en V asocia cada fase de construcción con la prueba que la valida.", "modelo_v"),
			_reactivo(84, 2, "En el modelo en V, los requerimientos del cliente se validan con:",
				["Pruebas unitarias", "Pruebas de aceptación", "Revisión del logotipo", "Pruebas de compilación"], 1,
				"Lo más cercano al cliente (requerimientos) se comprueba con la prueba más cercana al cliente (aceptación).", "modelo_v"),
			_reactivo(85, 2, "¿Qué ventaja tiene el desarrollo incremental?",
				["No necesita pruebas", "Todo se entrega en una sola fecha final", "El cliente recibe partes funcionales pronto y puede opinar sobre ellas", "Nunca cambian los requerimientos"], 2,
				"Cada incremento entrega funcionalidad útil y permite ajustar el rumbo con la opinión del cliente.", "iterativo"),
			_reactivo(86, 2, "¿Cuál es un riesgo del modelo de prototipado?",
				["Que el cliente crea que el prototipo ya es el producto terminado", "Que el prototipo sea demasiado caro", "Que impida hablar con los usuarios", "Que no se pueda mostrar al cliente"], 0,
				"Un prototipo se ve funcional, pero no tiene la calidad del producto final; hay que dejarlo claro.", "prototipado"),
			_reactivo(87, 2, "Un prototipo desechable es aquel que:",
				["Se construye para entender los requerimientos y después se descarta", "Se guarda sin mostrarlo a nadie", "Se vende al cliente como versión final", "Se usa solo para pruebas de carga"], 0,
				"El prototipo desechable sirve para aprender qué quiere el cliente; luego el sistema se construye bien.", "prototipado"),
			_reactivo(88, 2, "Un sistema bancario grande, con mucha incertidumbre técnica y alto costo si falla. ¿Qué modelo conviene?",
				["Big Bang", "Codificar y corregir", "Cascada", "Espiral"], 3,
				"El modelo en espiral analiza los riesgos en cada vuelta; es ideal para proyectos grandes y riesgosos.", "espiral"),
			_reactivo(89, 2, "Un cliente no tiene claro qué necesita y quiere ver algo antes de decidir. ¿Qué modelo conviene?",
				["Prototipado", "Big Bang", "Cascada", "Modelo en V"], 0,
				"El prototipado permite que el cliente vea y pruebe una versión preliminar para aclarar sus necesidades.", "prototipado"),
			_reactivo(90, 2, "El Manifiesto Ágil valora más:",
				["A los procesos que a las personas", "A seguir un plan que a responder al cambio", "A los contratos que a la colaboración con el cliente", "Al software funcionando que a la documentación extensa"], 3,
				"El Manifiesto Ágil prioriza el software que funciona, sin despreciar la documentación.", "agil"),
			# ---- Tema 3 · banco Sprint 3 ----
			_reactivo(91, 3, "¿Qué técnica de elicitación consiste en observar al usuario mientras trabaja?",
				["Etnografía u observación", "Cuestionario", "Lluvia de ideas", "Compilación"], 0,
				"Observar al usuario en su entorno revela necesidades que no menciona en una entrevista.", "elicitacion"),
			_reactivo(92, 3, "¿Cuál requerimiento está mejor escrito?",
				["El sistema será rápido", "El sistema funcionará bien", "El sistema mostrará los resultados de la búsqueda en menos de 3 segundos", "La interfaz será amigable"], 2,
				"Un buen requerimiento es medible y verificable; «rápido» o «amigable» no se pueden probar.", "verificabilidad"),
			_reactivo(93, 3, "¿Para quién se escriben los requerimientos de usuario?",
				["Solo para los probadores", "Para el sistema operativo", "Para el cliente, en lenguaje natural", "Para el compilador"], 2,
				"Los requerimientos de usuario se escriben para que el cliente los entienda; los de sistema dan el detalle técnico.", "req_usuario_sistema"),
			_reactivo(94, 3, "Validar los requerimientos significa:",
				["Contar cuántas páginas tiene el SRS", "Traducirlos a inglés", "Programarlos lo más rápido posible", "Comprobar que describen lo que el cliente realmente necesita"], 3,
				"La validación confirma con el cliente que lo escrito es lo que necesita.", "validacion_req"),
			_reactivo(95, 3, "¿Qué técnica sirve para validar requerimientos?",
				["Medir las líneas de código", "Instalar la app en un servidor", "Cambiar el lenguaje de programación", "Revisarlos junto con el cliente"], 3,
				"Las revisiones con el cliente y los prototipos son las técnicas más usadas para validar requerimientos.", "validacion_req"),
			_reactivo(96, 3, "Si un error en los requerimientos se descubre hasta la etapa de pruebas:",
				["Corregirlo cuesta mucho más que si se hubiera detectado al especificar", "Ya no se puede corregir", "Se corrige solo", "Cuesta lo mismo corregirlo en cualquier etapa"], 0,
				"Mientras más tarde se encuentra un error de requerimientos, más trabajo hay que rehacer.", "validacion_req"),
			_reactivo(97, 3, "¿Cuál es el formato de una historia de usuario?",
				["Entrada, salida y error", "Como (rol), quiero (acción), para (beneficio)", "Inicio, proceso y fin", "Si (condición), entonces (acción)"], 1,
				"Una historia de usuario dice quién lo pide, qué quiere y para qué le sirve.", "historia_usuario"),
			_reactivo(98, 3, "En la priorización MoSCoW, un requerimiento «Must have» es:",
				["Uno que no se hará", "Un requerimiento del diseño gráfico", "Opcional si sobra tiempo", "Indispensable para la entrega"], 3,
				"Must = sin él no se puede entregar; Should = importante; Could = deseable; Won't = no en esta entrega.", "priorizacion"),
			_reactivo(99, 3, "«La app debe estar disponible el 99 % del tiempo» es un requerimiento no funcional de:",
				["Disponibilidad", "Usabilidad", "Funcionalidad", "Portabilidad"], 0,
				"Es una cualidad del sistema (disponibilidad), no una acción que realiza.", "req_no_funcional"),
			_reactivo(100, 3, "¿Qué es la trazabilidad de requerimientos?",
				["Dibujar la interfaz a mano", "Poder seguir cada requerimiento hasta su diseño, su código y sus pruebas", "Borrar los requerimientos que no gustan", "Contar los requerimientos del SRS"], 1,
				"La trazabilidad, normalmente en una matriz, une cada requerimiento con lo que lo implementa y lo prueba.", "trazabilidad"),
			# ---- Tema 4 · banco Sprint 3 ----
			_reactivo(101, 4, "En un diagrama de casos de uso, «include» indica que:",
				["Un actor hereda de otro actor", "Un caso de uso a veces agrega un comportamiento opcional", "El sistema se conecta a internet", "Un caso de uso siempre incorpora el comportamiento de otro"], 3,
				"«Include» es obligatorio: «Pagar» siempre incluye «Validar tarjeta».", "include_extend"),
			_reactivo(102, 4, "«Aplicar cupón de descuento» ocurre solo si el usuario tiene un cupón. Respecto a «Pagar», ¿qué relación es?",
				["«extend»", "Herencia entre actores", "Composición", "«include»"], 0,
				"«Extend» se usa para comportamiento opcional que solo ocurre bajo cierta condición.", "include_extend"),
			_reactivo(103, 4, "En un diagrama de clases, el símbolo «−» antes de un atributo significa que es:",
				["Privado", "Público", "Estático", "Protegido"], 0,
				"En UML: + público, − privado, # protegido.", "diag_clases"),
			_reactivo(104, 4, "En un diagrama de clases, la multiplicidad «1..*» significa:",
				["Ninguno", "Uno o más", "Exactamente uno", "Cero o uno"], 1,
				"«1..*» indica que debe haber al menos uno y puede haber muchos.", "diag_clases"),
			_reactivo(105, 4, "Una Casa tiene Habitaciones; si se destruye la casa, las habitaciones dejan de existir. ¿Qué relación es?",
				["Herencia", "Dependencia", "Agregación", "Composición"], 3,
				"En la composición la parte no existe sin el todo; se dibuja con rombo relleno.", "herencia"),
			_reactivo(106, 4, "¿Qué diagrama muestra los estados de un objeto y cómo pasa de uno a otro?",
				["Diagrama de clases", "Diagrama de despliegue", "Diagrama de estados", "Diagrama de casos de uso"], 2,
				"El diagrama de estados muestra estados, eventos y transiciones.", "diag_estados"),
			_reactivo(107, 4, "Quieres mostrar que un pedido pasa por creado, pagado, enviado y entregado. ¿Qué diagrama usas?",
				["Diagrama de paquetes", "Diagrama de componentes", "Diagrama de estados", "Diagrama de clases"], 2,
				"Cuando algo cambia de estado a lo largo del tiempo, se usa el diagrama de estados.", "diag_estados"),
			_reactivo(108, 4, "¿Qué diagrama muestra en qué celulares o servidores se ejecuta cada parte del sistema?",
				["Diagrama de despliegue", "Diagrama de secuencia", "Diagrama de actividad", "Diagrama de casos de uso"], 0,
				"El diagrama de despliegue muestra los nodos físicos y sus conexiones.", "diag_despliegue"),
			_reactivo(109, 4, "¿Cuál de estos es un diagrama de comportamiento?",
				["Diagrama de despliegue", "Diagrama de clases", "Diagrama de componentes", "Diagrama de secuencia"], 3,
				"Secuencia, actividad, casos de uso y estados muestran comportamiento; clases, componentes y despliegue, estructura.", "uml_tipos"),
			_reactivo(110, 4, "¿Qué significan las siglas UML?",
				["Lenguaje de Usuario Móvil", "Lenguaje Unificado de Modelado", "Lenguaje Universal de Máquinas", "Lista Única de Módulos"], 1,
				"UML es el Unified Modeling Language: una notación estándar para modelar software.", "uml_tipos"),
			# ---- Tema 5 · banco Sprint 3 ----
			_reactivo(111, 5, "Usar un método «enviarCorreo()» sin saber cómo se conecta al servidor es un ejemplo de:",
				["Redundancia", "Herencia", "Acoplamiento", "Abstracción"], 3,
				"La abstracción permite usar algo por lo que hace, sin conocer sus detalles internos.", "abstraccion"),
			_reactivo(112, 5, "Que una clase esconda sus datos y solo exponga métodos para usarlos se llama:",
				["Duplicación", "Encapsulamiento", "Compilación", "Polimorfismo"], 1,
				"El encapsulamiento protege los datos internos y expone solo una interfaz.", "ocultamiento"),
			_reactivo(113, 5, "Una clase que solo se encarga de las operaciones de facturación tiene:",
				["Baja cohesión", "Alta redundancia", "Alta cohesión", "Alto acoplamiento"], 2,
				"Alta cohesión: todo lo que hace la clase está relacionado con una sola tarea.", "acoplamiento"),
			_reactivo(114, 5, "Si al cambiar la clase Pago tienes que modificar otras diez clases, el diseño tiene:",
				["Buena modularidad", "Alto acoplamiento", "Bajo acoplamiento", "Alta cohesión"], 1,
				"Cuando un cambio obliga a cambiar muchas otras partes, las clases dependen demasiado entre sí.", "acoplamiento"),
			_reactivo(115, 5, "Copiar y pegar la misma validación en cinco pantallas viola el principio:",
				["Singleton", "KISS (Mantenlo simple)", "MVC", "DRY (No te repitas)"], 3,
				"DRY pide tener cada lógica en un solo lugar para cambiarla una sola vez.", "dry_kiss"),
			_reactivo(116, 5, "El principio KISS recomienda:",
				["Repetir el código para que sea más claro", "Usar siempre el patrón más complejo", "Agregar todas las funciones posibles", "Elegir la solución más sencilla que funcione"], 3,
				"KISS: «Keep it simple». Lo simple es más fácil de entender, probar y mantener.", "dry_kiss"),
			_reactivo(117, 5, "Dividir el sistema en partes con funciones bien definidas que se prueban por separado se llama:",
				["Compilación", "Duplicación", "Modularidad", "Monolitismo"], 2,
				"La modularidad permite construir, probar y cambiar cada parte de forma independiente.", "modularidad"),
			_reactivo(118, 5, "El diseño arquitectónico define:",
				["Los componentes principales del sistema y cómo se comunican", "El precio de la aplicación", "El color de cada botón", "Los nombres de las variables"], 0,
				"La arquitectura es la vista general; el diseño detallado define cada componente por dentro.", "niveles_diseno"),
			_reactivo(119, 5, "Refactorizar el código significa:",
				["Mejorar su estructura interna sin cambiar lo que hace", "Borrar las pruebas", "Agregar funciones nuevas", "Traducirlo a otro lenguaje"], 0,
				"Refactorizar es ordenar y limpiar el código manteniendo su comportamiento.", "refactorizacion"),
			_reactivo(120, 5, "En MVC, ¿qué parte recibe las acciones del usuario y decide qué hacer con ellas?",
				["El modelo", "El controlador", "La base de datos", "La vista"], 1,
				"El controlador recibe la acción, actualiza el modelo y elige qué vista mostrar.", "mvc"),
			# ---- Tema 6 · banco Sprint 3 ----
			_reactivo(121, 6, "¿Qué verifica una prueba de integración?",
				["El diseño gráfico de la app", "Que el cliente apruebe la entrega", "Una sola función aislada", "Que varios módulos funcionen bien juntos"], 3,
				"La integración prueba la comunicación entre módulos que ya pasaron sus pruebas unitarias.", "aceptacion"),
			_reactivo(122, 6, "Un programador escribe «>» en lugar de «>=». Lo que queda en el código es:",
				["Una falla", "Un defecto", "Una prueba", "Un requerimiento"], 1,
				"La equivocación de la persona es el error; lo que queda mal en el código es el defecto.", "error_defecto_falla"),
			_reactivo(123, 6, "Al usar la app, el total del carrito sale mal. Lo que observa el usuario es:",
				["Un defecto", "Una falla", "Una inspección", "Un error de requerimientos"], 1,
				"La falla es el comportamiento incorrecto que se ve al ejecutar un defecto.", "error_defecto_falla"),
			_reactivo(124, 6, "Un campo acepta edades de 18 a 60. ¿Qué valores conviene probar según el análisis de valores límite?",
				["20, 30, 40 y 50", "17, 18, 60 y 61", "Solo 18", "1, 2, 3 y 4"], 1,
				"Los defectos suelen estar en los bordes: se prueba justo afuera y justo adentro de cada límite.", "valores_limite"),
			_reactivo(125, 6, "Las particiones de equivalencia consisten en:",
				["Probar solo los valores válidos", "Dividir el equipo en dos", "Agrupar entradas que se tratan igual y probar un valor de cada grupo", "Probar todos los valores posibles"], 2,
				"Si el sistema trata igual a todos los valores de un grupo, basta con probar uno representativo.", "particiones"),
			_reactivo(126, 6, "Las pruebas de caja blanca se diseñan:",
				["Sin conocer el código", "Solo con el manual de usuario", "Únicamente por el cliente", "Conociendo el código interno"], 3,
				"La caja blanca revisa caminos y condiciones del código; la caja negra solo entradas y salidas.", "caja_negra"),
			_reactivo(127, 6, "Las pruebas beta las realizan:",
				["Usuarios reales en su propio entorno, antes del lanzamiento", "Los diseñadores gráficos", "El compilador automáticamente", "Solo los programadores, en su computadora"], 0,
				"Las pruebas alfa se hacen en el lugar del desarrollador; las beta, con usuarios reales en su entorno.", "aceptacion"),
			_reactivo(128, 6, "En el desarrollo guiado por pruebas (TDD):",
				["Las pruebas las escribe el cliente", "Primero se escribe el código y nunca se prueba", "Primero se escribe la prueba y después el código", "Solo se prueba al final del proyecto"], 2,
				"TDD sigue el ciclo: prueba que falla → código que la pasa → refactorizar.", "tdd"),
			_reactivo(129, 6, "¿Cuál afirmación sobre las pruebas es correcta?",
				["Pueden mostrar que hay defectos, pero no que no exista ninguno", "Si pasan todas, el software no tiene errores", "Se puede probar cualquier programa con todas sus entradas", "Solo deben hacerse al final del proyecto"], 0,
				"Probar todo es imposible: las pruebas muestran la presencia de defectos, no su ausencia.", "principios_prueba"),
			_reactivo(130, 6, "Simular 10 000 usuarios conectados a la vez para ver cuándo falla el servidor es una prueba de:",
				["Aceptación", "Unidad", "Usabilidad", "Estrés"], 3,
				"La prueba de estrés lleva el sistema más allá de su carga esperada para ver cómo falla.", "pruebas_no_funcionales"),
			# ---- Tema 7 · banco Sprint 3 ----
			_reactivo(131, 7, "Un programa tiene dos «if» independientes, uno después del otro, sin anidar. ¿Cuál es su complejidad ciclomática?",
				["2", "3", "1", "4"], 1,
				"Complejidad ciclomática = número de decisiones + 1 = 2 + 1 = 3.", "ciclomatica"),
			_reactivo(132, 7, "Un grafo de flujo tiene 9 aristas y 7 nodos. Con V(G) = E − N + 2, ¿cuál es su complejidad ciclomática?",
				["18", "16", "4", "2"], 2,
				"V(G) = 9 − 7 + 2 = 4 caminos independientes.", "ciclomatica"),
			_reactivo(133, 7, "Un sistema de 15 000 líneas de código tiene 30 defectos. ¿Cuál es su densidad de defectos?",
				["30 defectos por KLOC", "2 defectos por KLOC", "0.5 defectos por KLOC", "15 defectos por KLOC"], 1,
				"15 000 líneas = 15 KLOC; 30 ÷ 15 = 2 defectos por cada mil líneas.", "densidad_defectos"),
			_reactivo(134, 7, "Un equipo escribió 2 400 líneas de código con 3 meses-persona de esfuerzo. ¿Cuál fue su productividad?",
				["2 400 líneas por mes-persona", "300 líneas por mes-persona", "800 líneas por mes-persona", "7 200 líneas por mes-persona"], 2,
				"Productividad = tamaño ÷ esfuerzo = 2 400 ÷ 3 = 800.", "productividad"),
			_reactivo(135, 7, "¿Por qué las líneas de código no sirven para comparar la productividad entre lenguajes distintos?",
				["Porque solo miden la calidad", "Porque todos los lenguajes usan las mismas líneas", "Porque no se pueden contar", "La misma función requiere distinto número de líneas en cada lenguaje"], 3,
				"Un lenguaje de alto nivel hace lo mismo en menos líneas; contar líneas castiga al más expresivo.", "loc"),
			_reactivo(136, 7, "Al cierre de la semana, EV = 40 % y PV = 50 %. ¿Cuánto vale el SPI y qué significa?",
				["0.8: el proyecto va atrasado", "1: el proyecto va en tiempo", "1.25: el proyecto va adelantado", "0.8: el proyecto va adelantado"], 0,
				"SPI = EV ÷ PV = 40 ÷ 50 = 0.8; menor que 1 significa atraso.", "valor_ganado"),
			_reactivo(137, 7, "El trabajo terminado vale 60 h según el plan (EV) y el equipo gastó 50 h reales (AC). ¿Cuánto vale el CPI?",
				["1.2: se gastó menos de lo planeado", "1.2: se gastó más de lo planeado", "0.83: se gastó más de lo planeado", "10: el proyecto va en tiempo"], 0,
				"CPI = EV ÷ AC = 60 ÷ 50 = 1.2; mayor que 1 significa que se gastó menos de lo planeado por lo que se hizo.", "valor_ganado"),
			_reactivo(138, 7, "«Tiempo promedio que tarda el equipo en corregir un defecto» es una métrica de:",
				["Proceso", "Usuario final", "Producto", "Hardware"], 0,
				"Mide cómo trabaja el equipo (el proceso), no el software en sí.", "tipos_metricas"),
			_reactivo(139, 7, "En el enfoque GQM, ¿qué se define primero?",
				["La métrica más fácil de obtener", "La herramienta para medir", "La gráfica del reporte", "La meta que se quiere alcanzar"], 3,
				"GQM = Goal, Question, Metric: primero la meta, luego las preguntas y al final las métricas.", "tipos_metricas"),
			_reactivo(140, 7, "¿Qué estima el modelo COCOMO?",
				["La cantidad de usuarios que tendrá la app", "El esfuerzo y la duración de un proyecto a partir de su tamaño", "El precio de venta del software", "La complejidad ciclomática de una función"], 1,
				"COCOMO estima meses-persona y duración a partir de las KLOC estimadas.", "estimacion_esfuerzo"),
			# ---- Tema 8 · banco Sprint 3 ----
			_reactivo(141, 8, "¿Cuál es la función principal del Scrum Master?",
				["Priorizar el Product Backlog", "Aprobar el presupuesto del cliente", "Facilitar el trabajo del equipo y ayudar a eliminar impedimentos", "Programar todas las historias"], 2,
				"El Scrum Master sirve al equipo: facilita los eventos y quita obstáculos.", "product_owner"),
			_reactivo(142, 8, "¿En qué evento el equipo muestra el incremento a los interesados para recibir retroalimentación?",
				["Sprint Planning", "Daily Scrum", "Sprint Retrospective", "Sprint Review"], 3,
				"En la Sprint Review se revisa el producto; en la Retrospective, la forma de trabajar.", "daily"),
			_reactivo(143, 8, "¿En qué evento se decide qué se hará durante el sprint?",
				["Sprint Retrospective", "Sprint Planning", "Sprint Review", "Daily Scrum"], 1,
				"En el Sprint Planning el equipo elige qué elementos del backlog entran y cómo los hará.", "daily"),
			_reactivo(144, 8, "La Definition of Done (DoD) es:",
				["La fecha de entrega final", "El nombre del último sprint", "El acuerdo del equipo sobre qué debe cumplir algo para considerarse terminado", "La lista de errores pendientes"], 2,
				"Si un elemento no cumple la DoD (por ejemplo, pruebas aprobadas), no está terminado.", "dod"),
			_reactivo(145, 8, "El incremento en Scrum es:",
				["El aumento de sueldo del equipo", "La suma de lo terminado en el sprint, en una versión utilizable", "El número de reuniones del sprint", "La cantidad de errores encontrados"], 1,
				"El incremento es producto que funciona y cumple la DoD.", "dod"),
			_reactivo(146, 8, "Planning Poker es una técnica para:",
				["Estimar en equipo el esfuerzo de las historias", "Asignar sueldos", "Jugar durante la retrospectiva", "Decidir quién es el Scrum Master"], 0,
				"Cada integrante muestra su estimación con una carta y se discuten las diferencias.", "estimacion_agil"),
			_reactivo(147, 8, "Los puntos de historia miden:",
				["Las horas exactas de trabajo", "El esfuerzo y la complejidad relativa de una historia", "La cantidad de usuarios", "El número de líneas de código"], 1,
				"Son una medida relativa: una historia de 8 puntos cuesta más o menos el doble que una de 4.", "estimacion_agil"),
			_reactivo(148, 8, "En tres sprints el equipo terminó 18, 22 y 20 puntos. ¿Cuál es su velocidad promedio?",
				["20 puntos por sprint", "22 puntos por sprint", "18 puntos por sprint", "60 puntos por sprint"], 0,
				"Velocidad = (18 + 22 + 20) ÷ 3 = 20 puntos por sprint.", "estimacion_agil"),
			_reactivo(149, 8, "En una gráfica burndown, la línea real queda por encima de la ideal. Eso indica que:",
				["No hay trabajo pendiente", "El equipo va adelantado", "El sprint ya terminó", "El equipo va atrasado"], 3,
				"Por encima de la línea ideal = queda más trabajo del que debería a esa altura del sprint.", "burndown"),
			_reactivo(150, 8, "En Kanban, ¿para qué sirve limitar el trabajo en curso (WIP)?",
				["Para terminar tareas antes de empezar otras y evitar cuellos de botella", "Para que el equipo trabaje menos horas", "Para que no haya prioridades", "Para eliminar la columna «Hecho»"], 0,
				"Con menos tareas a medias, el trabajo fluye y los bloqueos se ven rápido.", "kanban"),
			# ---- Tema 9 · banco Sprint 3 ----
			_reactivo(151, 9, "La verificación responde a la pregunta:",
				["¿Cuánto cuesta el producto?", "¿Estamos construyendo el producto correctamente?", "¿Estamos construyendo el producto correcto?", "¿Quién usará el producto?"], 1,
				"Verificar = comprobar contra la especificación.", "verif_valid"),
			_reactivo(152, 9, "La validación responde a la pregunta:",
				["¿Estamos construyendo el producto correctamente?", "¿En qué lenguaje se programa?", "¿Estamos construyendo el producto correcto?", "¿Cuántas líneas tiene el código?"], 2,
				"Validar = comprobar que el producto sirve para lo que el usuario necesita.", "verif_valid"),
			_reactivo(153, 9, "Mostrar el prototipo a los alumnos para ver si la app les ayuda a estudiar es una actividad de:",
				["Refactorización", "Compilación", "Validación", "Verificación"], 2,
				"Se comprueba contra la necesidad real del usuario: eso es validación.", "verif_valid"),
			_reactivo(154, 9, "¿Qué norma define características de calidad del producto de software como usabilidad y mantenibilidad?",
				["ISO/IEC 25010", "IEEE 802.11", "ISO/IEC 29110", "ISO 14001"], 0,
				"ISO/IEC 25010 es el modelo de calidad del producto; ISO/IEC 29110 trata de procesos para equipos pequeños.", "iso25010"),
			_reactivo(155, 9, "Que un usuario nuevo aprenda a usar la app sin ayuda es una característica de:",
				["Portabilidad", "Eficiencia", "Mantenibilidad", "Usabilidad"], 3,
				"La usabilidad es qué tan fácil es aprender y usar el sistema.", "iso25010"),
			_reactivo(156, 9, "Que la app funcione en distintos modelos de celular Android se relaciona con:",
				["Seguridad", "Portabilidad", "Adecuación funcional", "Usabilidad"], 1,
				"La portabilidad es la facilidad para llevar el software a otros entornos.", "iso25010"),
			_reactivo(157, 9, "Una app que no pierde el progreso aunque se cierre de golpe tiene buena:",
				["Usabilidad", "Fiabilidad", "Portabilidad", "Compatibilidad"], 1,
				"La fiabilidad incluye tolerar fallas y recuperarse sin perder datos.", "iso25010"),
			_reactivo(158, 9, "Una inspección de código es:",
				["Una revisión en grupo del código para encontrar defectos sin ejecutarlo", "Ejecutar el programa con muchos usuarios", "Medir cuánta batería usa la app", "Instalar la app en la tienda"], 0,
				"Las inspecciones son revisiones estáticas: se lee el código buscando defectos.", "revisiones"),
			_reactivo(159, 9, "El aseguramiento de la calidad (QA) se enfoca en:",
				["Las ventas del producto", "El diseño del logotipo", "El proceso, para prevenir defectos", "Solo en ejecutar pruebas al final"], 2,
				"QA define y vigila buenas prácticas para que los defectos no se produzcan.", "qa_qc"),
			_reactivo(160, 9, "El control de calidad (QC) se enfoca en:",
				["El proceso, para prevenir defectos", "El precio del software", "La contratación del equipo", "El producto, para detectar defectos"], 3,
				"QC revisa y prueba el producto terminado o en construcción para encontrar defectos.", "qa_qc"),
			# ---- Tema 10 · banco Sprint 3 ----
			_reactivo(161, 10, "¿Para qué sirve un sistema de control de versiones?",
				["Para registrar cada cambio del código y poder volver a versiones anteriores", "Para diseñar la interfaz", "Para enviar correos al cliente", "Para compilar el programa más rápido"], 0,
				"Guarda el historial de cambios: quién cambió qué, cuándo y por qué.", "control_versiones"),
			_reactivo(162, 10, "¿Cuál de estos es un sistema de control de versiones?",
				["Excel", "Godot", "Android", "Git"], 3,
				"Git es el sistema de control de versiones más usado; GitHub aloja repositorios de Git.", "control_versiones"),
			_reactivo(163, 10, "Un commit es:",
				["Un archivo que se borra", "Una instantánea de los cambios guardada en el historial con un mensaje", "Un error del compilador", "Una reunión del equipo"], 1,
				"Cada commit queda en el historial y se puede consultar o recuperar después.", "commit_git"),
			_reactivo(164, 10, "¿Cuál es el mejor mensaje de commit?",
				["cambios", "ya quedó", "Agrega validación del alias de 3 a 20 caracteres", "asdf"], 2,
				"Un buen mensaje dice qué cambió, para que cualquiera lo entienda sin abrir el código.", "commit_git"),
			_reactivo(165, 10, "¿Para qué sirve crear una rama?",
				["Para trabajar en una funcionalidad sin afectar la versión principal", "Para compilar el proyecto", "Para borrar el historial", "Para cambiar el lenguaje del proyecto"], 0,
				"Cada funcionalidad puede desarrollarse en su rama y unirse a main cuando esté lista.", "ramas"),
			_reactivo(166, 10, "Un conflicto de fusión ocurre cuando:",
				["El repositorio no tiene archivos", "Dos ramas cambiaron las mismas líneas de un archivo de forma distinta", "Se crea una rama nueva", "Se hace un commit sin mensaje"], 1,
				"Git no sabe qué versión conservar, así que una persona debe decidir.", "merge"),
			_reactivo(167, 10, "¿Qué comando sube tus commits al repositorio remoto?",
				["git status", "git push", "git init", "git pull"], 1,
				"push sube tus cambios; pull trae los cambios de los demás.", "repo_remoto"),
			_reactivo(168, 10, "¿Qué comando trae a tu computadora los cambios que subieron tus compañeros?",
				["git add", "git commit", "git pull", "git push"], 2,
				"git pull descarga y une los cambios del repositorio remoto con tu copia.", "repo_remoto"),
			_reactivo(169, 10, "Un pull request sirve para:",
				["Pedir que el equipo revise los cambios de una rama antes de integrarlos", "Crear un usuario en GitHub", "Borrar una rama remota", "Descargar Git"], 0,
				"El pull request permite revisar y comentar el código antes de unirlo a main.", "repo_remoto"),
			_reactivo(170, 10, "La gestión de configuración del software se encarga de:",
				["Configurar el brillo de la pantalla", "Elegir los colores de la app", "Instalar el sistema operativo", "Controlar las versiones y los cambios de todo el proyecto, código y documentos"], 3,
				"Controla qué versión de cada elemento forma parte de cada entrega.", "control_versiones"),
			# ---- Tema 11 · banco Sprint 3 ----
			_reactivo(171, 11, "La triple restricción de un proyecto está formada por:",
				["Código, diseño y pruebas", "Cliente, equipo y profesor", "Requerimientos, UML y SRS", "Alcance, tiempo y costo"], 3,
				"Alcance, tiempo y costo se equilibran entre sí; la calidad depende de ese equilibrio.", "triple_restriccion"),
			_reactivo(172, 11, "El cliente pide más funciones sin mover la fecha ni el presupuesto. ¿Qué suele pasar?",
				["El costo baja automáticamente", "Se arriesga la calidad o el equipo se sobrecarga", "El proyecto termina antes", "No pasa nada"], 1,
				"Si crece el alcance, debe ajustarse el tiempo o el costo; si no, la calidad sufre.", "triple_restriccion"),
			_reactivo(173, 11, "Un riesgo es:",
				["Un problema que ya ocurrió", "Una tarea terminada", "Un requerimiento del cliente", "Un evento incierto que, si ocurre, afecta al proyecto"], 3,
				"El riesgo todavía no pasa; si ya pasó, es un problema.", "riesgo"),
			_reactivo(174, 11, "Para decidir qué riesgos atender primero se evalúan:",
				["Su orden alfabético", "Su probabilidad y su impacto", "La fecha en que se anotaron", "Quién los escribió"], 1,
				"Los riesgos con probabilidad e impacto altos se atienden primero.", "riesgo"),
			_reactivo(175, 11, "Riesgo: un integrante podría enfermarse. Que dos personas conozcan cada módulo es una estrategia de:",
				["Mitigación", "Evitación", "Transferencia", "Aceptación"], 0,
				"Mitigar es reducir el impacto o la probabilidad del riesgo.", "estrategias_riesgo"),
			_reactivo(176, 11, "Contratar un seguro o pasar una parte riesgosa a un proveedor externo es:",
				["Transferir el riesgo", "Ignorar el riesgo", "Aceptar el riesgo", "Evitar el riesgo"], 0,
				"Transferir pasa el impacto a otro, aunque el riesgo siga existiendo.", "estrategias_riesgo"),
			_reactivo(177, 11, "Cambiar a una tecnología conocida para que un riesgo técnico ya no pueda ocurrir es:",
				["Transferir el riesgo", "Mitigar el riesgo", "Aceptar el riesgo", "Evitar el riesgo"], 3,
				"Evitar es cambiar el plan para eliminar la causa del riesgo.", "estrategias_riesgo"),
			_reactivo(178, 11, "La estructura de desglose del trabajo (EDT/WBS) es:",
				["El presupuesto del proyecto", "Un diagrama de clases", "La división del trabajo en partes cada vez más pequeñas y manejables", "La lista de integrantes del equipo"], 2,
				"Se descompone el trabajo hasta llegar a tareas que se pueden estimar y asignar.", "wbs"),
			_reactivo(179, 11, "Un hito (milestone) es:",
				["Un punto de control importante, como el fin de un sprint", "Un error del sistema", "Una tarea que dura muchos días", "Un integrante del equipo"], 0,
				"Un hito no tiene duración: marca un momento clave del proyecto.", "hitos"),
			_reactivo(180, 11, "En un diagrama de Gantt, ¿qué representa la longitud de cada barra?",
				["El costo de la tarea", "El número de personas", "La duración de la tarea", "La importancia de la tarea"], 2,
				"Cada barra se extiende desde el inicio hasta el fin planeado de la tarea.", "hitos"),
			# ---- Tema 12 · banco Sprint 3 ----
			_reactivo(181, 12, "¿Qué organizaciones crearon el Código de Ética de la Ingeniería de Software?",
				["La OTAN y la ONU", "Google y Microsoft", "La ISO y la UNESCO", "La ACM y la IEEE Computer Society"], 3,
				"La ACM y la IEEE-CS publicaron juntas el código de ética y práctica profesional.", "codigo_etica"),
			_reactivo(182, 12, "Según el código de ética, cuando hay un conflicto, el ingeniero debe actuar primero en interés de:",
				["Su jefe", "El público", "Él mismo", "La empresa competidora"], 1,
				"El primer principio pide actuar de acuerdo con el interés y el bienestar del público.", "codigo_etica"),
			_reactivo(183, 12, "Un equipo entrega tarde y culpa a un compañero que no tuvo la culpa. ¿Qué principio viola?",
				["El de cuidar la calidad del producto", "El de seguir aprendiendo", "Ninguno", "El de ser justo y apoyar a los colegas"], 3,
				"El código pide ser justo con los colegas y reconocer el trabajo de cada uno.", "codigo_etica"),
			_reactivo(184, 12, "Encuentras un defecto que pone en riesgo los datos de los usuarios y te piden no decir nada. Lo correcto es:",
				["Borrar el código sin avisar", "Informarlo por los canales adecuados aunque retrase la entrega", "Publicarlo en redes sociales", "Callarlo para entregar a tiempo"], 1,
				"Ocultar un defecto que daña a los usuarios va contra el interés público.", "honestidad"),
			_reactivo(185, 12, "Te ofrecen un proyecto en una tecnología que no dominas. Lo ético es:",
				["Aceptarlo sin mencionar nada", "Decirlo con claridad antes de aceptarlo", "Rechazar cualquier proyecto nuevo", "Copiar un proyecto ajeno"], 1,
				"Un profesional es honesto sobre sus límites y solo promete lo que puede cumplir.", "honestidad"),
			_reactivo(186, 12, "Una licencia de código abierto como MIT permite:",
				["Usar, modificar y distribuir el código respetando sus condiciones", "Usarlo solo en computadoras de la universidad", "Usarlo sin ninguna condición", "Quitar el nombre del autor y venderlo como propio"], 0,
				"Las licencias abiertas dan permisos amplios, pero con condiciones, como conservar el aviso de derechos de autor.", "licencias"),
			_reactivo(187, 12, "Copiar código de internet a tu proyecto sin revisar su licencia puede:",
				["Hacerlo de dominio público", "Mejorar automáticamente su calidad", "Violar los derechos de autor", "Eliminar sus defectos"], 2,
				"El código publicado sigue teniendo autor; su licencia dice qué puedes hacer con él.", "licencias"),
			_reactivo(188, 12, "Presentar código de otra persona como propio, sin darle crédito, es:",
				["Refactorización", "Trabajo en equipo", "Plagio", "Reutilización correcta"], 2,
				"Reutilizar está bien si se respeta la licencia y se da crédito; presentarlo como propio es plagio.", "licencias"),
			_reactivo(189, 12, "Antes de guardar datos personales de los usuarios, la app debe:",
				["Guardarlos sin avisar", "Publicarlos para que sean transparentes", "Informar para qué se usarán y pedir su consentimiento", "Venderlos a otras empresas"], 2,
				"Los usuarios deben saber qué datos se recolectan, para qué, y aceptarlo.", "privacidad"),
			_reactivo(190, 12, "¿Cuál es una buena práctica para guardar las contraseñas de los usuarios?",
				["Guardarlas transformadas con una función hash", "Enviarlas por correo al administrador", "Guardarlas en texto plano", "Escribirlas en el código fuente"], 0,
				"Con un hash, aunque alguien robe la base de datos, no ve las contraseñas originales.", "privacidad"),
		],
		"intentos_modulo": [],
		# ---- Conceptos de teoría (CU-04) ----
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
			# ---- Conceptos nuevos del banco Sprint 3 ----
			_concepto("actividades_proceso", 1, "Actividades del proceso de software",
				"Un proceso de software es el conjunto de actividades que llevan a producir un sistema. Todo proceso incluye cuatro actividades básicas: especificación (qué hará), desarrollo (construirlo), validación (comprobar que es lo que se pidió) y evolución (cambiarlo con el tiempo).",
				["Especificación", "Desarrollo", "Validación", "Evolución"],
				"Qué hacer → hacerlo → comprobarlo → cambiarlo."),
			_concepto("algoritmo", 1, "Algoritmo",
				"Un algoritmo es una serie finita y ordenada de pasos para resolver un problema. Casi siempre sigue el patrón entrada → proceso → salida.",
				["Pasos ordenados", "Entrada", "Proceso", "Salida"],
				"Si cambias el orden de los pasos, el resultado cambia."),
			_concepto("atributos_software", 1, "Atributos del buen software",
				"Un buen software es mantenible (se puede cambiar), confiable y seguro (no falla ni pone en riesgo datos), eficiente (no desperdicia memoria ni procesador) y aceptable (sus usuarios lo entienden y lo usan).",
				["Mantenibilidad", "Confiabilidad", "Eficiencia", "Aceptabilidad"],
				"Que se pueda cambiar, que no falle, que no desperdicie y que lo usen."),
			_concepto("crisis_software", 1, "La crisis del software",
				"En los años 60 y 70 muchos proyectos se entregaban tarde, costaban más de lo planeado y fallaban. Para resolverlo se propuso tratar el desarrollo de software como una ingeniería, con métodos y disciplina; el término se popularizó en una conferencia de la OTAN en 1968.",
				["Retrasos", "Sobrecostos", "OTAN 1968"],
				"Sin método, el software se sale de tiempo, de presupuesto y de calidad."),
			_concepto("estructuras_control", 1, "Estructuras de control",
				"Todo algoritmo se arma con tres estructuras: secuencial (un paso tras otro), condicional (elegir un camino según una condición: si…, entonces…) y repetitiva (repetir mientras se cumpla una condición).",
				["Secuencial", "Condicional", "Repetitiva"],
				"Hacer, decidir y repetir."),
			_concepto("producto_software", 1, "Producto de software",
				"El software no es solo el código: incluye la documentación, los datos de configuración y el soporte. Hay productos genéricos, que se venden a cualquier cliente, y productos a la medida, hechos para un cliente específico.",
				["Código + documentación", "Genérico", "A la medida"],
				"Genérico = para todos (como un procesador de textos); a la medida = para uno (como el sistema de una escuela)."),
			_concepto("tipos_dato", 1, "Tipos de datos",
				"Cada dato tiene un tipo que dice qué valores puede guardar: entero (19), decimal (8.7), texto («Ana») o booleano (verdadero o falso).",
				["Entero", "Decimal", "Texto", "Booleano"],
				"Pregúntate: ¿lleva punto?, ¿lleva letras?, ¿es sí o no?"),
			_concepto("modelo_v", 2, "Modelo en V",
				"Es una variante de la cascada en la que cada fase de desarrollo tiene un nivel de prueba asociado: los requerimientos se validan con pruebas de aceptación, el diseño del sistema con pruebas de sistema e integración, y el código con pruebas unitarias.",
				["Desarrollo ↔ prueba", "Aceptación", "Unitarias"],
				"El lado izquierdo de la V construye; el derecho prueba lo que se construyó en el mismo nivel."),
			_concepto("historia_usuario", 3, "Historias de usuario",
				"En los métodos ágiles los requerimientos se escriben como historias cortas desde el punto de vista del usuario: «Como (rol), quiero (acción), para (beneficio)». Cada historia lleva criterios de aceptación que dicen cuándo está cumplida.",
				["Como…", "Quiero…", "Para…"],
				"Quién lo pide, qué quiere y para qué le sirve."),
			_concepto("priorizacion", 3, "Priorización MoSCoW",
				"MoSCoW clasifica los requerimientos en Must (indispensable), Should (importante), Could (deseable si hay tiempo) y Won't (no se hará en esta entrega).",
				["Must", "Should", "Could", "Won't"],
				"Must = sin esto no se entrega."),
			_concepto("req_usuario_sistema", 3, "Requerimientos de usuario y de sistema",
				"Los requerimientos de usuario se escriben en lenguaje natural para que el cliente los entienda. Los requerimientos de sistema detallan con precisión qué hará el software y sirven a los desarrolladores.",
				["Usuario: lenguaje natural", "Sistema: detalle técnico"],
				"Usuario = para el cliente; sistema = para el equipo."),
			_concepto("trazabilidad", 3, "Trazabilidad de requerimientos",
				"Es poder seguir cada requerimiento hasta el diseño, el código y las pruebas que lo cubren, y al revés. Se registra en una matriz de trazabilidad; así se sabe qué afecta un cambio y si algo quedó sin probar.",
				["Matriz de trazabilidad", "Requerimiento → prueba"],
				"Si un requerimiento no tiene prueba, nadie sabe si se cumplió."),
			_concepto("validacion_req", 3, "Validación de requerimientos",
				"Consiste en comprobar que los requerimientos describen lo que el cliente realmente necesita. Se hace con revisiones junto al cliente y con prototipos. Corregir un requerimiento mal entendido al inicio es mucho más barato que corregirlo después de programar.",
				["Revisión con el cliente", "Prototipos", "Costo del cambio"],
				"Un error de requerimientos crece de precio en cada fase que avanza."),
			_concepto("diag_despliegue", 4, "Diagrama de despliegue",
				"Muestra los nodos físicos (celulares, servidores) donde se ejecuta el software y cómo se conectan entre sí.",
				["Nodos", "Hardware", "Conexiones"],
				"Despliegue = dónde corre cada parte."),
			_concepto("diag_estados", 4, "Diagrama de estados",
				"Muestra los estados por los que pasa un objeto durante su vida y los eventos que provocan cada cambio de estado (transiciones). Por ejemplo, un pedido pasa de creado a pagado, a enviado y a entregado.",
				["Estados", "Transiciones", "Eventos"],
				"Úsalo cuando algo «cambia de estado» con el tiempo."),
			_concepto("include_extend", 4, "Relaciones «include» y «extend»",
				"En un diagrama de casos de uso, «include» indica que un caso de uso siempre incorpora el comportamiento de otro (por ejemplo, «Pagar» incluye «Validar tarjeta»). «Extend» indica un comportamiento opcional que solo ocurre bajo cierta condición (por ejemplo, «Aplicar cupón»).",
				["«include» = siempre", "«extend» = a veces"],
				"Include es obligatorio; extend es opcional."),
			_concepto("uml_tipos", 4, "Tipos de diagramas UML",
				"UML (Lenguaje Unificado de Modelado) tiene diagramas estructurales, que muestran cómo está formado el sistema (clases, componentes, despliegue), y diagramas de comportamiento, que muestran qué hace (casos de uso, actividad, secuencia, estados).",
				["Estructurales", "De comportamiento"],
				"Estructura = de qué está hecho; comportamiento = qué hace."),
			_concepto("abstraccion", 5, "Abstracción",
				"Consiste en enfocarse en lo esencial de algo e ignorar los detalles que no importan en ese momento. Por ejemplo, para usar un método «enviarCorreo()» no necesitas saber cómo se conecta al servidor.",
				["Lo esencial", "Ocultar detalles"],
				"Piensa en el «qué», no en el «cómo»."),
			_concepto("dry_kiss", 5, "Principios DRY y KISS",
				"DRY («No te repitas») pide no duplicar la misma lógica en varios lugares, para que un cambio se haga una sola vez. KISS («Mantenlo simple») pide elegir la solución más sencilla que funcione.",
				["DRY", "KISS"],
				"Si copias y pegas código, probablemente estás rompiendo DRY."),
			_concepto("modularidad", 5, "Modularidad",
				"Es dividir el sistema en partes (módulos) con funciones bien definidas que se pueden construir, probar y cambiar por separado.",
				["Módulos", "Independencia"],
				"Divide y vencerás."),
			_concepto("niveles_diseno", 5, "Diseño arquitectónico y diseño detallado",
				"El diseño arquitectónico define los componentes principales del sistema y cómo se comunican. El diseño detallado define cómo funciona cada componente por dentro: sus clases, métodos y datos.",
				["Arquitectónico", "Detallado"],
				"Primero el plano de la casa, luego cada cuarto."),
			_concepto("ocultamiento", 5, "Encapsulamiento y ocultamiento de información",
				"Cada módulo esconde sus datos y su forma de trabajar, y solo expone una interfaz para usarlo. Así, si cambia por dentro, los demás módulos no se ven afectados.",
				["Interfaz pública", "Datos privados"],
				"Los demás usan los botones, no abren la caja."),
			_concepto("refactorizacion", 5, "Refactorización",
				"Es mejorar la estructura interna del código (nombres, duplicación, tamaño de las clases) sin cambiar lo que hace. Se apoya en pruebas para confirmar que el comportamiento sigue igual.",
				["Misma funcionalidad", "Mejor estructura"],
				"Refactorizar = ordenar el código, no agregar funciones."),
			_concepto("error_defecto_falla", 6, "Error, defecto y falla",
				"Un error es la equivocación de una persona; produce un defecto (bug) en el código o en un documento; cuando ese defecto se ejecuta, causa una falla, que es el comportamiento incorrecto que ve el usuario.",
				["Error (persona)", "Defecto (código)", "Falla (ejecución)"],
				"La persona se equivoca, el código queda mal, el programa falla."),
			_concepto("particiones", 6, "Particiones de equivalencia",
				"Las entradas se dividen en grupos que el sistema debe tratar igual (por ejemplo, edades válidas y edades inválidas) y se prueba un valor representativo de cada grupo, en lugar de probar todos los valores.",
				["Grupos de entradas", "Un valor por grupo"],
				"Si dos valores se tratan igual, basta con probar uno."),
			_concepto("principios_prueba", 6, "Principios de las pruebas",
				"Las pruebas pueden mostrar que hay defectos, pero no demostrar que no existe ninguno. Probar todo es imposible, por eso se eligen los casos con más probabilidad de encontrar defectos, y conviene empezar a probar desde temprano.",
				["Presencia, no ausencia", "Probar todo es imposible", "Probar temprano"],
				"Pasar todas las pruebas no significa cero errores."),
			_concepto("pruebas_no_funcionales", 6, "Pruebas de rendimiento y estrés",
				"Comprueban cualidades del sistema, no sus funciones. Las de rendimiento miden tiempos de respuesta con la carga normal; las de estrés llevan el sistema más allá de su carga esperada para ver cómo y cuándo falla.",
				["Rendimiento", "Estrés", "Carga"],
				"Estrés = empujar el sistema hasta que se rompa."),
			_concepto("tdd", 6, "Desarrollo guiado por pruebas (TDD)",
				"En TDD primero se escribe una prueba que falla, luego el código mínimo para que pase, y al final se refactoriza. Se repite en ciclos cortos: rojo, verde, refactorizar.",
				["Rojo", "Verde", "Refactorizar"],
				"La prueba va antes que el código."),
			_concepto("valores_limite", 6, "Análisis de valores límite",
				"Los defectos suelen aparecer en los bordes de los rangos. Si un campo acepta de 1 a 100, conviene probar 0, 1, 100 y 101: justo afuera y justo adentro de cada límite.",
				["Bordes del rango", "Justo adentro", "Justo afuera"],
				"Prueba el límite y su vecino de cada lado."),
			_concepto("estimacion_esfuerzo", 7, "Estimación de esfuerzo: COCOMO",
				"COCOMO es un modelo que estima el esfuerzo (en meses-persona) y la duración de un proyecto a partir de su tamaño en miles de líneas de código (KLOC), ajustado por factores del equipo y del producto.",
				["Tamaño (KLOC)", "Esfuerzo", "Duración"],
				"Más tamaño → más esfuerzo, y crece más rápido que el tamaño."),
			_concepto("productividad", 7, "Productividad",
				"Relaciona lo producido con el esfuerzo invertido, por ejemplo líneas de código o puntos de función por mes-persona. Sirve para estimar, pero no para comparar equipos que usan lenguajes distintos.",
				["Tamaño / esfuerzo", "Mes-persona"],
				"Productividad = cuánto se hizo ÷ cuánto esfuerzo costó."),
			_concepto("tipos_metricas", 7, "Métricas de producto, proceso y proyecto; GQM",
				"Las métricas de producto miden el software (tamaño, complejidad, defectos); las de proceso miden cómo se trabaja (tiempo para corregir un defecto, defectos encontrados en revisiones); las de proyecto miden avance, costo y calendario. El enfoque GQM (Meta-Pregunta-Métrica) define primero la meta, luego las preguntas y al final qué medir.",
				["Producto", "Proceso", "Proyecto", "GQM"],
				"No midas por medir: primero la meta, luego la métrica."),
			_concepto("burndown", 8, "Gráfica burndown",
				"Muestra cuánto trabajo falta por hacer en cada día del sprint. Si la línea real queda por encima de la ideal, el equipo va atrasado.",
				["Trabajo restante", "Línea ideal"],
				"Arriba de la línea ideal = atraso."),
			_concepto("dod", 8, "Definition of Done e incremento",
				"La Definition of Done (DoD) es el acuerdo del equipo sobre qué debe cumplir un elemento para considerarse terminado (por ejemplo: código revisado, pruebas aprobadas, documentado). Lo terminado en el sprint forma el incremento, una versión utilizable del producto.",
				["Terminado = cumple la DoD", "Incremento utilizable"],
				"Si no cumple la DoD, no está terminado, aunque «ya casi»."),
			_concepto("estimacion_agil", 8, "Estimación ágil: puntos de historia y velocidad",
				"Los puntos de historia miden el esfuerzo y la complejidad relativa de una historia, no horas exactas. Se estiman en equipo, por ejemplo con Planning Poker. La velocidad es el promedio de puntos que el equipo termina por sprint y sirve para planear los siguientes.",
				["Puntos de historia", "Planning Poker", "Velocidad"],
				"Velocidad = puntos terminados por sprint, en promedio."),
			_concepto("iso25010", 9, "Modelo de calidad ISO/IEC 25010",
				"Define las características de calidad de un producto de software, entre ellas: adecuación funcional, eficiencia de desempeño, compatibilidad, usabilidad, fiabilidad, seguridad, mantenibilidad y portabilidad.",
				["Usabilidad", "Fiabilidad", "Mantenibilidad", "Portabilidad"],
				"Cada RNF de un SRS suele caer en una de estas características."),
			_concepto("qa_qc", 9, "Aseguramiento y control de calidad",
				"El aseguramiento de la calidad (QA) se enfoca en el proceso: definir y seguir buenas prácticas para prevenir defectos. El control de calidad (QC) se enfoca en el producto: revisarlo y probarlo para detectar defectos.",
				["QA = proceso, prevenir", "QC = producto, detectar"],
				"QA evita que el defecto nazca; QC lo encuentra si nació."),
			_concepto("revisiones", 9, "Revisiones e inspecciones",
				"Son lecturas en grupo de un artefacto (requerimientos, diseño o código) para encontrar defectos sin ejecutarlo. Detectan errores temprano, cuando corregirlos cuesta menos que en pruebas o en producción.",
				["Sin ejecutar", "En equipo", "Temprano"],
				"Lo que se encuentra en una revisión ya no llega al usuario."),
			_concepto("verif_valid", 9, "Verificación y validación",
				"La verificación revisa que el producto cumpla su especificación: «¿estamos construyendo el producto correctamente?». La validación revisa que el producto sirva a lo que el usuario necesita: «¿estamos construyendo el producto correcto?».",
				["Verificación = según la especificación", "Validación = según el usuario"],
				"Verificar contra el documento; validar contra el cliente."),
			_concepto("commit_git", 10, "Commits",
				"Un commit guarda en el historial una instantánea de los cambios, con un mensaje que explica qué se hizo. Un buen mensaje es corto y específico, por ejemplo «Agrega validación del alias».",
				["Instantánea", "Mensaje claro"],
				"El mensaje responde: ¿qué cambió y por qué?"),
			_concepto("control_versiones", 10, "Control de versiones y gestión de configuración",
				"Un sistema de control de versiones, como Git, registra cada cambio de los archivos, quién lo hizo y cuándo, y permite volver a versiones anteriores. La gestión de configuración aplica ese control a todo el proyecto: código, documentos y versiones entregadas.",
				["Historial", "Volver atrás", "Git"],
				"Sin control de versiones, «final_final_v3.zip» es tu historial."),
			_concepto("merge", 10, "Fusión (merge) y conflictos",
				"Fusionar une los cambios de una rama con otra. Hay conflicto cuando dos ramas cambiaron las mismas líneas de forma distinta; una persona debe decidir qué versión queda.",
				["Fusionar", "Conflicto", "Resolver a mano"],
				"Mismo archivo, mismas líneas, cambios distintos = conflicto."),
			_concepto("ramas", 10, "Ramas",
				"Una rama es una línea de trabajo separada. Permite desarrollar una funcionalidad sin afectar la versión principal (main) hasta que esté lista para integrarse.",
				["main", "feature/…", "Trabajo aislado"],
				"Una rama por funcionalidad, como feature/CU-01-perfil."),
			_concepto("repo_remoto", 10, "Repositorio remoto y pull request",
				"El repositorio remoto (por ejemplo, en GitHub) es la copia compartida del equipo. «git push» sube tus commits y «git pull» trae los de los demás. Un pull request pide que el equipo revise los cambios de una rama antes de integrarlos.",
				["push = subir", "pull = traer", "Pull request = revisión"],
				"Push empuja hacia afuera; pull jala hacia ti."),
			_concepto("estrategias_riesgo", 11, "Estrategias ante los riesgos",
				"Evitar: cambiar el plan para que el riesgo no pueda ocurrir. Mitigar: reducir su probabilidad o su impacto. Transferir: pasarlo a otro, por ejemplo con un seguro o un proveedor. Aceptar: asumirlo y tener un plan B por si ocurre.",
				["Evitar", "Mitigar", "Transferir", "Aceptar"],
				"Quitarlo, achicarlo, pasarlo o asumirlo."),
			_concepto("hitos", 11, "Hitos y diagrama de Gantt",
				"Un hito es un punto de control importante sin duración, como el fin de un sprint o una entrega. El diagrama de Gantt muestra las tareas como barras en el tiempo: la longitud de cada barra es su duración.",
				["Hito = punto de control", "Barra = duración"],
				"Los hitos marcan fechas; las barras, trabajo."),
			_concepto("riesgo", 11, "Riesgos",
				"Un riesgo es un evento incierto que, si ocurre, afecta al proyecto. Se evalúa por su probabilidad y su impacto, y se atienden primero los que tienen ambos altos.",
				["Probabilidad", "Impacto", "Prioridad"],
				"Riesgo = algo que todavía no pasa, pero podría."),
			_concepto("triple_restriccion", 11, "Triple restricción",
				"Todo proyecto se equilibra entre alcance (qué se entrega), tiempo y costo. Si uno cambia, al menos otro tiene que ajustarse; si no, la que sufre es la calidad.",
				["Alcance", "Tiempo", "Costo"],
				"Más alcance sin más tiempo ni costo = menos calidad."),
			_concepto("wbs", 11, "Estructura de desglose del trabajo (EDT/WBS)",
				"Divide todo el trabajo del proyecto en partes cada vez más pequeñas, hasta llegar a tareas que se pueden estimar, asignar y controlar.",
				["Descomponer", "Tareas manejables"],
				"Si una tarea no se puede estimar, divídela más."),
			_concepto("codigo_etica", 12, "Código de ética de la ingeniería de software",
				"La ACM y la IEEE Computer Society publicaron un código de ética con ocho principios: actuar en interés del público, del cliente y el empleador, cuidar la calidad del producto, mantener un juicio independiente, gestionar con ética, cuidar la profesión, apoyar a los colegas y seguir aprendiendo.",
				["ACM / IEEE-CS", "Interés público primero", "8 principios"],
				"Cuando hay conflicto, el bienestar del público va primero."),
			_concepto("honestidad", 12, "Honestidad y competencia profesional",
				"Un ingeniero informa a tiempo los retrasos y los defectos que conoce, aunque sean malas noticias, y solo acepta trabajos para los que tiene la competencia, o lo dice con claridad.",
				["Informar defectos", "Reconocer límites"],
				"Ocultar un problema no lo resuelve, lo agranda."),
			_concepto("licencias", 12, "Licencias y propiedad intelectual",
				"El código tiene autor y licencia. Las licencias de código abierto, como MIT o GPL, permiten usarlo y modificarlo bajo ciertas condiciones. Usar código ajeno sin respetar su licencia, o presentarlo como propio, viola los derechos de autor y es plagio.",
				["Licencia", "Derechos de autor", "Dar crédito"],
				"Antes de copiar, revisa la licencia y da crédito."),
			_concepto("privacidad", 12, "Privacidad y protección de datos",
				"Una app debe informar qué datos personales recolecta y para qué, pedir consentimiento, guardar solo lo necesario y protegerlo; por ejemplo, las contraseñas se guardan transformadas con una función hash, nunca en texto plano.",
				["Consentimiento", "Datos mínimos", "Hash"],
				"Si no lo necesitas, no lo pidas; si lo guardas, protégelo."),
		],
		# ---- CU-05: insignias con niveles bronce / plata / oro ----
		"insignias": [
			# Logros generales: suben de nivel al alcanzar cada umbral de su métrica
			_insignia("primer_paso", "Primer paso", "Cada módulo completado es un paso en tu formación como ingeniero de software.", "modulos_completados", [1, 6, 18], "módulos completados",
				["Completa tu primer módulo (≥ 70 %)", "Completa 6 módulos", "Completa 18 módulos"], "estrella", "#2F55E6"),
			_insignia("punteria", "Puntería", "Reconoce la precisión: retos resueltos sin fallar una sola pregunta.", "retos_perfectos", [1, 5, 15], "retos con 100 %",
				["Logra 100 % en un reto", "Logra 100 % en 5 retos", "Logra 100 % en 15 retos"], "check", "#178A4C"),
			_insignia("armador", "Armador", "Puzzles armados sin un solo error.", "puzzles_perfectos", [1, 4, 12], "puzzles con 100 %",
				["Completa un puzzle con 100 %", "Completa 4 puzzles con 100 %", "Completa 12 puzzles con 100 %"], "puzzle", "#7C3AED"),
			_insignia("estudioso", "Estudioso", "Repasar la teoría es de ingenieros: consultas de conceptos desde los retos.", "teoria", [5, 15, 40], "consultas de teoría",
				["Consulta la teoría 5 veces", "Consulta la teoría 15 veces", "Consulta la teoría 40 veces"], "libro", "#0E7490"),
			_insignia("racha", "A la primera", "Módulos completados en el primer intento, sin necesidad de repetirlos.", "primer_intento", [1, 5, 15], "módulos a la primera",
				["Completa un módulo en el primer intento", "Completa 5 módulos a la primera", "Completa 15 módulos a la primera"], "play", "#C2410C"),
			_insignia("constante", "Constante", "La práctica hace al ingeniero: retos terminados, cuenten como cuenten.", "intentos", [10, 30, 80], "retos terminados",
				["Termina 10 retos", "Termina 30 retos", "Termina 80 retos"], "reiniciar", "#D97706"),
			_insignia("analista", "Analista", "Dominas los requerimientos funcionales y no funcionales.", "analista", [1, 3, 4], "avance en Requerimientos",
				["Completa un módulo del tema Requerimientos", "Completa los 3 módulos de Requerimientos", "Domina Requerimientos (aprueba su práctica)"], "quiz", "#2F55E6"),
			_insignia("ingeniero", "Ingeniero", "Recorriste mapas completos: temas con sus tres módulos terminados.", "temas_completos", [1, 6, 12], "temas completos",
				["Completa los 3 módulos de un tema", "Completa 6 temas", "Completa los 12 temas"], "mapa", "#B45309"),
			_insignia("perfeccionista", "Perfeccionista", "Nada se te escapa: módulos con 100 % como mejor puntaje.", "modulos_perfectos", [3, 12, 36], "módulos con 100 %",
				["Ten 100 % en 3 módulos", "Ten 100 % en 12 módulos", "Ten 100 % en los 36 módulos"], "estrella", "#14633A"),
			_insignia("repasador", "Repasador", "Convertiste errores en aciertos en Repasar mis errores.", "corregidas", [5, 20, 50], "preguntas corregidas",
				["Corrige 5 preguntas en el repaso", "Corrige 20 preguntas", "Corrige 50 preguntas"], "reiniciar", "#0E7490"),
			_insignia("sin_pistas", "Sin ayuda", "Módulos completados sin pedir ninguna pista.", "sin_pistas", [1, 10, 36], "módulos sin pistas",
				["Completa un módulo sin pistas", "Completa 10 módulos sin pistas", "Completa los 36 módulos sin pistas"], "ojo", "#7C3AED"),
			_insignia("dominio", "Dominio", "Temas dominados con la práctica de ingeniero aprobada.", "temas_dominados", [1, 6, 12], "temas dominados",
				["Domina un tema (práctica ≥ 70 %)", "Domina 6 temas", "Domina los 12 temas"], "puzzle", "#C2410C"),
			# Medallas por tema: promedio del mejor puntaje de sus 3 módulos (bronce ≥ 70, plata ≥ 85, oro = 100)
			_medalla_tema(1, "Fundamentos", "libro", "#2F55E6"),
			_medalla_tema(2, "Ciclo de vida", "reiniciar", "#178A4C"),
			_medalla_tema(3, "Requerimientos", "lapiz", "#7C3AED"),
			_medalla_tema(4, "Modelado UML", "mapa", "#0E7490"),
			_medalla_tema(5, "Diseño", "puzzle", "#C2410C"),
			_medalla_tema(6, "Pruebas", "check", "#14633A"),
			_medalla_tema(7, "Métricas", "quiz", "#D97706"),
			_medalla_tema(8, "Gestión ágil", "play", "#B45309"),
			_medalla_tema(9, "Calidad", "estrella", "#2F55E6"),
			_medalla_tema(10, "Control de versiones", "guardar", "#178A4C"),
			_medalla_tema(11, "Proyectos y riesgos", "alerta", "#7C3AED"),
			_medalla_tema(12, "Ética", "ojo", "#0E7490"),
		],
		"avatares_desbloqueados": ["avatar_01", "avatar_02", "avatar_03", "avatar_04", "avatar_05", "avatar_06"],
		# ---- CU-09: preguntas falladas pendientes de repaso ----
		"errores": [],
		# ---- Ejercicios de manipulación por tema (módulo Puzzle y práctica de ingeniero, CU-11) ----
		"puzzles": [
			# ---- Tema 1 ----
			_pz(1, _ej_ordenar("Ordena los pasos del algoritmo para calcular el promedio de tres calificaciones.", [
				"Leer las tres calificaciones", "Sumar las tres calificaciones", "Dividir la suma entre 3", "Mostrar el promedio"],
				"Primero se obtienen los datos (entrada), luego se procesan (suma y división) y al final se muestra el resultado (salida).", "algoritmo")),
			_pz(1, _ej_clasificar("¿Qué estructura de control describe cada instrucción?", ["Secuencial", "Condicional", "Repetitiva"], [
				["Leer dos números y mostrar su suma", "Secuencial"], ["Si la calificación es ≥ 70, aprobar; si no, reprobar", "Condicional"], ["Mientras haya alumnos en la lista, tomar asistencia", "Repetitiva"], ["Encender la computadora, abrir el navegador y entrar al sitio", "Secuencial"], ["Si llueve, llevar paraguas", "Condicional"], ["Pedir la contraseña hasta que sea correcta", "Repetitiva"]],
				"Secuencial = un paso tras otro; condicional = se elige un camino según una condición; repetitiva = se repite mientras se cumple una condición.", "estructuras_control")),
			_pz(1, _ej_ordenar("Ordena el pseudocódigo que indica si un número es par o impar.", [
				"Inicio", "Leer el número", "Calcular el residuo de dividir el número entre 2", "Si el residuo es 0, mostrar «par»; si no, mostrar «impar»", "Fin"],
				"Un número es par si al dividirlo entre 2 el residuo es 0; la decisión se toma después de calcular el residuo.", "estructuras_control")),
			_pz(1, _ej_clasificar("¿Qué tipo de dato conviene para guardar cada valor?", ["Entero", "Decimal", "Texto", "Booleano"], [
				["Edad: 19", "Entero"], ["Promedio: 8.7", "Decimal"], ["Nombre: «Ana»", "Texto"], ["¿Está inscrito?: verdadero", "Booleano"], ["Número de módulos: 12", "Entero"], ["Precio: 25.50", "Decimal"]],
				"Entero = números sin punto; decimal = con punto; texto = letras y símbolos; booleano = solo verdadero o falso.", "tipos_dato")),
			_pz(1, _ej_clasificar("Sigue el pseudocódigo y clasifica cada afirmación: x ← 4; mientras x > 0: x ← x − 2", ["Verdadero", "Falso"], [
				["El ciclo se repite 2 veces", "Verdadero"], ["Al final, x vale 0", "Verdadero"], ["El ciclo nunca termina", "Falso"], ["En algún momento x vale 2", "Verdadero"], ["Al final, x vale −2", "Falso"]],
				"x pasa de 4 a 2 (primera vuelta) y de 2 a 0 (segunda); como 0 > 0 es falso, el ciclo termina con x = 0.", "estructuras_control")),
			_pz(1, _ej_clasificar("¿Qué atributo del buen software pide cada frase del cliente?", ["Mantenibilidad", "Confiabilidad", "Eficiencia", "Aceptabilidad"], [
				["«Que podamos agregar temas sin reescribir todo»", "Mantenibilidad"], ["«Que no se trabe ni pierda mi progreso»", "Confiabilidad"], ["«Que no se acabe la batería del celular»", "Eficiencia"], ["«Que los alumnos lo entiendan sin manual»", "Aceptabilidad"], ["«Que no desperdicie memoria»", "Eficiencia"], ["«Que sea fácil cambiarlo el próximo semestre»", "Mantenibilidad"]],
				"Cambiar fácil = mantenible; no fallar = confiable; no desperdiciar recursos = eficiente; que lo entiendan y usen = aceptable.", "atributos_software")),
			# ---- Tema 2 ----
			_pz(2, _ej_clasificar("¿Qué modelo de ciclo de vida conviene en cada situación?", ["Cascada", "Prototipado", "Espiral", "Scrum"], [
				["Requerimientos claros y estables, por ejemplo un sistema de nómina conocido", "Cascada"], ["El cliente no sabe qué quiere hasta ver algo", "Prototipado"], ["Proyecto grande con mucho riesgo técnico", "Espiral"], ["Requerimientos que cambian y entregas cada dos semanas", "Scrum"], ["Se necesita probar ideas de interfaz con usuarios antes de construir", "Prototipado"], ["Sistema crítico donde cada vuelta empieza analizando riesgos", "Espiral"]],
				"Estable → cascada; incierto para el cliente → prototipado; riesgoso → espiral; cambiante con entregas frecuentes → Scrum.", "cascada")),
			_pz(2, _ej_ordenar("Ordena las fases del modelo en cascada, de la primera a la última.", [
				"Análisis de requerimientos", "Diseño", "Implementación", "Pruebas", "Mantenimiento"],
				"No puedes probar lo que no has programado ni programar lo que no has diseñado.", "cascada")),
			_pz(2, _ej_ordenar("Ordena los pasos de una vuelta del modelo en espiral.", [
				"Definir objetivos y alternativas", "Analizar y resolver los riesgos", "Desarrollar y probar el incremento", "Planear la siguiente vuelta"],
				"Cada vuelta de la espiral empieza por los objetivos, ataca los riesgos, construye y planea la siguiente.", "espiral")),
			# ---- Tema 3 ----
			_pz(3, _ej_clasificar("¿Es un requerimiento verificable o ambiguo?", ["Verificable", "Ambiguo"], [
				["El registro se completa en máximo 3 pantallas", "Verificable"], ["El sistema será fácil de usar", "Ambiguo"], ["La búsqueda responde en menos de 2 segundos", "Verificable"], ["La app será rápida", "Ambiguo"], ["Las contraseñas tienen al menos 8 caracteres", "Verificable"], ["El sistema tendrá buena seguridad", "Ambiguo"]],
				"Un requerimiento verificable tiene un criterio medible; «fácil», «rápida» o «buena» no se pueden probar.", "verificabilidad")),
			_pz(3, _ej_ordenar("Ordena las actividades de la ingeniería de requerimientos.", [
				"Elicitación", "Análisis", "Especificación", "Validación"],
				"Primero se obtienen los requerimientos, luego se analizan, se escriben en el SRS y al final se validan con el cliente.", "elicitacion")),
			_pz(3, _ej_clasificar("Clasifica cada requerimiento del cliente de una biblioteca escolar.", ["Funcional", "No funcional"], [
				["Registrar el préstamo de un libro", "Funcional"], ["Responder en menos de 2 segundos", "No funcional"], ["Enviar recordatorio de devolución", "Funcional"], ["Funcionar sin conexión a internet", "No funcional"], ["Cifrar las contraseñas de los usuarios", "No funcional"], ["Generar el reporte mensual de préstamos", "Funcional"]],
				"Funcional = una acción que el sistema hace; no funcional = una cualidad o límite (tiempo, seguridad, disponibilidad).", "req_no_funcional")),
			_pz(3, _ej_clasificar("Prioriza con MoSCoW las historias de la app de la biblioteca.", ["Must", "Should", "Could", "Won't"], [
				["Registrar préstamos y devoluciones", "Must"], ["Enviar recordatorio de devolución por correo", "Should"], ["Modo oscuro", "Could"], ["Vender libros en línea", "Won't"], ["Buscar un libro por título", "Must"], ["Estadísticas con gráficas", "Could"]],
				"Must = sin esto no se entrega; Should = importante pero no bloquea; Could = si sobra tiempo; Won't = fuera de esta versión.", "priorizacion")),
			# ---- Tema 4 ----
			_pz(4, _ej_clasificar("¿Qué diagrama UML usarías para cada necesidad?", ["Casos de uso", "Clases", "Secuencia", "Actividad"], [
				["Mostrar qué puede hacer cada tipo de usuario", "Casos de uso"], ["Mostrar los atributos y métodos de Pedido", "Clases"], ["Mostrar el orden de los mensajes al pagar", "Secuencia"], ["Mostrar el proceso de inscripción con sus decisiones", "Actividad"], ["Mostrar la herencia entre Usuario y Administrador", "Clases"], ["Mostrar paso a paso cómo responde el servidor al iniciar sesión", "Secuencia"]],
				"Quién hace qué → casos de uso; estructura → clases; mensajes en el tiempo → secuencia; flujo con decisiones → actividad.", "uml_tipos")),
			_pz(4, _ej_construir("Control escolar: los alumnos se inscriben y consultan calificaciones; los profesores capturan calificaciones. Coloca cada elemento en el diagrama.", ["Actor", "Caso de uso"], [
				["Alumno", "Actor"], ["Inscribirse a materias", "Caso de uso"], ["Profesor", "Actor"], ["Capturar calificaciones", "Caso de uso"], ["Consultar calificaciones", "Caso de uso"], ["Sistema de pagos del banco", "Actor"]],
				"Los actores son personas o sistemas externos (como el banco); los casos de uso son lo que el sistema les ofrece.", "casos_uso")),
			_pz(4, _ej_construir("Biblioteca escolar: arma el diagrama de casos de uso colocando cada elemento donde va.", ["Actor", "Caso de uso"], [
				["Bibliotecario", "Actor"], ["Prestar libro", "Caso de uso"], ["Alumno", "Actor"], ["Devolver libro", "Caso de uso"], ["Consultar catálogo", "Caso de uso"], ["Sistema de correo", "Actor"]],
				"Los actores son personas o sistemas externos; los casos de uso son las funciones que el sistema les ofrece.", "casos_uso")),
			_pz(4, _ej_clasificar("En un diagrama de casos de uso, ¿la relación es «include» o «extend»?", ["include", "extend"], [
				["Pagar siempre requiere Iniciar sesión", "include"], ["Al pagar, a veces se aplica un cupón", "extend"], ["Reservar libro siempre valida la disponibilidad", "include"], ["Al registrarse, opcionalmente se sube una foto", "extend"], ["Enviar pedido siempre calcula el envío", "include"], ["Al consultar calificaciones, a veces se descarga el PDF", "extend"]],
				"Include = el caso base siempre lo ejecuta; extend = solo en algunas condiciones.", "include_extend")),
			# ---- Tema 5 ----
			_pz(5, _ej_clasificar("En una app con MVC, ¿a qué parte pertenece cada responsabilidad?", ["Modelo", "Vista", "Controlador"], [
				["Guardar las calificaciones en la base de datos", "Modelo"], ["Mostrar la tabla de calificaciones", "Vista"], ["Recibir el clic en «Guardar» y decidir qué hacer", "Controlador"], ["Validar que la calificación esté entre 0 y 10", "Modelo"], ["Pintar el mensaje de error en rojo", "Vista"], ["Pedir los datos al modelo y elegir qué pantalla mostrar", "Controlador"]],
				"Modelo = datos y reglas; vista = lo que se ve; controlador = recibe acciones y coordina.", "mvc")),
			_pz(5, _ej_clasificar("¿Es una decisión de buen diseño o de mal diseño?", ["Buen diseño", "Mal diseño"], [
				["Dos módulos que se comunican solo por una interfaz", "Buen diseño"], ["Copiar la función de validación en cinco pantallas", "Mal diseño"], ["Un módulo que hace una sola cosa", "Buen diseño"], ["La vista consulta directamente la base de datos", "Mal diseño"], ["Elegir la solución más simple que funciona", "Buen diseño"], ["Una clase de 3 000 líneas que hace de todo", "Mal diseño"]],
				"Bajo acoplamiento, alta cohesión, DRY y KISS son buen diseño; duplicar código, saltarse capas y clases gigantes son mal diseño.", "dry_kiss")),
			_pz(5, _ej_ordenar("Ordena los niveles del diseño, del más general al más detallado.", [
				"Diseño arquitectónico: componentes y cómo se comunican", "Diseño de interfaces entre componentes", "Diseño detallado: clases, métodos y datos de cada componente", "Codificación"],
				"Primero el plano de la casa (arquitectura), luego cómo se conectan los cuartos y al final cada cuarto por dentro.", "niveles_diseno")),
			_pz(5, _ej_clasificar("¿Qué principio de diseño aplica cada frase?", ["Abstracción", "Encapsulamiento", "Modularidad"], [
				["Usar enviarCorreo() sin saber cómo se conecta al servidor", "Abstracción"], ["Los datos de la clase son privados y se cambian solo con métodos", "Encapsulamiento"], ["Dividir la app en módulos de perfil, mapa y actividad", "Modularidad"], ["Modelar un Alumno solo con nombre, matrícula y promedio", "Abstracción"], ["Cambiar la base de datos sin que las pantallas se enteren", "Encapsulamiento"], ["Probar el módulo de insignias por separado", "Modularidad"]],
				"Quedarse con lo esencial = abstracción; esconder lo interno = encapsulamiento; dividir en partes independientes = modularidad.", "abstraccion")),
			# ---- Tema 6 ----
			_pz(6, _ej_clasificar("Un campo acepta edades de 18 a 60. ¿El sistema debe aceptar o rechazar cada valor?", ["Aceptar", "Rechazar"], [
				["18", "Aceptar"], ["17", "Rechazar"], ["60", "Aceptar"], ["61", "Rechazar"], ["35", "Aceptar"], ["−1", "Rechazar"]],
				"Los valores límite (17, 18, 60, 61) son los que más defectos encuentran; 35 representa a los válidos y −1 a los inválidos.", "valores_limite")),
			_pz(6, _ej_clasificar("¿Qué nivel de prueba es cada caso?", ["Unitaria", "Integración", "Sistema", "Aceptación"], [
				["Probar la función que calcula el IVA", "Unitaria"], ["Probar que el carrito y el módulo de pagos se comuniquen bien", "Integración"], ["Probar la app completa en un celular real", "Sistema"], ["El cliente usa la app y aprueba la entrega", "Aceptación"], ["Probar el método que valida el correo", "Unitaria"], ["Probar que el inicio de sesión y la base de datos funcionen juntos", "Integración"]],
				"Una pieza → unitaria; piezas juntas → integración; todo el sistema → sistema; el cliente decide → aceptación.", "aceptacion")),
			_pz(6, _ej_ordenar("Ordena los pasos para corregir un defecto (bug).", [
				"Reproducir la falla", "Localizar la línea que la causa", "Corregir el código", "Volver a ejecutar las pruebas"],
				"Si no puedes reproducir la falla, no sabes si la corregiste; al final se repiten las pruebas para no romper otra cosa.", "error_defecto_falla")),
			_pz(6, _ej_ordenar("Ordena el ciclo de TDD (desarrollo guiado por pruebas).", [
				"Escribir una prueba que falla (rojo)", "Escribir el código mínimo para que pase (verde)", "Refactorizar el código", "Repetir con la siguiente prueba"],
				"En TDD la prueba va antes que el código: rojo → verde → refactorizar.", "tdd")),
			# ---- Tema 7 ----
			_pz(7, _ej_clasificar("¿Es una métrica de producto, de proceso o de proyecto?", ["Producto", "Proceso", "Proyecto"], [
				["Líneas de código del módulo", "Producto"], ["Tiempo promedio para corregir un defecto", "Proceso"], ["Porcentaje de avance contra el calendario", "Proyecto"], ["Complejidad ciclomática de una función", "Producto"], ["Defectos encontrados por revisión", "Proceso"], ["Horas gastadas contra las planeadas", "Proyecto"]],
				"Producto = mide el software; proceso = mide cómo se trabaja; proyecto = mide avance, costo y calendario.", "tipos_metricas")),
			_pz(7, _ej_clasificar("Al cierre de la semana: PV = 50 %, EV = 40 % y AC = 55 h de 50 h planeadas. Clasifica cada afirmación.", ["Verdadero", "Falso"], [
				["El proyecto va retrasado", "Verdadero"], ["SPI = 0.8", "Verdadero"], ["Se ha gastado menos esfuerzo del planeado", "Falso"], ["CPI es menor que 1", "Verdadero"], ["El equipo va adelantado", "Falso"]],
				"EV < PV → retraso; SPI = 40/50 = 0.8; AC (55 h) > planeado (50 h) → CPI < 1.", "valor_ganado")),
			_pz(7, _ej_ordenar("Ordena los pasos del enfoque GQM para definir qué medir.", [
				"Definir la meta (Goal)", "Formular las preguntas que dicen si se cumple la meta", "Elegir las métricas que responden cada pregunta", "Recolectar los datos", "Interpretar los resultados contra la meta"],
				"GQM = Goal, Question, Metric: primero la meta, luego las preguntas y al final las métricas.", "tipos_metricas")),
			# ---- Tema 8 ----
			_pz(8, _ej_ordenar("Ordena los eventos de un sprint de Scrum.", [
				"Sprint Planning", "Daily Scrum (cada día)", "Sprint Review", "Sprint Retrospective"],
				"Se planea, se trabaja con un Daily cada día, se revisa el producto y al final se revisa la forma de trabajar.", "daily")),
			_pz(8, _ej_seleccionar("El sprint tiene 16 h disponibles. Elige las historias que caben, priorizando alta y luego media.", 16, [
				["Iniciar sesión · prioridad alta", 7, true], ["Ver catálogo de cursos · prioridad alta", 5, true], ["Filtrar cursos por tema · prioridad media", 4, true], ["Recuperar contraseña · prioridad media", 3, false], ["Animación de bienvenida · prioridad baja", 2, false]],
				"7 + 5 + 4 = 16 h; ya no cabe ninguna otra historia.", "sprint")),
			_pz(8, _ej_clasificar("¿A quién le toca cada responsabilidad en Scrum?", ["Product Owner", "Scrum Master", "Equipo de desarrollo"], [
				["Priorizar el Product Backlog", "Product Owner"], ["Quitar impedimentos y facilitar los eventos", "Scrum Master"], ["Estimar y construir las historias del sprint", "Equipo de desarrollo"], ["Decidir qué entra en la siguiente versión", "Product Owner"], ["Cuidar que se siga Scrum", "Scrum Master"], ["Decidir cómo construir cada historia", "Equipo de desarrollo"]],
				"El PO decide el qué y el orden; el SM cuida el proceso; el equipo decide el cómo y construye.", "product_owner")),
			# ---- Tema 9 ----
			_pz(9, _ej_clasificar("¿Es una actividad de verificación o de validación?", ["Verificación", "Validación"], [
				["Revisar que el código cumpla el estándar de codificación", "Verificación"], ["Mostrar el prototipo al cliente", "Validación"], ["Inspeccionar el SRS buscando contradicciones", "Verificación"], ["Pruebas de aceptación con usuarios reales", "Validación"], ["Comprobar que el diseño cumple el SRS", "Verificación"], ["Preguntar a los alumnos si la app les ayuda a estudiar", "Validación"]],
				"Contra el documento → verificación; contra la necesidad del usuario → validación.", "verif_valid")),
			_pz(9, _ej_clasificar("¿A qué característica de ISO/IEC 25010 corresponde cada requerimiento no funcional?", ["Usabilidad", "Fiabilidad", "Mantenibilidad", "Portabilidad"], [
				["Un alumno nuevo completa su perfil sin ayuda", "Usabilidad"], ["No perder el progreso si la app se cierra de golpe", "Fiabilidad"], ["Agregar un tema nuevo sin tocar las demás pantallas", "Mantenibilidad"], ["Funcionar en Android y en iOS", "Portabilidad"], ["Recuperarse sin perder datos tras un fallo", "Fiabilidad"], ["Que el código sea fácil de modificar", "Mantenibilidad"]],
				"Fácil de usar = usabilidad; no fallar y recuperarse = fiabilidad; fácil de cambiar = mantenibilidad; correr en varios entornos = portabilidad.", "iso25010")),
			_pz(9, _ej_ordenar("Ordena los pasos de una inspección de software.", [
				"Planear la inspección y repartir el artefacto", "Lectura individual buscando defectos", "Reunión de inspección para registrar los defectos", "Corregir los defectos encontrados", "Verificar que las correcciones quedaron bien"],
				"Primero cada quien lee, luego se juntan los hallazgos, se corrige y se verifica; encontrar defectos sin ejecutar cuesta menos que en pruebas.", "revisiones")),
			# ---- Tema 10 ----
			_pz(10, _ej_ordenar("Ordena los pasos para compartir un cambio con tu equipo en Git.", [
				"git pull (traer lo último)", "Modificar los archivos", "git add (preparar los cambios)", "git commit (guardar en el historial)", "git push (subir al remoto)"],
				"Primero actualizas tu copia para evitar conflictos; luego cambias, preparas, guardas y subes.", "repo_remoto")),
			_pz(10, _ej_clasificar("¿Es un buen mensaje de commit o uno malo?", ["Buen mensaje", "Mal mensaje"], [
				["Agrega validación del alias de 3 a 20 caracteres", "Buen mensaje"], ["cambios", "Mal mensaje"], ["Corrige el cálculo del porcentaje en registrar_intento", "Buen mensaje"], ["asdf", "Mal mensaje"], ["ya quedó", "Mal mensaje"], ["Elimina el módulo duplicado del mapa", "Buen mensaje"]],
				"Un buen mensaje dice qué cambió y por qué; «cambios» o «asdf» no le sirven a nadie dentro de una semana.", "commit_git")),
			_pz(10, _ej_clasificar("¿Qué comando de Git usarías?", ["git branch", "git merge", "git pull", "git push"], [
				["Crear una línea de trabajo aparte para el CU-08", "git branch"], ["Unir la rama feature/CU-08 a main", "git merge"], ["Traer a mi copia lo que subieron mis compañeros", "git pull"], ["Subir mis commits al repositorio remoto", "git push"], ["Juntar dos ramas y resolver conflictos si los hay", "git merge"], ["Actualizar mi main antes de empezar", "git pull"]],
				"branch = separar; merge = unir; pull = traer; push = subir.", "ramas")),
			# ---- Tema 11 ----
			_pz(11, _ej_ordenar("Ordena los pasos de la gestión de riesgos.", [
				"Identificar los riesgos", "Analizar su probabilidad e impacto", "Planear la respuesta", "Monitorear los riesgos"],
				"No se puede responder a un riesgo que no se ha identificado ni analizado; el monitoreo dura todo el proyecto.", "riesgo")),
			_pz(11, _ej_clasificar("¿Qué estrategia ante el riesgo se está aplicando?", ["Evitar", "Mitigar", "Transferir", "Aceptar"], [
				["Cambiar de librería porque la actual podría quedar sin soporte", "Evitar"], ["Hacer respaldos diarios por si se daña el disco", "Mitigar"], ["Contratar un proveedor que se haga responsable del servidor", "Transferir"], ["Seguir adelante y tener un plan B si el integrante se enferma", "Aceptar"], ["Capacitar al equipo en Godot para reducir los errores", "Mitigar"], ["Comprar un seguro para el equipo de cómputo", "Transferir"]],
				"Quitarlo = evitar; achicarlo = mitigar; pasarlo a otro = transferir; asumirlo con plan B = aceptar.", "estrategias_riesgo")),
			_pz(11, _ej_seleccionar("Esta semana el equipo tiene 24 h disponibles. Elige las tareas del plan que caben, priorizando alta y luego media.", 24, [
				["Codificar CU-08 · prioridad alta", 10, true], ["Pruebas de CU-08 · prioridad alta", 6, true], ["Actualizar el SRS · prioridad media", 4, true], ["Manual de usuario · prioridad media", 8, false], ["Rediseñar el logo · prioridad baja", 6, false]],
				"10 + 6 + 4 = 20 h; el manual (8 h) ya no cabe y el logo es prioridad baja: alcance, tiempo y costo se equilibran.", "triple_restriccion")),
			# ---- Tema 12 ----
			_pz(12, _ej_clasificar("¿Es una conducta ética o no ética?", ["Ética", "No ética"], [
				["Usar una librería respetando su licencia", "Ética"], ["Entregar el código de otro equipo como propio", "No ética"], ["Avisar al cliente que el proyecto se va a retrasar", "Ética"], ["Ocultar un defecto conocido para entregar a tiempo", "No ética"], ["Pedir permiso antes de recolectar datos personales", "Ética"], ["Guardar las contraseñas en texto plano", "No ética"]],
				"Respetar licencias, informar a tiempo y proteger a los usuarios es ético; plagiar, ocultar defectos y descuidar datos no lo es.", "codigo_etica")),
			_pz(12, _ej_clasificar("¿Qué principio ético está en juego en cada caso?", ["Privacidad", "Honestidad", "Licencias"], [
				["Pedir consentimiento antes de recolectar datos", "Privacidad"], ["Avisar al cliente del retraso en cuanto se detecta", "Honestidad"], ["Revisar los términos antes de usar código ajeno", "Licencias"], ["Guardar las contraseñas con hash", "Privacidad"], ["No ocultar un defecto conocido", "Honestidad"], ["Dar crédito al autor del código reutilizado", "Licencias"]],
				"Datos de los usuarios → privacidad; decir la verdad al cliente → honestidad; respetar al autor → licencias.", "licencias")),
		],
		# ---- CU-11: una práctica de ingeniero por tema (escenario; los ejercicios se sortean del banco) ----
		"practicas": [
			_practica(1, "Tu primer programa", "Vas a aplicar la lógica de programación básica y los fundamentos de la ingeniería de software: algoritmos, estructuras de control, tipos de datos y atributos del buen software."),
			_practica(2, "Elegir el modelo", "Un despacho recibe tres proyectos distintos. Vas a decidir qué modelo de ciclo de vida le conviene a cada uno y en qué orden se trabaja."),
			_practica(3, "Biblioteca escolar", "El cliente, la biblioteca de una preparatoria, pide una app para registrar préstamos de libros. Vas a obtener, escribir, priorizar y validar sus requerimientos."),
			_practica(4, "Control escolar", "Vas a modelar con UML un sistema de control escolar: elegir el diagrama correcto, colocar actores y casos de uso y distinguir include de extend."),
			_practica(5, "Diseñar la app de pedidos", "Una fonda quiere una app para recibir pedidos. Vas a repartir responsabilidades con MVC, detectar malas decisiones de diseño y aplicar los principios básicos."),
			_practica(6, "Probar el registro", "Vas a planear las pruebas de un formulario de registro: valores límite, niveles de prueba, corrección de defectos y TDD."),
			_practica(7, "Medir el proyecto", "Tu equipo quiere saber si el proyecto va bien. Vas a clasificar métricas, leer el valor ganado y definir qué medir con GQM."),
			_practica(8, "Planear el sprint", "Tu equipo Scrum inicia un sprint de dos semanas. Vas a ordenar los eventos, elegir las historias que caben y repartir responsabilidades."),
			_practica(9, "Asegurar la calidad", "Antes de la entrega, vas a distinguir verificación de validación, ubicar cada requerimiento no funcional en ISO/IEC 25010 y organizar una inspección."),
			_practica(10, "Trabajar con Git", "Tu equipo comparte el código en GitHub. Vas a ordenar el flujo de trabajo, escribir buenos commits y elegir el comando correcto."),
			_practica(11, "Gestionar el proyecto", "Como gerente de planeación, vas a administrar los riesgos del semestre y decidir qué tareas caben en las horas disponibles."),
			_practica(12, "Decidir con ética", "Vas a enfrentar dilemas reales del desarrollo de software: licencias, honestidad con el cliente y privacidad de los usuarios."),
		],
		"intentos_practica": [],
	}

func _tema(id: int, nombre: String, corto: String, descripcion: String, icono: String, color: String) -> Dictionary:
	return {
		"id": id,
		"nombre": nombre,
		"corto": corto,            # nombre corto para chips y etiquetas
		"descripcion": descripcion,
		"icono": icono,            # tipo de Icono.gd
		"color": color,
	}

func _practica(id_tema: int, titulo: String, escenario: String) -> Dictionary:
	return {
		"id_tema": id_tema,
		"titulo": titulo,
		"escenario": escenario,
		"intentos": 0,
		"mejor_porcentaje": -1,
		"mejor_puntos": 0,
		"dominada": false,
	}

## Asigna un ejercicio de manipulación a un tema.
func _pz(id_tema: int, ej: Dictionary) -> Dictionary:
	ej["id_tema"] = id_tema
	return ej

## Ejercicio "clasificar": tocar la etiqueta de cada tarjeta para asignarle categoría.
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

func _concepto(id: String, id_tema: int, titulo: String, explicacion: String, claves: Array, truco: String) -> Dictionary:
	return {
		"id": id,
		"id_tema": id_tema,
		"titulo": titulo,
		"explicacion": explicacion,
		"claves": claves,          # ideas clave (chips en la pantalla de teoría)
		"truco": truco,            # truco rápido para recordarlo (también es la pista de CU-10)
	}

func _insignia(id: String, titulo: String, descripcion: String, metrica: String, niveles: Array, unidad: String, condiciones: Array, icono: String, color: String) -> Dictionary:
	return {
		"id": id,
		"tipo": "logro",
		"titulo": titulo,
		"descripcion": descripcion,   # texto que se muestra al obtenerla
		"metrica": metrica,           # cifra del progreso que la hace subir de nivel (ver _metricas)
		"niveles": niveles,           # umbrales [bronce, plata, oro]
		"unidad": unidad,             # nombre de la cifra ("retos con 100 %")
		"condiciones": condiciones,   # "Cómo se obtiene" por nivel
		"condicion": condiciones[0],  # compatibilidad con pantallas anteriores
		"icono": icono,               # tipo de Icono.gd
		"color": color,
		"nivel": 0,                   # 0 bloqueada · 1 bronce · 2 plata · 3 oro
		"progreso": 0,
		"obtenida": false,
		"fecha": "",
	}

## Medalla de un tema: bronce / plata / oro según el promedio de sus módulos.
func _medalla_tema(id_tema: int, corto: String, icono: String, color: String) -> Dictionary:
	var ins := _insignia("tema_%d" % id_tema, "Medalla · %s" % corto,
		"Dominas el tema %s: sus tres módulos completados." % corto,
		"promedio_tema", [70, 85, 100], "% promedio",
		["Completa los 3 módulos del tema con promedio ≥ 70 %", "Promedio ≥ 85 % en los 3 módulos", "100 % en los 3 módulos"],
		icono, color)
	ins["tipo"] = "tema"
	ins["id_tema"] = id_tema
	return ins

func _modulo(id: int, nombre: String, tipo: String, descripcion: String, estado: String = "bloqueado", id_tema: int = 1, num_preguntas: int = PREGUNTAS_POR_QUIZ) -> Dictionary:
	return {
		"id": id,
		"id_tema": id_tema,          # CU-08: tema al que pertenece el módulo
		"nombre": nombre,
		"tipo": tipo,                # "quiz" | "puzzle"
		"descripcion": descripcion,
		"num_preguntas": num_preguntas,   # preguntas que se sortean (quiz) o ejercicios (puzzle)
		"puntos_maximos": 100,
		"estado": estado,            # "bloqueado" | "desbloqueado" | "completado"
		"mejor_puntaje": -1,         # % (-1 = sin intentos)
		"puntos_obtenidos": 0,       # puntos del mejor intento completado (suma al total)
	}

func _reactivo(id: int, id_tema: int, pregunta: String, opciones: Array, correcta: int, retro: String, id_concepto: String = "") -> Dictionary:
	return {
		"id": id,
		"id_tema": id_tema,          # banco del tema; cada quiz sortea 5
		"pregunta": pregunta,
		"opciones": opciones,
		"respuesta_correcta": correcta,
		"retroalimentacion": retro,
		"id_concepto": id_concepto,  # concepto de teoría asociado (CU-04); "" = sin concepto
	}
