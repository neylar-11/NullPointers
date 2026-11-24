# res://assets/ui/Logo.gd
# Logo de SoftPlay en estilo terminal: "> soft.play()" con cursor parpadeante.
# Se dibuja por código con fuente monoespaciada (sin imágenes), igual que el resto de la UI.
#   tamano      : tamaño de la fuente en px (el ancho se calcula solo)
#   oscuro      : true = texto claro sobre fondo oscuro (pantalla de inicio)
#   escribir    : true = anima el texto letra por letra al aparecer
@tool
extends Control
class_name LogoSoftPlay

const TEXTO := "soft.play()"
const VERDE := Color("#178A4C")
const VERDE_CLARO := Color("#4ADE80")
const AZUL := Color("#2F55E6")
const AZUL_CLARO := Color("#8FA6F5")
const NARANJA := Color("#C2410C")
const TINTA := Color("#15192B")

@export var tamano: int = 48:
	set(v):
		tamano = v
		_actualizar_minimo()
		queue_redraw()
@export var oscuro: bool = false:
	set(v):
		oscuro = v
		queue_redraw()
@export var escribir: bool = false
@export var velocidad: float = 0.07      # segundos por letra al escribir

var fuente: Font = preload("res://assets/fonts/DejaVuSansMono-Bold.ttf")
var letras_visibles: int = TEXTO.length()
var cursor_visible := true
var _t := 0.0
var _parpadeo := 0.0

signal escritura_terminada

func _ready() -> void:
	_actualizar_minimo()
	if escribir and not Engine.is_editor_hint():
		letras_visibles = 0
	set_process(not Engine.is_editor_hint())

func _process(delta: float) -> void:
	if letras_visibles < TEXTO.length():
		_t += delta
		if _t >= velocidad:
			_t = 0.0
			letras_visibles += 1
			queue_redraw()
			if letras_visibles == TEXTO.length():
				escritura_terminada.emit()
	_parpadeo += delta
	if _parpadeo >= 0.5:
		_parpadeo = 0.0
		cursor_visible = not cursor_visible
		queue_redraw()

func _actualizar_minimo() -> void:
	var ancho := fuente.get_string_size("> " + TEXTO + " ", HORIZONTAL_ALIGNMENT_LEFT, -1, tamano).x + tamano * 0.5
	custom_minimum_size = Vector2(ancho, tamano * 1.35)

func _draw() -> void:
	var ancho_char := fuente.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, tamano).x
	var y := size.y / 2.0 + fuente.get_ascent(tamano) * 0.38
	var x := 0.0
	var verde := VERDE_CLARO if oscuro else VERDE
	var azul := AZUL_CLARO if oscuro else AZUL
	var tinta := Color.WHITE if oscuro else TINTA
	# ">" prompt
	draw_string(fuente, Vector2(x, y), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, tamano, verde)
	x += ancho_char * 2
	# "soft" en tinta, ".play()" en azul, letra por letra para poder animar
	for i in letras_visibles:
		var ch := TEXTO[i]
		var color := tinta if i < 4 else azul
		draw_string(fuente, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, tamano, color)
		x += ancho_char
	# cursor
	if cursor_visible:
		var alto := fuente.get_ascent(tamano) * 0.95
		draw_rect(Rect2(Vector2(x + ancho_char * 0.15, y - alto * 0.88), Vector2(ancho_char * 0.55, alto)), NARANJA)
