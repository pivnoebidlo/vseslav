# Сборка под Android: разовая памятка

Android не входит в цели проекта ([SPEC](SPEC.md), таблица «Цель и рамки», строка «Не цель»). Мобильный интерфейс не адаптирован: шрифты, кнопки и элементы управления рассчитаны на десктоп и на телефоне слишком мелкие. Эта памятка описывает только техническую сборку APK для проверки. Она не делает проект мобильным и не требует правок в коде или настройках игры.

Проверено: debug-APK собирается, устанавливается и запускается. Для обычной сборки достаточно готового Android-шаблона Godot; Gradle-сборка и Android Build Template не нужны. Менять `project.godot` тоже не нужно: на Android используется mobile-ветка рендерера, а сжатие текстур ETC2/ASTC в проекте уже включено.

## Что должно быть установлено

| Компонент | Требование |
|---|---|
| Godot | Версия из [ADR-0015](adr/0015-toolchain-versions.md) и Android export templates той же версии |
| JDK | **17 или новее** — минимальная официально поддерживаемая версия. Более старые не гарантируются; системная Java по умолчанию может быть любой, важен путь в настройках Godot |
| Android SDK | `platform-tools` (нужен `adb`) и `build-tools` (нужен `apksigner`) |
| Debug-keystore | Godot создаёт сам; можно указать существующий |
| `adb` | Для установки APK на устройство или эмулятор |

Для сборки **готового APK** (способ ниже) не нужны Android SDK Platform, NDK и Gradle. Они понадобятся только если включать `Use Gradle Build` и собирать проект через Android Build Template.

Не используй Android SDK из репозитория дистрибутива: там обычно неполный набор пакетов и старые версии. Лучше поставить SDK через Android Studio или официальные `cmdline-tools`.

## 1. Установить JDK

Нужен JDK 17 или новее. Проверка:

```sh
java -version
```

Godot не обязан использовать системную Java. В настройках редактора указывается отдельный путь к JDK — именно его Godot передаёт в `JAVA_HOME` и `PATH` при экспорте.

## 2. Установить Android SDK

Через Android Studio: **SDK Manager** → установить:

- **Android SDK Platform-Tools**;
- **Android SDK Build-Tools** (версия должна содержать `apksigner`; желательно та, что соответствует target SDK проекта).

Через `cmdline-tools`:

```sh
# sdkmanager тоже запускается с JDK 17+, даже если java по умолчанию старая
JAVA_HOME=/путь/к/jdk sdkmanager --licenses
JAVA_HOME=/путь/к/jdk sdkmanager "platform-tools" "build-tools;<версия>"
```

Версию Build-Tools выбери из `sdkmanager --list` по target SDK, который использует текущая версия Godot. Если точной версии нет, Godot попробует найти совместимую.

После установки проверь, что существуют:

```text
<ANDROID_SDK>/platform-tools/adb
<ANDROID_SDK>/build-tools/<версия>/apksigner
```

## 3. Настроить Godot

1. Установи Android export templates: **Editor → Manage Export Templates**. Нужны `android_debug.apk` и `android_release.apk` той же версии, что и Godot.
2. Открой **Editor → Editor Settings → Export → Android** и укажи:
   - **Android SDK Path** — папка установленного Android SDK (внутри неё должны быть `platform-tools` и `build-tools`);
   - **Java SDK Path** — папка JDK 17+;
   - **Debug Keystore** — путь к debug-keystore. Godot может создать его сам.

Если Godot уже запущен с неправильными путями, после изменения настроек лучше перезапустить редактор.

## 4. Создать Android export preset

**Project → Export → Add… → Android** и заполнить:

- **Export Path**: `build/android/Vseslav.apk`;
- **Package → Unique Name**: `org.vseslav.game`;
- **Package → Name**: `Всеслав Чародей`;
- **Version → Code**: `1`;
- **Version → Name**: `0.0.1`;
- **Architectures → Arm64-v8a**: включить;
- **Architectures → X86_64**: включить, если нужен эмулятор;
- **Gradle Build → Use Gradle Build**: **выключить** — будет использован готовый Android-шаблон.

Остальные параметры можно оставить по умолчанию. Пресет сохраняется в `export_presets.cfg`; это локальная настройка, её не обязательно коммитить.

## 5. Собрать APK

```sh
godot --headless --import
mkdir -p build/android
godot --headless --export-debug "Android" build/android/Vseslav.apk
```

В редакторе то же самое: **Project → Export → Export Project**.

Debug-сборка подписывается debug-keystore автоматически. Для release-сборки нужно указать release-keystore в пресете и выполнить:

```sh
godot --headless --export-release "Android" build/android/Vseslav.apk
```

## 6. Установить на устройство

```sh
adb install -r build/android/Vseslav.apk
```

`adb` берётся из `platform-tools`. На телефоне должна быть включена отладка по USB; APK можно также просто скопировать на устройство и открыть.

## Если всё-таки нужна Gradle-сборка

Обычная сборка игры этого не требует. Gradle нужен только для изменения Android-шаблона, подключения плагинов или собственной сборки движка.

В этом случае дополнительно:

1. Установи Android SDK Platform и NDK. Их версии должны совпадать с требованиями установленного шаблона Godot — смотри `android/build/config.gradle` после установки шаблона.
2. Установи шаблон: **Project → Install Android Build Template**.
3. Включи в пресете **Gradle Build → Use Gradle Build**.
4. Для ручного запуска Gradle укажи SDK, например через `android/build/local.properties`:

   ```properties
   sdk.dir=/путь/к/android/sdk
   ```

   и запускай Gradle с JDK 17+.

Не используй `./gradlew build` в `android/build` как замену экспорту игры: это промежуточный Gradle-проект, в него не попадает PCK с игрой. Правильный путь и в этом случае — экспорт через Godot.

## Частые ошибки

| Ошибка | Причина и решение |
|---|---|
| `SDK location not found` | Запущен ручной `gradlew` без `ANDROID_HOME`/`local.properties`. Для обычной сборки Gradle не нужен — экспортируй через Godot |
| `Invalid export preset name: Android` | Пресет не создан, не сохранён или у него пустой `Export Path` |
| `Unable to find ... apksigner` | Не установлены Build-Tools или неверен `Android SDK Path` |
| `A valid Java SDK path is required` | В настройках указан JDK 8/11 или неверный путь; нужен JDK 17+ |
| APK не подписан | Не найден `apksigner` или он не запускается с указанным JDK |
| Текст и кнопки слишком мелкие | Ожидаемо: мобильный интерфейс не адаптирован, это не ошибка сборки |

## Что не коммитить

- `android/` — сгенерированный Android Build Template (нужен только для Gradle-сборки);
- `build/android/` — результат сборки;
- изменения `export_presets.cfg`, если Android-пресет не должен попасть в репозиторий.

После разовой сборки проект можно вернуть в состояние HEAD:

```sh
git restore export_presets.cfg
rm -rf android/
```

`build/` уже исключён в `.gitignore`; готовый APK можно оставить локально для проверки.
