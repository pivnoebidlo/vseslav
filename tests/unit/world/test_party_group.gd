extends GutTest
## Выбор героя и сцепка в исследовании (ADR-0030).


func _group() -> PartyGroup:
	return PartyGroup.new(["lovchiy", "ratnik", "volkhv"] as Array[String])


func test_everyone_starts_chained_first_selected() -> void:
	var g := _group()
	assert_eq(g.selected, "lovchiy")
	assert_eq(g.followers(), ["ratnik", "volkhv"] as Array[String])
	assert_eq(g.movers(), ["lovchiy", "ratnik", "volkhv"] as Array[String])


func test_selecting_another_hero_leads_the_chain() -> void:
	var g := _group()
	g.select("volkhv")
	assert_eq(g.followers(), ["lovchiy", "ratnik"] as Array[String])
	g.select("nobody")
	assert_eq(g.selected, "volkhv", "unknown id ignored")


func test_unchained_hero_stays_behind() -> void:
	var g := _group()
	g.toggle_chain("ratnik")
	assert_false(g.is_chained("ratnik"))
	assert_eq(g.followers(), ["volkhv"] as Array[String])


func test_selected_unchained_hero_walks_alone() -> void:
	var g := _group()
	g.toggle_chain("ratnik")
	g.select("ratnik")
	assert_eq(g.movers(), ["ratnik"] as Array[String])
	g.toggle_chain("ratnik")
	assert_eq(g.followers(), ["lovchiy", "volkhv"] as Array[String], "re-chained leads again")


func test_next_cycles_through_party() -> void:
	var g := _group()
	assert_eq(g.next_id(), "ratnik")
	g.select("volkhv")
	assert_eq(g.next_id(), "lovchiy")
	assert_eq(PartyGroup.new().next_id(), "")
