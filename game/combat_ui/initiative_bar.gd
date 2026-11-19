class_name InitiativeBar
extends HFlowContainer
## Порядок хода: участники по инициативе, текущий подсвечен, павшие притушены.

const TEAM_TINT: Dictionary[String, Color] = {
	"party": Color(0.55, 0.7, 1.0),
}
const ENEMY_TINT := Color(1.0, 0.65, 0.6)


func refresh(state: CombatState) -> void:
	for child in get_children():
		child.queue_free()
	var current := state.current()
	for id in state.order:
		var c := state.get_combatant(id)
		if c == null:
			continue
		var panel := PanelContainer.new()
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text = "%s\n%d/%d" % [CombatLogFormat.display_name(c), c.hp, c.max_hp]
		label.add_theme_font_size_override("font_size", 13)
		var tint: Color = TEAM_TINT.get(c.team, ENEMY_TINT)
		label.modulate = tint
		if c.dead:
			label.modulate = Color(0.5, 0.5, 0.5, 0.6)
		elif c.hp == 0:
			label.modulate = Color(0.9, 0.4, 0.4, 0.8)
		if c == current and not state.ended:
			label.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
			label.text = "▶ " + label.text
		panel.add_child(label)
		add_child(panel)
