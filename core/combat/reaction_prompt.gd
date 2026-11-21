class_name ReactionPrompt
extends RefCounted
## Повод для реакции персонажа игрока, возникший при применении команды (ADR-0023).

const OPPORTUNITY := "opportunity"
const PROTECTION := "protection"

var reactor: String = ""
## OPPORTUNITY — ударить вдогонку [member target]; PROTECTION — прикрыть [member target]
## от атаки [member source].
var kind: String = ""
var target: String = ""
var source: String = ""
## Ответ взят из команды; false — ответа не было, сработало правило по умолчанию.
var answered: bool = false
var accepted: bool = true


func _init(
	p_reactor: String = "", p_kind: String = "", p_target: String = "", p_source: String = ""
) -> void:
	reactor = p_reactor
	kind = p_kind
	target = p_target
	source = p_source
