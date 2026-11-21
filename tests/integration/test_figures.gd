extends GutTest
## Облик участников боя (ADR-0022): у каждого персонажа и существа базового модуля
## есть запись в models.json, модели грузятся, снаряжение и анимации ролей существуют.

const MODELS_DIR := "res://modules/base/models"
const ROLES: Array[String] = [
	"idle", "walk", "melee", "ranged", "hit", "downed", "downed_idle", "stand_up", "revive"
]

var _catalog: FigureCatalog


func before_all() -> void:
	_catalog = FigureCatalog.load_dir(MODELS_DIR, RigProfile.load_all())


func test_catalog_loads_without_errors() -> void:
	assert_eq(_catalog.errors, [] as Array[String])
	assert_gt(_catalog.entries.size(), 0)


func test_every_character_and_creature_has_a_figure() -> void:
	var db := CombatSim.rules()
	for id: String in db.characters:
		assert_not_null(_catalog.entry(id), "figure for character %s" % id)
	for id: String in db.creatures:
		assert_not_null(_catalog.entry(id), "figure for creature %s" % id)


func test_models_load_with_held_items_and_animations() -> void:
	for id: String in _catalog.entries:
		var e := _catalog.entry(id)
		if e.path == "":
			continue
		var model := _catalog.instantiate(e)
		assert_not_null(model, "%s loads" % id)
		if model == null:
			continue
		autofree(model.root)
		assert_not_null(model.rig, "%s rig recognised" % id)
		var shown: Array[String] = []
		for slot_name in model.rig.attachment_slots:
			for slot in model.root.find_children(slot_name, "", true, false):
				for child in slot.get_children():
					if (child as Node3D).visible:
						shown.append(str(child.name))
		shown.sort()
		var expected := e.hold.duplicate()
		expected.sort()
		assert_eq(shown, expected, "%s holds exactly what models.json says" % id)
		for role in ROLES:
			assert_ne(FigureCatalog.animation_for(e, model, role), "", "%s: role %s" % [id, role])
		for role: String in e.animations:
			var found := false
			for name in e.animations[role]:
				if model.animation_player.has_animation(name):
					found = true
			assert_true(found, "%s: override %s names a real animation" % [id, role])


func test_rejects_paths_outside_the_models_folder() -> void:
	var dir := "user://test_tmp/figures"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("models.json"), FileAccess.WRITE)
	f.store_string('{"figures": {"a": {"file": "../evil.glb"}, "b": {"figure": "beast"}}}')
	f.close()
	var c := FigureCatalog.load_dir(dir, RigProfile.load_all())
	assert_eq(c.errors.size(), 1)
	assert_null(c.entry("a"))
	assert_eq(c.entry("b").figure, FigureCatalog.FIGURE_BEAST)
	assert_null(c.instantiate(c.entry("b")))
