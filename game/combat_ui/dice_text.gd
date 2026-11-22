class_name DiceText
extends RefCounted
## Подписи под кубиком: «13 + 2 = 15 против СЛ 15 — успех».


static func modifier(mod: int) -> String:
	return "+ %d" % mod if mod >= 0 else "− %d" % -mod


static func vs_dc(r: CheckResult) -> String:
	var outcome := "UI_DICE_SUCCESS" if r.success else "UI_DICE_FAIL"
	return (
		TranslationServer
		. translate("UI_DICE_VS_DC")
		. format(
			{
				"natural": r.natural,
				"mod": modifier(r.modifier),
				"total": r.total,
				"dc": r.dc,
				"outcome": TranslationServer.translate(outcome),
			}
		)
	)
