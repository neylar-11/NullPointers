# res://autoload/JuegoRepository.gd
# Base de datos local (Autoload / Singleton) de NullPointers-AppGamificada.
# Persiste en user:// (memoria interna de la app) como JSON → 100 % offline (RNF-01, RNF-02).
#
# Tablas (SDS): perfil_jugador, modulos, reactivos, intentos_modulo, conceptos, insignias
# Casos de uso cubiertos: CU-01 (perfil), CU-02 (mapa), CU-03 (actividad),
#                         CU-04 (teoría), CU-05 (insignias), CU-06 (progreso)
#
# Uso desde cualquier escena:
#   JuegoRepository.crear_perfil("estudiante_7421")
#   JuegoRepository.obtener_modulos()
#   JuegoRepository.registrar_intento(3, 4)   # módulo 3, 4 aciertos de 5
#   JuegoRepository.obtener_concepto(id_reactivo)   # CU-04
#   JuegoRepository.obtener_insignias()             # CU-05
#   JuegoRepository.obtener_progreso()              # CU-06

extends Node

const RUTA_BD := "user://nullpointers_bd.json"
const PORCENTAJE_MINIMO := 70        # % necesario para completar un módulo (mockups / CU-03)

var bd: Dictionary = {}
var modulo_seleccionado: int = 1      # lo pone el mapa (CU-02) antes de abrir la actividad

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
func registrar_intento(id_modulo: int, aciertos: int) -> Dictionary:
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
	})

	# 2) Conservar el mejor puntaje ("Se conserva tu mejor puntaje")
	var puntos_sumados := 0
	if porcentaje > mejor_previo:
		modulo["mejor_puntaje"] = porcentaje
		if completado:
			puntos_sumados = puntos - puntos_previos      # solo la mejora cuenta al total
			modulo["puntos_obtenidos"] = puntos
			bd["perfil_jugador"]["puntos_totales"] = obtener_puntos_totales() + puntos_sumados

	# 3) Marcar completado y desbloquear el siguiente de forma permanente
	var siguiente_desbloqueado: Dictionary = {}
	if completado:
		modulo["estado"] = "completado"
		var siguiente := obtener_modulo(id_modulo + 1)
		if not siguiente.is_empty() and siguiente["estado"] == "bloqueado":
			siguiente["estado"] = "desbloqueado"
			siguiente_desbloqueado = siguiente

	# 4) Insignias que se desbloquean con este intento (CU-05)
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
	}


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

	var racha := 0      # módulos consecutivos completados desde el 1
	for m in bd["modulos"]:
		if m["estado"] == "completado":
			racha += 1
		else:
			break

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
		if cumple:
			ins["obtenida"] = true
			ins["fecha_obtencion"] = Time.get_datetime_string_from_system()
			nuevas.append(ins)
	return nuevas


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
		var fila := {
			"id": int(m["id"]),
			"nombre": m["nombre"],
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
		"modulos": [
			_modulo(1, "Fundamentos", "quiz", "5 preguntas sobre qué es la ingeniería de software.", "desbloqueado"),
			_modulo(2, "Ciclo de vida", "quiz", "5 preguntas sobre modelos de ciclo de vida."),
			_modulo(3, "Requerimientos de software", "quiz", "5 preguntas sobre requerimientos funcionales y no funcionales."),
			_modulo(4, "Modelado con UML", "quiz", "5 preguntas sobre diagramas UML."),
			_modulo(5, "Diseño", "puzzle", "Acertijos de diseño y arquitectura."),
			_modulo(6, "Pruebas", "quiz", "5 preguntas sobre pruebas de software."),
			_modulo(7, "Métricas", "puzzle", "Acertijos sobre métricas y estimación."),
			_modulo(8, "Gestión ágil", "quiz", "5 preguntas sobre Scrum y metodologías ágiles."),
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
			_insignia("ingeniero", "Ingeniero", "Recorriste todo el mapa: completaste los ocho módulos.", "Completa los 8 módulos con al menos 70 %.", "mapa", "#B45309"),
			_insignia("perfeccionista", "Perfeccionista", "Nada se te escapó: 100 % en todos los módulos.", "Alcanza 100 % como mejor puntaje en los 8 módulos.", "estrella", "#14633A"),
		],
	}

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

func _modulo(id: int, nombre: String, tipo: String, descripcion: String, estado: String = "bloqueado") -> Dictionary:
	return {
		"id": id,
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
