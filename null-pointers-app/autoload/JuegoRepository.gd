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
#  CU-01: GESTIONAR PERFIL DE JUGADOR
# =====================================================================
func existe_perfil() -> bool:
	return bd["perfil_jugador"]["alias"] != ""

func obtener_perfil() -> Dictionary:
	return bd["perfil_jugador"]

## Crea el perfil. Regresa false si el alias está vacío (validación del CU-01, paso 4).
func crear_perfil(alias: String) -> bool:
	alias = alias.strip_edges()
	if alias.is_empty():
		return false
	bd["perfil_jugador"]["alias"] = alias
	bd["perfil_jugador"]["fecha_creacion"] = Time.get_datetime_string_from_system()
	guardar_bd()
	return true

## Edita el alias de un perfil existente.
func actualizar_nombre(nuevo_alias: String) -> bool:
	nuevo_alias = nuevo_alias.strip_edges()
	if nuevo_alias.is_empty():
		return false
	bd["perfil_jugador"]["alias"] = nuevo_alias
	guardar_bd()
	return true

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
			"alias": "",
			"puntos_totales": 0,
			"fecha_creacion": "",
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
