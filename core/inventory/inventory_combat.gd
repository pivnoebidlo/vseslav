class_name InventoryCombat
extends RefCounted
## Операции с инвентарём в бою (ADR-0024). Данные правил не нужны: свойства
## предмета (двуручное) берутся из действия.


## Можно ли взять оружие с пояса в основную руку.
static func can_draw(inv: Inventory, item_id: String, two_handed: bool) -> String:
	if inv.in_hands(item_id):
		return ""
	if inv.belt_count(item_id) <= 0:
		return Inventory.ERR_NOT_HERE
	if two_handed and inv.off_hand != "":
		return Inventory.ERR_HANDS_BUSY
	return ""


## Берёт оружие с пояса в основную руку; прежнее — на пояс, а если там нет места —
## в мешок. Возвращает, куда ушло прежнее: "belt", "bag" или "" (рука была пуста).
## Вызывать после успешного [method can_draw].
static func draw(inv: Inventory, item_id: String) -> String:
	if inv.in_hands(item_id):
		return ""
	ItemStack.take_from(inv.belt, item_id, 1)
	var previous := inv.main_hand
	inv.main_hand = item_id
	if previous == "":
		return ""
	if inv.belt_has_room(previous):
		ItemStack.add_to(inv.belt, previous, 1)
		return "belt"
	ItemStack.add_to(inv.bag, previous, 1)
	return "bag"


## Убирает оружие из основной руки на пояс.
static func stow(inv: Inventory) -> String:
	if inv.main_hand == "":
		return Inventory.ERR_NOT_HERE
	if not inv.belt_has_room(inv.main_hand):
		return Inventory.ERR_BELT_FULL
	ItemStack.add_to(inv.belt, inv.main_hand, 1)
	inv.main_hand = ""
	return ""


## Достаёт стопку из мешка на пояс (в бою — действием).
static func fetch(inv: Inventory, item_id: String) -> String:
	if inv.bag_count(item_id) <= 0:
		return Inventory.ERR_NOT_HERE
	if not inv.belt_has_room(item_id):
		return Inventory.ERR_BELT_FULL
	var n := inv.bag_count(item_id)
	ItemStack.take_from(inv.bag, item_id, n)
	ItemStack.add_to(inv.belt, item_id, n)
	return ""


## Тратит один предмет: сначала из рук (брошенная сулица), затем с пояса.
static func spend(inv: Inventory, item_id: String) -> void:
	if inv.main_hand == item_id:
		inv.main_hand = ""
	elif inv.off_hand == item_id:
		inv.off_hand = ""
	else:
		ItemStack.take_from(inv.belt, item_id, 1)
