# Dell XPS 15 9500 — macOS Sequoia (OpenCore)

Рабочая конфигурация OpenCore для **Dell XPS 15 9500** (Comet Lake-H) под **macOS Sequoia 15.7.9**.

Главный результат: **сон работает.** Не «в целом работает», а по-настоящему: крышку закрыл — машина
записала образ и обесточилась, открыл — вернулась с той же сессией. На ноутбуке с Modern Standby, где в
прошивке вообще нет пути возврата из S3, это не очевидно, и путь к этому был длинным. Тупики, в которые
мы заходили, тоже описаны — чтобы вам их не проходить.

> 🇬🇧 English: **[README.md](README.md)** · документация в [`docs/`](docs/)

---

## Что работает

| Компонент | Состояние | Примечание |
|---|---|---|
| **Сон и пробуждение** | ✅ | Гибернация S4, пробуждение по открытию крышки — [подробно](docs/ru/sleep-hibernation.md) |
| Управление питанием CPU | ✅ | Работает `XCPM`, штатное изменение частот |
| Intel UHD 630 | ✅ | Полное ускорение, клавиши яркости, внешний монитор |
| NVIDIA GTX 1650 Ti | ⛔ Отключена | Драйвера под macOS не существует — обесточена ради батареи |
| Экран 1920×1200 | ✅ | |
| Внешний монитор (HDMI / USB-C) | ✅ | См. [графику](docs/ru/graphics-and-display.md) |
| Звук — динамики, наушники | ✅ | AppleALC `layout-id 13` |
| Звук — **низкочастотные динамики** | ✅ | В прошивке выключены — [как включили](docs/ru/woofers.md) |
| Звук — системный эквалайзер | ✅ | 32 полосы внутри драйвера — [как](docs/ru/building-applealc-without-xcode.md) |
| Звук — встроенный микрофон | ✅ | Нужна небольшая утилита, см. [звук](docs/ru/audio-keyboard-cardreader.md) |
| **Wi-Fi** | ✅ | Intel AX201 через `itlwm` + HeliPort |
| Wi-Fi — нативное меню macOS | ⛔ Недостижимо | Нужен root-патчинг OCLP — [почему](docs/ru/wifi-and-bluetooth.md) |
| **Bluetooth** | ✅ | Intel, включая наушники — [одна оговорка](docs/ru/wifi-and-bluetooth.md#bluetooth) |
| USB 3 / Type-C / Thunderbolt 3 | ✅ | Карта портов, предел в 15 портов соблюдён |
| Тачпад (I²C, жесты) | ✅ | VoodooI2C |
| Клавиатура, клавиши яркости и громкости | ✅ | VoodooPS2 |
| Картридер SD | ✅ | Sinetek-rtsx |
| Батарея, датчики, вентиляторы | ✅ | VirtualSMC + SMCDellSensors |
| Веб-камера | ✅ | |
| Сканер отпечатка | ⛔ Никогда | Драйвера нет и не предвидится |
| AirDrop / Handoff / Continuity | ⛔ Никогда | Нужно фирменное железо Apple |
| iCloud, App Store | ✅ | «Найти Mac» включать **не надо** — [почему](docs/ru/smbios.md#apple-id) |

---

## На каком железе собрано и проверено

| | |
|---|---|
| Модель | Dell XPS 15 9500 |
| Процессор | Intel Core i5-10300H (Comet Lake-H, 4 ядра / 8 потоков) |
| Встроенная графика | Intel UHD Graphics 630 — `0x3E9B`, platform-id `0x3E9B0009` |
| Дискретная графика | NVIDIA GeForce GTX 1650 Ti (отключена) |
| Память | 16 ГБ |
| Экран | 1920×1200 (FHD+), без сенсора |
| Накопитель | Samsung SSD 970 EVO Plus 1 ТБ (NVMe) |
| Wi-Fi / BT | Intel Wi-Fi 6 AX201 — `pci8086,6f0`, subsystem `1651` (CNVi) + Intel BT `8087:0026` |
| Звук | Intel Smart Sound (cAVS), AppleALC `layout-id 13` |
| Thunderbolt | Intel JHL7540 Titan Ridge |
| Батарея | DELL M59JH06 (BYD), проектная ёмкость 7394 мА·ч |

Если у вас 9500 с i7, экраном 4K OLED или другой картой Wi-Fi — большая часть применима, но сначала
прочитайте [графику](docs/ru/graphics-and-display.md) и [SMBIOS](docs/ru/smbios.md).

**Софт:** OpenCore `1.0.7` (REL-107-2025-11-19) · macOS Sequoia `15.7.9` (24G830) · SMBIOS `MacBookAir9,1`

---

## Быстрый старт

> Сначала прочитайте [SMBIOS](docs/ru/smbios.md). Этот EFI в неизменном виде не заработает — поля серийных
> номеров намеренно обнулены.

1. Скопируйте `EFI/` на EFI-раздел целевого диска.
2. Сгенерируйте собственные серийники и заполните `SystemSerialNumber`, `MLB`, `SystemUUID`, `ROM` —
   см. [SMBIOS](docs/ru/smbios.md). В `ROM` должен быть **реальный MAC** вашего сетевого адаптера.
3. Настройте BIOS по [этому списку](docs/ru/bios-settings.md).
4. Установите macOS, затем примените [настройки сна](docs/ru/sleep-hibernation.md) — это набор команд
   `pmset`, и сама macOS их **не** выставит.
5. По желанию — вспомогательные вещи из [`scripts/`](scripts/) и [`tools/`](tools/).

В загрузочных аргументах оставлены `-v keepsyms=1 debug=0x100` — подробная загрузка и внятный вывод при
панике. Это сделано намеренно, конфигурация так и разрабатывалась. Когда всё заработает, уберите их ради
обычной графической загрузки; `-igfxblt hbfx-ahbm=3 -btlfxallowanyaddr` оставьте — они функциональные.

### Чего здесь намеренно нет

`IOSkywalkFamily.kext`, `IO80211FamilyLegacy.kext` и `AirPortBrcmNIC.kext` — это **проприетарные двоичные
файлы Apple**, вынутые из старой macOS. Другие репозитории их выкладывают, этот — нет, потому что это
нарушение авторских прав. Нужны они только для нативного Wi-Fi, который
[всё равно не работает без root-патчинга OCLP](docs/ru/wifi-and-bluetooth.md#нативный-airportitlwm).
`AirportItlwm.kext` тоже не приложен — берите в
[релизах OpenIntelWireless](https://github.com/OpenIntelWireless/itlwm/releases).

---

## Документация

| | |
|---|---|
| [Сон и гибернация](docs/ru/sleep-hibernation.md) | **Начните отсюда.** Единственная по-настоящему трудная задача и её решение |
| [Wi-Fi и Bluetooth](docs/ru/wifi-and-bluetooth.md) | Почему `itlwm`, почему нативный AirportItlwm — тупик, особенности Bluetooth |
| [Графика и экран](docs/ru/graphics-and-display.md) | Патчи фреймбуфера, отключение дискретной карты, внешние мониторы |
| [Карта портов USB](docs/ru/usb-mapping.md) | Как устроена и как её строить |
| [Низкочастотные динамики](docs/ru/woofers.md) | Басовые динамики 9500 отключены в прошивке. Как их включить, с измерениями |
| [Сборка AppleALC без Xcode](docs/ru/building-applealc-without-xcode.md) | 32-полосный эквалайзер внутри драйвера и как собрать плагин Lilu одними Command Line Tools |
| [Звук, клавиатура, картридер](docs/ru/audio-keyboard-cardreader.md) | Мелкие правки, включая беду с русской раскладкой |
| [SMBIOS и Apple ID](docs/ru/smbios.md) | Согласованность серийников, проверка board-ID, чего избегать |
| [Настройки BIOS](docs/ru/bios-settings.md) | Что менять в прошивке Dell |
| [Известные проблемы](docs/ru/known-issues.md) | Что не работает и что уже проверено впустую |
| [Диагностика](docs/ru/troubleshooting.md) | Как искать причину, с реальными сигнатурами в логах |

---

## Благодарности

- [Acidanthera](https://github.com/acidanthera) — OpenCore, Lilu, VirtualSMC, WhateverGreen, AppleALC и многое другое
- [OpenIntelWireless](https://github.com/OpenIntelWireless) — `itlwm`, `HeliPort`, `IntelBluetoothFirmware`
- [Dortania](https://dortania.github.io/OpenCore-Install-Guide/) — руководство по установке OpenCore
- [zhen-zen/XPS-9500-CometLake-OpenCore](https://github.com/zhen-zen) и сообщество XPS 9500 — базовая
  конфигурация, с которой всё начиналось
- [5T33Z0/OCLP4Hackintosh](https://github.com/5T33Z0/OCLP4Hackintosh) — самое внятное описание ситуации с
  Wi-Fi в Sequoia

## Лицензия

Конфигурация, документация и скрипты: [MIT](LICENSE).

Приложенные кексты принадлежат своим авторам и распространяются по их лицензиям — см. внутри каждого `.kext`.
