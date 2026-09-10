# Сборка AppleALC без Xcode

Файлы раскладок AppleALC компилируются внутрь кекста, поэтому любое изменение графа DSP — например
[добавление настоящего эквалайзера в цепочку динамиков](woofers.md#эквалайзер-внутри-драйвера) — требует
пересборки. Во всех руководствах написано, что для этого нужен Xcode.

Не нужен. **Достаточно Command Line Tools**, и здесь это важно: версия Xcode из App Store требует macOS
новее Sequoia, а с портала разработчика это 8 ГБ и аккаунт с доступом. Вся сборка занимает около минуты.

Скрипт — [`tools/applealc-speaker-eq/build.sh`](../../tools/applealc-speaker-eq/build.sh). Здесь описано,
что он делает, и — что полезнее — четыре вещи, которые ломаются.

## Что нужно

```bash
xcode-select --install
```

Три исходника, все публичные:

| | |
|---|---|
| [AppleALC](https://github.com/acidanthera/AppleALC) | сам плагин; здесь собран на `a822e7c` (1.9.7) |
| [Lilu](https://github.com/acidanthera/Lilu) | 1.7.2 — её заголовки **и** `Library/plugin_start.cpp` |
| [MacKernelSDK](https://github.com/acidanthera/MacKernelSDK) | заголовки ядра и `libkmod.a` |

KDK не нужен. KDK требуется только для пересборки *коллекций ядра*, а мы этого не делаем.

## Четыре ловушки

Каждая даёт сборку, которая выглядит нормальной.

### 1. `-DHAVE_ANALOG_AUDIO` — иначе данные раскладок молча исчезают

Все данные кодеков в AppleALC спрятаны за этим `#ifdef`. Без него `kern_resources.cpp` компилируется без
единого предупреждения в **15 КБ вместо 1,88 МБ**, а получившийся кекст загружается, работает и не делает
ничего.

Проверка — размер одного объектного файла:

```
kern_resources.o    1879464 bayt      <- верно
kern_resources.o      15xxx bayt      <- определение забыто
```

### 2. `-DPRODUCT_NAME=AppleALC` — иначе все символы названы неправильно

Макрос `ADDPR()` из Lilu подставляет имя продукта в каждый экспортируемый символ. Без определения получится
`_PRODUCT_NAME_kextList` вместо `_AppleALC_kextList`, и линковка провалится так, будто не хватает исходников.
`-DMODULE_VERSION=1.9.7` нужен по той же причине — Lilu превращает его в строку.

Ещё легко пропустить: **`Lilu/Library/plugin_start.cpp` нужно компилировать в свой кекст.** Это файл в дереве
Lilu, который включает в себя каждый плагин, а не часть двоичного файла самой Lilu.

### 3. `ResourceConverter` надо собрать заранее

`ResourceConverter/generate.sh` — это то, что превращает `Resources/**/*.xml` в
`AppleALC/kern_resources.cpp`. Xcode запускает его как этап сборки, и он ожидает две переменные, которые
выставил бы Xcode:

```bash
PROJECT_DIR="$PWD"          # корень репозитория
TARGET_BUILD_DIR="$RC"      # папка с собранным ResourceConverter
```

`ResourceConverter` — отдельная вспомогательная цель на Objective-C++, файл `ResourceConverter/main.mm`,
которую вы собираете сами:

```bash
clang++ -o "$RC/ResourceConverter" ResourceConverter/main.mm -framework Foundation -std=c++17 -O2
```

Пропустить это хуже, чем получить ошибку, потому что **`generate.sh` удаляет `kern_resources.cpp` перед
вызовом конвертера.** Запуск без `TARGET_BUILD_DIR` оставляет вас вообще без файла ресурсов — а поскольку
`kern_resources.cpp` внесён в `.gitignore`, `git status` ничего плохого не покажет. Здесь именно так и
вышло. Повторный запуск с собранным конвертером всё восстанавливает.

`generate.sh` ещё и кеширует по MD5 (`Resources.md5`, `*.xml.md5`) и печатает `Trusting existing
kern_resources.cpp`, когда ничего не менялось. Это нормально, а не сбой.

### 4. `kmod_info` — та, что стоит одной перезагрузки

Вот это самое интересное. Линковка проходит, `file` показывает корректный `Mach-O 64-bit kext bundle
x86_64`, все символы плагина определены, все неразрешённые символы есть в ядре — и ядро не загружает
ничего. Ни паники, ни строчки в журнале, ни одного звукового устройства в системе.
`kmutil showloaded | grep AppleALC` просто пустой.

`kmod_info` — структура, по которой ядро находит точки входа кекста. Файл, который её определяет, генерирует
Xcode из настроек сборки `MODULE_NAME`, `MODULE_START` и `MODULE_STOP`. В репозитории такого файла нет,
поэтому у сборки руками нет `kmod_info`, а кекст без неё отвергается молча.

`libkmod.a` тут не спасает: в архиве лежат `c_start.o` и `c_stop.o`, которые **ссылаются** на `_kmod_info`,
но не определяют её. А так как в ваших собственных объектниках на неё тоже никто не ссылается, линкер вообще
не втягивает эти члены архива.

**Диагноз в одну строку**, который занимает секунду и сэкономил бы перезагрузку:

```bash
nm your-AppleALC | grep _kmod_info
```

```
00000000001ab5f0 D _kmod_info       <- штатный AppleALC
                                    <- наш: ничего
```

Лечение — [`tools/applealc-speaker-eq/kmod_glue.c`](../../tools/applealc-speaker-eq/kmod_glue.c), ровно то,
что сгенерировал бы Xcode:

```c
#include <mach/mach_types.h>

extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
extern kern_return_t AppleALC_kern_start(kmod_info_t *ki, void *data);
extern kern_return_t AppleALC_kern_stop(kmod_info_t *ki, void *data);

__attribute__((visibility("default")))
KMOD_EXPLICIT_DECL(as.vit9696.AppleALC, "1.9.7", _start, _stop)

__private_extern__ kmod_start_func_t *_realmain = AppleALC_kern_start;
__private_extern__ kmod_stop_func_t  *_antimain = AppleALC_kern_stop;
```

Сойтись должны три вещи. Первый аргумент макроса обязан совпадать с `CFBundleIdentifier`, второй — с
`CFBundleVersion` из `Info.plist` кекста. `_realmain` / `_antimain` — это то, что вызывают `c_start.o` и
`c_stop.o`, и они указывают на точки входа плагина Lilu, чьи имена берутся из `MODULE_START` / `MODULE_STOP`
в проекте Xcode (`$(PRODUCT_NAME)_kern_start`). А ссылка на `_start` / `_stop` — это ещё и то, что наконец
заставляет линкер втянуть `libkmod.a`.

Структуру можно вычитать из готового бинарника — имя занимает 64 байта по смещению 16, версия — следующие
64 — и оба поля должны совпадать с бандлом:

```
AppleALC (наш)      name='as.vit9696.AppleALC' version='1.9.7'
AppleALC (штатный)  name='as.vit9696.AppleALC' version='1.9.7'
```

`build.sh` проверяет наличие символа и отказывается завершаться без него.

## Как проверить до перезагрузки

Полностью проверить линковку кекста на штатной macOS нельзя. `kextutil` в Sequoia — заглушка над `kmutil`:

```
kextutil: -n is not a supported kmutil mode
```

а `kmutil create` отказывается без KDK под вашу сборку:

```
Missing Developer Kit: As of macOS 13.0, you will need to install a KDK matching
your build 24G830 to rebuild kernel collections.
```

Что **можно** сделать — и что поймало настоящую причину — это сравнить свой бинарник со штатным по
структуре:

```bash
N=out/AppleALC
S=/Volumes/EFI/EFI/OC/Kexts/AppleALC.kext/Contents/MacOS/AppleALC

otool -hv "$N" | tail -1                  # должно быть KEXTBUNDLE ... NOUNDEFS
nm "$N" | grep _kmod_info                 # должен быть  (ловушка 4)
nm -u "$N" | sort -u > /tmp/n
nm -u "$S" | sort -u > /tmp/s
comm -23 /tmp/n /tmp/s                    # символы, нужные вам, но не штатному
```

Всё из последнего списка обязано существовать в ядре, и это проверяется напрямую:

```bash
nm /System/Library/Kernels/kernel | awk '{print $NF}' | sort -u > /tmp/k
grep -qx '__ZN9IOService4initEP12OSDictionary' /tmp/k && echo present
```

Нашей сборке понадобилось семь символов, которых нет у штатной, — слоты базовых классов IOKit и диспетчер
`IORPC`, все в ядре присутствуют. Она же экспортирует на 49 символов больше штатной, потому что отличаются
флаги видимости; это безвредно — все они с искажёнными именами `AlcEnabler` и ни с чем столкнуться не могут.

## Установка и откат

Меняется только двоичный файл. Остальное в бандле надо сохранить — в первую очередь `Info.plist`, где живёт
[конфигурация пина низкочастотников](woofers.md#а-конфигурация-пина-навсегда).

```bash
D=/Volumes/EFI/EFI/OC/Kexts/AppleALC.kext/Contents/MacOS
sudo cp "$D/AppleALC" "$D/AppleALC.stock"        # сначала копия, всегда
sudo cp out/AppleALC "$D/AppleALC"
sudo chmod 755 "$D/AppleALC"
```

Команду отката надо набрать **до** перезагрузки:

```bash
sudo cp "$D/AppleALC.stock" "$D/AppleALC"
```

Отказ выглядит как пропавший звук, а не как потерянная машина — этот кекст не критичен для загрузки. Если
вместе со звуком отвалится SSH, понадобится флешка восстановления, так что иметь её — разумная
предосторожность.

После загрузки:

```bash
kmutil showloaded | grep -i applealc
```

Штатную и свою сборку отличают по размеру загруженного образа (`0x1cd000` против `0x1de000` здесь) и по
размеру файла на EFI-разделе.

## Воспроизводимость

Сборка воспроизводима побайтово, кроме `LC_UUID`, который генерирует линкер: пересборка с нуля и сравнение с
установленным файлом дали **16 различающихся байт**, ровно длину UUID. Если у вас расхождение больше —
значит что-то изменилось в генерации ресурсов.

## Про обновления

Мы подменяем файл внутри бандла кекста, поэтому обновление AppleALC его перезапишет. Держите `build.sh` и
патч, пересобирайте на новом теге и каждый раз перепроверяйте `nm | grep _kmod_info`.

## Это работает для любого плагина Lilu

Ничего из написанного не привязано к AppleALC, кроме имени продукта и определения `HAVE_ANALOG_AUDIO`. Те же
четыре ловушки — определения самого плагина, `plugin_start.cpp`, генерируемые ресурсы и `kmod_info` — это
всё, что стоит между Command Line Tools и любым плагином Lilu, собранным руками.
