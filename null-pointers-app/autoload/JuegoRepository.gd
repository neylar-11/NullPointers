# res://autoload/JuegoRepository.gd
# Base de datos local (Autoload / Singleton) de NullPointers-AppGamificada.
# Persiste en user:// (memoria interna de la app) como JSON → 100 % offline (RNF-01, RNF-02).
#
# Tablas (SDS): perfil_jugador, modulos, reactivos, intentos_modulo
# Casos de uso cubiertos: CU-01 (perfil), CU-02 (mapa de módulos), CU-03 (resolver actividad)
#
# Uso desde cualquier escena:
#   JuegoRepository.crear_perfil("estudiante_7421")
#   JuegoRepository.obtener_modulos()
#   JuegoRepository.registrar_intento(3, 4)   # módulo 3, 4 aciertos de 5

extends Node

const RUTA_BD := "user://nullpointers_bd.json"
const PORCENTAJE_MINIMO := 70        # % necesario para completar un módulo (mockups / CU-03)

var bd: Dictionary = {}
var modulo_seleccionado: int = 1      # lo pone el mapa (CU-02) antes de abrir la actividad

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
				"La ingeniería de software aplica principios de ingeniería al desarrollo, operación y mantenimiento del software."),
			_reactivo(2, 1, "¿Cuál NO es una característica del software?",
				["Se desarrolla, no se fabrica", "No se desgasta físicamente", "Se oxida con el tiempo", "La mayoría se construye a la medida"], 2,
				"El software no se desgasta físicamente, pero sí se deteriora por cambios y falta de mantenimiento."),
			_reactivo(3, 1, "¿Qué documento define QUÉ debe hacer el sistema?",
				["SRS", "Manual de usuario", "Plan de pruebas", "Diagrama de clases"], 0,
				"El SRS (Especificación de Requisitos de Software) describe qué debe hacer el sistema."),
			_reactivo(4, 1, "La fase donde se corrige y mejora el software ya entregado se llama:",
				["Análisis", "Diseño", "Mantenimiento", "Codificación"], 2,
				"El mantenimiento ocurre después de la entrega e incluye correcciones y mejoras."),
			_reactivo(5, 1, "¿Cuál es un estándar para procesos de software en equipos pequeños?",
				["ISO/IEC 29110", "HTML5", "IEEE 802.11", "USB 3.0"], 0,
				"ISO/IEC 29110 define perfiles de proceso para Very Small Entities (VSE)."),
			# ---- Módulo 3 · Requerimientos (del mockup) ----
			_reactivo(6, 3, "¿Qué es un requerimiento funcional?",
				["Una acción o servicio que el sistema debe realizar", "El color de la interfaz", "El tiempo de respuesta del sistema", "El presupuesto del proyecto"], 0,
				"Un requerimiento funcional describe lo que el sistema debe hacer."),
			_reactivo(7, 3, "¿Quién es la fuente principal de los requerimientos?",
				["El compilador", "Los stakeholders / cliente", "El servidor", "El sistema operativo"], 1,
				"Los requerimientos se obtienen de los interesados (stakeholders) del sistema."),
			_reactivo(8, 3, "¿Cuál de estos es un requerimiento no funcional?",
				["Responder en menos de 2 segundos", "Registrar un nuevo pedido", "Enviar correo al confirmar la compra", "Generar el reporte mensual de ventas"], 0,
				"Un requerimiento no funcional describe una cualidad del sistema (rendimiento, seguridad, usabilidad), no una acción."),
			_reactivo(9, 3, "La característica de un requerimiento de poder ser probado se llama:",
				["Ambigüedad", "Verificabilidad", "Redundancia", "Volatilidad"], 1,
				"Un requerimiento verificable puede comprobarse mediante una prueba."),
			_reactivo(10, 3, "¿Qué actividad consiste en obtener los requerimientos del cliente?",
				["Elicitación", "Compilación", "Despliegue", "Refactorización"], 0,
				"La elicitación es la actividad de descubrir y recolectar los requerimientos."),
			# ---- Módulo 2 · Ciclo de vida ----
			_reactivo(11, 2, "¿Cuál es la primera fase del modelo en cascada?",
				["Pruebas", "Análisis de requerimientos", "Implementación", "Mantenimiento"], 1,
				"El modelo en cascada inicia con el análisis de requerimientos y avanza secuencialmente."),
			_reactivo(12, 2, "¿Qué modelo repite ciclos cortos entregando versiones funcionales?",
				["Cascada", "Iterativo e incremental", "Big Bang", "Modelo V"], 1,
				"Los modelos iterativos e incrementales entregan versiones funcionales en ciclos cortos."),
			_reactivo(13, 2, "¿En qué modelo se construye un prototipo para validar requerimientos con el cliente?",
				["Prototipado", "Cascada", "Espiral puro", "RAD"], 0,
				"El modelo de prototipado construye versiones preliminares para validar con el usuario."),
			_reactivo(14, 2, "El modelo en espiral se caracteriza por enfocarse en:",
				["La documentación", "El análisis de riesgos", "La velocidad de entrega", "Las pruebas unitarias"], 1,
				"Cada vuelta de la espiral incluye un análisis explícito de riesgos (Boehm)."),
			_reactivo(15, 2, "¿Cuál de estos es un marco de trabajo ágil?",
				["Scrum", "Cascada", "Modelo V", "CMMI"], 0,
				"Scrum es un marco ágil basado en sprints, roles y eventos definidos."),
			# ---- Módulo 4 · Modelado con UML ----
			_reactivo(16, 4, "¿Qué diagrama UML muestra los actores y las funcionalidades del sistema?",
				["Diagrama de clases", "Diagrama de casos de uso", "Diagrama de despliegue", "Diagrama de paquetes"], 1,
				"El diagrama de casos de uso representa actores y las funciones que el sistema les ofrece."),
			_reactivo(17, 4, "¿Qué diagrama representa la estructura estática con atributos y métodos?",
				["Diagrama de clases", "Diagrama de secuencia", "Diagrama de actividad", "Diagrama de estados"], 0,
				"El diagrama de clases describe la estructura estática: clases, atributos, métodos y relaciones."),
			_reactivo(18, 4, "¿Qué diagrama muestra el intercambio de mensajes entre objetos en el tiempo?",
				["Diagrama de componentes", "Diagrama de secuencia", "Diagrama de objetos", "Diagrama de clases"], 1,
				"El diagrama de secuencia ordena en el tiempo los mensajes entre objetos."),
			_reactivo(19, 4, "En UML, la relación 'es un tipo de' se modela con:",
				["Asociación", "Dependencia", "Herencia (generalización)", "Agregación"], 2,
				"La generalización (herencia) expresa que una clase es un tipo especializado de otra."),
			_reactivo(20, 4, "¿Qué diagrama describe el flujo de trabajo paso a paso con decisiones?",
				["Diagrama de actividad", "Diagrama de despliegue", "Diagrama de clases", "Diagrama de paquetes"], 0,
				"El diagrama de actividad modela flujos de trabajo con acciones, decisiones y bifurcaciones."),
			# ---- Módulo 5 · Diseño ----
			_reactivo(21, 5, "¿Qué principio busca que cada módulo tenga una sola responsabilidad?",
				["Acoplamiento", "Responsabilidad única", "Redundancia", "Herencia múltiple"], 1,
				"El principio de responsabilidad única (SRP) dice que un módulo debe tener una sola razón para cambiar."),
			_reactivo(22, 5, "Un diseño con bajo acoplamiento y alta cohesión es:",
				["Difícil de mantener", "Deseable", "Imposible", "Más lento"], 1,
				"Bajo acoplamiento y alta cohesión facilitan el mantenimiento y la reutilización."),
			_reactivo(23, 5, "¿Qué patrón separa la interfaz, la lógica y los datos?",
				["Singleton", "MVC / MVVM", "Observador", "Fábrica"], 1,
				"MVC y MVVM separan la vista, la lógica y el modelo de datos."),
			_reactivo(24, 5, "¿Qué patrón garantiza una única instancia de una clase?",
				["Singleton", "Adaptador", "Decorador", "Estrategia"], 0,
				"Singleton restringe la instanciación a un único objeto (como un Autoload en Godot)."),
			_reactivo(25, 5, "La arquitectura en capas organiza el sistema en:",
				["Procesos paralelos", "Niveles con responsabilidades definidas", "Un solo archivo", "Hilos"], 1,
				"Cada capa (presentación, lógica, datos) tiene responsabilidades claras y se comunica con la adyacente."),
			# ---- Módulo 6 · Pruebas ----
			_reactivo(26, 6, "¿Qué prueba verifica una función o clase de forma aislada?",
				["Prueba de sistema", "Prueba unitaria", "Prueba de aceptación", "Prueba de carga"], 1,
				"Las pruebas unitarias validan la unidad más pequeña de código de forma aislada."),
			_reactivo(27, 6, "Las pruebas de caja negra se basan en:",
				["El código fuente", "Las entradas y salidas esperadas", "La cobertura de ramas", "El compilador"], 1,
				"La caja negra prueba el comportamiento externo sin conocer la implementación interna."),
			_reactivo(28, 6, "¿Qué prueba realiza el cliente para validar que el sistema cumple sus necesidades?",
				["Prueba de aceptación", "Prueba unitaria", "Prueba de integración", "Prueba de regresión"], 0,
				"La prueba de aceptación la realiza el cliente o usuario final antes de aprobar la entrega."),
			_reactivo(29, 6, "¿Qué prueba comprueba que un cambio no rompió lo que ya funcionaba?",
				["Prueba de humo", "Prueba de regresión", "Prueba alfa", "Prueba de estrés"], 1,
				"Las pruebas de regresión se repiten tras cada cambio para detectar errores reintroducidos."),
			_reactivo(30, 6, "Un caso de prueba debe incluir al menos:",
				["Entrada y resultado esperado", "El nombre del programador", "El costo", "El diagrama de Gantt"], 0,
				"Todo caso de prueba define datos de entrada, pasos y el resultado esperado."),
			# ---- Módulo 7 · Métricas ----
			_reactivo(31, 7, "¿Qué mide la métrica 'líneas de código' (LOC)?",
				["La calidad", "El tamaño del software", "La seguridad", "La usabilidad"], 1,
				"LOC es una métrica de tamaño; no mide calidad ni complejidad por sí sola."),
			_reactivo(32, 7, "La complejidad ciclomática mide:",
				["El número de caminos independientes del código", "El tamaño del equipo", "El tiempo de compilación", "La memoria usada"], 0,
				"McCabe definió la complejidad ciclomática como el número de caminos linealmente independientes."),
			_reactivo(33, 7, "¿Qué técnica estima el tamaño funcional desde el punto de vista del usuario?",
				["Puntos de función", "Horas-hombre", "Velocidad de CPU", "Bugs por día"], 0,
				"Los puntos de función miden funcionalidad entregada al usuario, independiente del lenguaje."),
			_reactivo(34, 7, "El 'valor ganado' compara:",
				["Trabajo planificado contra trabajo realizado", "Salarios", "Versiones", "Errores"], 0,
				"El valor ganado (EV) relaciona el avance real contra lo planeado y lo gastado."),
			_reactivo(35, 7, "¿Qué métrica ayuda a estimar la densidad de defectos?",
				["Defectos por KLOC", "Pulgadas de pantalla", "Número de reuniones", "Ancho de banda"], 0,
				"Defectos por cada mil líneas de código (KLOC) es una métrica clásica de calidad."),
			# ---- Módulo 8 · Gestión ágil ----
			_reactivo(36, 8, "¿Cómo se llama la iteración de tiempo fijo en Scrum?",
				["Fase", "Sprint", "Hito", "Release"], 1,
				"El sprint es la iteración de duración fija (1-4 semanas) en Scrum."),
			_reactivo(37, 8, "¿Quién prioriza el Product Backlog?",
				["Scrum Master", "Product Owner", "El equipo de pruebas", "El cliente final directamente"], 1,
				"El Product Owner es responsable de ordenar y priorizar el Product Backlog."),
			_reactivo(38, 8, "¿Qué evento diario dura máximo 15 minutos?",
				["Sprint Review", "Daily Scrum", "Sprint Planning", "Retrospectiva"], 1,
				"El Daily Scrum es una reunión corta diaria para sincronizar al equipo."),
			_reactivo(39, 8, "¿Qué tablero visualiza el flujo de trabajo en columnas (Por hacer, En curso, Hecho)?",
				["Gantt", "Kanban", "PERT", "Ishikawa"], 1,
				"El tablero Kanban muestra el flujo de trabajo y limita el trabajo en curso."),
			_reactivo(40, 8, "¿Qué evento sirve para que el equipo mejore su forma de trabajar?",
				["Sprint Retrospective", "Sprint Review", "Refinamiento", "Daily Scrum"], 0,
				"En la retrospectiva el equipo reflexiona sobre su proceso y acuerda mejoras."),
		],
		"intentos_modulo": [],
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

func _reactivo(id: int, id_modulo: int, pregunta: String, opciones: Array, correcta: int, retro: String) -> Dictionary:
	return {
		"id": id,
		"id_modulo": id_modulo,
		"pregunta": pregunta,
		"opciones": opciones,
		"respuesta_correcta": correcta,   # índice (0-3) dentro de opciones
		"retroalimentacion": retro,       # para CU-04
	}
