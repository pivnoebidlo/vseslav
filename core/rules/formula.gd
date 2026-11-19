class_name Formula
extends RefCounted
## Формула из данных: "1d8 + STR", "8 + PROF + WIS", "max(1, 2d4 - 1)" (ADR-0008).
## Белый список: целые числа, кости NdM (N можно опустить), + - * /, унарный минус,
## скобки, min(a, b), max(a, b), переменные из VARIABLES. Деление — вниз.
## Godot Expression не используется: он даёт доступ к методам объектов.

enum Kind { NUM, DICE, VAR, ADD, SUB, MUL, DIV, NEG, MIN, MAX }

## Переменные, которые можно использовать в данных. Значения даёт вызывающий.
const VARIABLES: Array[String] = [
	"STR", "DEX", "CON", "INT", "WIS", "CHA", "PROF", "LEVEL", "SPELL", "MOD"
]
const MAX_LENGTH := 200
const MAX_DICE := 100
const MAX_SIDES := 1000

## Исходный текст.
var text: String = ""
## Пусто, если формула корректна.
var error: String = ""
## Программа в обратной польской записи.
var _ops: Array[Op] = []


## Одна операция программы.
class Op:
	extends RefCounted
	var kind: Kind = Kind.NUM
	var value: int = 0
	var sides: int = 0
	var name: String = ""

	func _init(p_kind: Kind, p_value: int = 0, p_sides: int = 0, p_name: String = "") -> void:
		kind = p_kind
		value = p_value
		sides = p_sides
		name = p_name


## Разбирает текст. Ошибка — в поле [member error] (тогда is_valid() == false).
static func parse(source: String) -> Formula:
	var f := Formula.new()
	f.text = source
	if source.length() > MAX_LENGTH:
		f.error = "too long"
		return f
	var parser := _Parser.new(source)
	f._ops = parser.run()
	f.error = parser.error
	if f.error != "":
		f._ops.clear()
	return f


## Формула-константа.
static func constant(value: int) -> Formula:
	return parse(str(value))


func is_valid() -> bool:
	return error == "" and not _ops.is_empty()


## Есть ли в формуле кости.
func has_dice() -> bool:
	for op in _ops:
		if op.kind == Kind.DICE:
			return true
	return false


## Вычисляет формулу. При [param critical] число костей удваивается.
## Каждый выпавший результат кости добавляется в [param rolls] — для лога и реплеев.
func roll(
	rng: Rng, vars: Dictionary[String, int] = {}, critical: bool = false, rolls: Array[int] = []
) -> int:
	var stack: Array[int] = []
	for op in _ops:
		match op.kind:
			Kind.NUM:
				stack.append(op.value)
			Kind.VAR:
				var value: int = vars.get(op.name, 0)
				stack.append(value)
			Kind.DICE:
				var count := op.value * 2 if critical else op.value
				var sum := 0
				for i in count:
					var r := rng.roll(op.sides)
					rolls.append(r)
					sum += r
				stack.append(sum)
			Kind.NEG:
				var top: int = stack.pop_back()
				stack.append(-top)
			_:
				var b: int = stack.pop_back()
				var a: int = stack.pop_back()
				stack.append(_binary(op.kind, a, b))
	return stack[0] if stack.size() == 1 else 0


## Наименьшее и наибольшее возможное значение [min, max] — для предпросмотра.
func value_range(vars: Dictionary[String, int] = {}, critical: bool = false) -> Vector2i:
	var stack: Array[Vector2i] = []
	for op in _ops:
		match op.kind:
			Kind.NUM:
				stack.append(Vector2i(op.value, op.value))
			Kind.VAR:
				var v: int = vars.get(op.name, 0)
				stack.append(Vector2i(v, v))
			Kind.DICE:
				var count := op.value * 2 if critical else op.value
				stack.append(Vector2i(count, count * op.sides))
			Kind.NEG:
				var x: Vector2i = stack.pop_back()
				stack.append(Vector2i(-x.y, -x.x))
			_:
				var b: Vector2i = stack.pop_back()
				var a: Vector2i = stack.pop_back()
				stack.append(_binary_range(op.kind, a, b))
	return stack[0] if stack.size() == 1 else Vector2i.ZERO


func _binary(kind: Kind, a: int, b: int) -> int:
	var result := 0
	match kind:
		Kind.ADD:
			result = a + b
		Kind.SUB:
			result = a - b
		Kind.MUL:
			result = a * b
		Kind.DIV:
			result = 0 if b == 0 else IntMath.floor_div(a, b)
		Kind.MIN:
			result = mini(a, b)
		Kind.MAX:
			result = maxi(a, b)
	return result


func _binary_range(kind: Kind, a: Vector2i, b: Vector2i) -> Vector2i:
	match kind:
		Kind.ADD:
			return Vector2i(a.x + b.x, a.y + b.y)
		Kind.SUB:
			return Vector2i(a.x - b.y, a.y - b.x)
		Kind.MIN:
			return Vector2i(mini(a.x, b.x), mini(a.y, b.y))
		Kind.MAX:
			return Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	# Умножение и деление монотонны по каждому аргументу при фиксированном знаке:
	# крайние значения достигаются в углах интервалов.
	var corners: Array[int] = []
	for x: int in [a.x, a.y]:
		for y: int in [b.x, b.y]:
			corners.append(_binary(kind, x, y))
	if kind == Kind.DIV and b.x <= 0 and b.y >= 0:
		corners.append(0)
	var lo: int = corners.min()
	var hi: int = corners.max()
	return Vector2i(lo, hi)


## Рекурсивный спуск: expr := term (('+'|'-') term)*;
## term := unary (('*'|'/') unary)*; unary := '-' unary | atom;
## atom := NUM | DICE | VAR | ('min'|'max') '(' expr ',' expr ')' | '(' expr ')'.
class _Parser:
	extends RefCounted
	var error: String = ""
	var _tokens: PackedStringArray = []
	var _pos: int = 0
	var _out: Array[Op] = []

	func _init(source: String) -> void:
		var re := RegEx.create_from_string("\\s*(\\d*d\\d+|\\d+|[A-Za-z_]+|[-+*/(),])")
		var at := 0
		var stripped := source.strip_edges()
		while at < stripped.length():
			var m := re.search(stripped, at)
			if m == null or m.get_start() != at:
				error = "unexpected character at %d" % at
				return
			_tokens.append(m.get_string(1))
			at = m.get_end()
			while at < stripped.length() and stripped[at] == " ":
				at += 1

	func run() -> Array[Op]:
		if error != "":
			return []
		if _tokens.is_empty():
			error = "empty"
			return []
		_expr()
		if error == "" and _pos < _tokens.size():
			error = "unexpected '%s'" % _tokens[_pos]
		return _out

	func _peek() -> String:
		return _tokens[_pos] if _pos < _tokens.size() else ""

	func _take(expected: String) -> bool:
		if _peek() != expected:
			if error == "":
				error = "expected '%s'" % expected
			return false
		_pos += 1
		return true

	func _expr() -> void:
		_term()
		while error == "" and (_peek() == "+" or _peek() == "-"):
			var op := _peek()
			_pos += 1
			_term()
			_out.append(Op.new(Kind.ADD if op == "+" else Kind.SUB))

	func _term() -> void:
		_unary()
		while error == "" and (_peek() == "*" or _peek() == "/"):
			var op := _peek()
			_pos += 1
			_unary()
			_out.append(Op.new(Kind.MUL if op == "*" else Kind.DIV))

	func _unary() -> void:
		if _peek() == "-":
			_pos += 1
			_unary()
			_out.append(Op.new(Kind.NEG))
			return
		_atom()

	func _atom() -> void:
		if error != "":
			return
		var tok := _peek()
		if tok == "":
			error = "unexpected end"
			return
		_pos += 1
		if tok == "(":
			_expr()
			_take(")")
		elif tok.is_valid_int():
			_out.append(Op.new(Kind.NUM, tok.to_int()))
		elif tok.contains("d") and tok.replace("d", "").is_valid_int():
			var parts := tok.split("d")
			var count := 1 if parts[0] == "" else parts[0].to_int()
			var sides := parts[1].to_int()
			if count < 1 or count > MAX_DICE or sides < 1 or sides > MAX_SIDES:
				error = "bad dice '%s'" % tok
				return
			_out.append(Op.new(Kind.DICE, count, sides))
		elif tok == "min" or tok == "max":
			if not _take("("):
				return
			_expr()
			if not _take(","):
				return
			_expr()
			if not _take(")"):
				return
			_out.append(Op.new(Kind.MIN if tok == "min" else Kind.MAX))
		elif VARIABLES.has(tok):
			_out.append(Op.new(Kind.VAR, 0, 0, tok))
		else:
			error = "unknown token '%s'" % tok
