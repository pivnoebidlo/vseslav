class_name Money
extends RefCounted
## Деньги в целых кунах; гривна кун = 25 кун (XI век, docs/rules/items.md).

const KUNY_PER_GRIVNA := 25


static func grivny(kuny: int) -> int:
	return IntMath.floor_div(maxi(kuny, 0), KUNY_PER_GRIVNA)


static func remainder_kuny(kuny: int) -> int:
	return maxi(kuny, 0) - grivny(kuny) * KUNY_PER_GRIVNA
