class_name ReactionLog
extends RefCounted
## Реакции персонажей игрока во время применения одной команды (ADR-0023):
## ответы из команды по порядку и возникшие вопросы. Не сохраняется.

var answers: Array[bool] = []
var prompts: Array[ReactionPrompt] = []

var _cursor: int = 0


## Начало применения команды: ответы игрока, вопросы — с чистого листа.
func begin(p_answers: Array[bool]) -> void:
	answers = p_answers.duplicate()
	prompts.clear()
	_cursor = 0


## Срабатывает ли реакция [param reactor]. Участники ИИ реагируют всегда;
## персонаж игрока — по очередному ответу из команды, без ответа — реагирует.
func decide(reactor: Combatant, kind: String, target_id: String, source_id: String) -> bool:
	if not reactor.player:
		return true
	var prompt := ReactionPrompt.new(reactor.id, kind, target_id, source_id)
	if _cursor < answers.size():
		prompt.answered = true
		prompt.accepted = answers[_cursor]
	_cursor += 1
	prompts.append(prompt)
	return prompt.accepted


## Первый вопрос без ответа в команде или null.
func first_unanswered() -> ReactionPrompt:
	for p in prompts:
		if not p.answered:
			return p
	return null
