extends GutTest
## Реакции персонажей игрока: ответы в команде, вопросы, правило по умолчанию (ADR-0023).


func _flee_setup(player: bool) -> CombatState:
	var a := MiniCombat.unit("a", "x", Vector2i(1, 0))
	var guard := MiniCombat.unit("guard", "y", Vector2i(2, 0))
	guard.player = player
	guard.actions = [MiniCombat.melee("bite", "4")]
	return MiniCombat.make([a, guard], ["a", "guard"], [".....", "....."])


func test_player_declines_opportunity_attack() -> void:
	var s := _flee_setup(true)
	var cmd := MoveCommand.new("a", Vector2i(0, 0))
	cmd.reactions = [false]
	var events := cmd.apply(s)
	assert_eq(MiniCombat.events_of(events, CombatEvent.REACTION).size(), 0)
	assert_eq(MiniCombat.events_of(events, CombatEvent.MOVED).size(), 1, "movement not split")
	assert_eq(s.get_combatant("a").hp, 20)
	assert_true(s.get_combatant("guard").reaction_ready, "reaction kept for later")
	assert_eq(s.reactions.prompts.size(), 1)
	assert_true(s.reactions.prompts[0].answered)
	assert_null(s.reactions.first_unanswered())


func test_unanswered_prompt_defaults_to_reacting() -> void:
	var s := _flee_setup(true)
	MiniCombat.rolls(s, [15])
	var events := MoveCommand.new("a", Vector2i(0, 0)).apply(s)
	assert_eq(MiniCombat.events_of(events, CombatEvent.REACTION).size(), 1)
	var prompt := s.reactions.first_unanswered()
	assert_not_null(prompt)
	assert_eq(prompt.reactor, "guard")
	assert_eq(prompt.kind, ReactionPrompt.OPPORTUNITY)
	assert_eq(prompt.target, "a")


func test_ai_reactors_are_never_asked() -> void:
	var s := _flee_setup(false)
	MiniCombat.rolls(s, [15])
	var cmd := MoveCommand.new("a", Vector2i(0, 0))
	cmd.reactions = [false]
	var events := cmd.apply(s)
	assert_eq(MiniCombat.events_of(events, CombatEvent.REACTION).size(), 1)
	assert_eq(s.reactions.prompts.size(), 0)


func test_player_declines_protection() -> void:
	var a := MiniCombat.unit("a", "x", Vector2i(1, 1))
	a.actions = [MiniCombat.melee()]
	var b := MiniCombat.unit("b", "y", Vector2i(2, 1), 20, 15)
	var guard := MiniCombat.unit("guard", "y", Vector2i(3, 1))
	guard.player = true
	guard.has_shield = true
	guard.traits = [MiniCombat.trait_def({"type": "protection"})]
	var s := MiniCombat.make([a, b, guard], ["a", "b", "guard"])
	MiniCombat.rolls(s, [15, 3])
	var cmd := UseActionCommand.new("a", "hit", "b")
	cmd.reactions = [false]
	var events := cmd.apply(s)
	assert_eq(MiniCombat.events_of(events, CombatEvent.REACTION).size(), 0)
	assert_true(guard.reaction_ready)
	var attack := MiniCombat.events_of(events, CombatEvent.ATTACK)[0]
	var rolls: Array = attack.data["rolls"]
	assert_eq(rolls, [15], "no disadvantage without protection")
	assert_true(JsonRead.get_bool(attack.data, "hit"))
	assert_eq(s.reactions.prompts[0].kind, ReactionPrompt.PROTECTION)
	assert_eq(s.reactions.prompts[0].source, "a")


func test_dry_run_on_copy_then_apply_matches() -> void:
	# Как делает интерфейс: прогон на копии, ответ, затем настоящее применение.
	var s := _flee_setup(true)
	MiniCombat.rolls(s, [15])
	var cmd := MoveCommand.new("a", Vector2i(0, 0))
	var probe := CombatState.from_dict(s.to_dict(), s.grid)
	probe.rng = StubRng.new([15])
	cmd.apply(probe)
	assert_not_null(probe.reactions.first_unanswered())
	assert_eq(s.get_combatant("a").column, Vector2i(1, 0), "real state untouched")
	cmd.reactions.append(false)
	cmd.apply(s)
	assert_eq(s.get_combatant("a").column, Vector2i(0, 0))
	assert_eq(s.get_combatant("a").hp, 20)


func test_reactions_survive_serialization() -> void:
	var cmd := MoveCommand.new("a", Vector2i(3, 2))
	assert_false(cmd.to_dict().has("reactions"), "old records stay the same")
	cmd.reactions = [true, false]
	var back := CombatCommand.from_dict(cmd.to_dict())
	assert_eq(back.reactions, [true, false] as Array[bool])
	var act := UseActionCommand.new("a", "hit", "b")
	act.reactions = [false]
	assert_eq(CombatCommand.from_dict(act.to_dict()).reactions, [false] as Array[bool])
