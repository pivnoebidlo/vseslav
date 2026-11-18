class_name ModelLimits
extends RefCounted
## Лимиты для моделей из модулей и от пользователей (SPEC §11).
## Значения по умолчанию — стартовые, уточняются по мере появления реальных моделей.

var max_file_bytes: int = 32 * 1024 * 1024
var max_triangles: int = 50_000
var max_texture_side: int = 2048
var max_skeletons: int = 1
var max_bones: int = 100
