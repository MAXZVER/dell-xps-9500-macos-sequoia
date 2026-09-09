# Графика и экран

## Intel UHD 630 — то, на чём всё держится

```
PciRoot(0x0)/Pci(0x2,0x0)
    AAPL,ig-platform-id              = 09 00 9B 3E     → 0x3E9B0009
    device-id                        = 9B 3E 00 00     → 0x3E9B
    enable-backlight-registers-fix   = 01 00 00 00
```

плюс `WhateverGreen.kext` и `-igfxblt` в boot-args.

`0x3E9B0009` — мобильный фреймбуфер UHD 630 с тремя внешними выходами. Он даёт полное ускорение, рабочий
внутренний экран 1920×1200 и рабочий внешний выход. Связка `enable-backlight-registers-fix` и `-igfxblt` —
это то, что делает управляемой подсветку внутренней панели на Comet Lake; без неё вы получите либо чёрный
экран, либо яркость, застрявшую на одном значении.

Клавиши яркости работают благодаря `BrightnessKeys.kext` и `SSDT-PNLF-CFL.aml`.

### Если у вас панель 4K OLED

Всё собрано и проверено на панели **1920×1200 без сенсора**. Для модели с 4K OLED обычно нужны другие
патчи коннекторов фреймбуфера (и часто `enable-dpcd-max-link-rate-fix`). Не считайте, что эти значения
перенесутся — начните с
[FAQ по Intel HD в WhateverGreen](https://github.com/acidanthera/WhateverGreen/blob/master/Manual/FAQ.IntelHD.en.md).

## NVIDIA GTX 1650 Ti — отключена

```
PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)
    disable-gpu = 01 00 00 00
```

вместе с `SSDT-NoHybGfx.aml`.

Драйвера под macOS для Turing нет и не будет — поддержка NVIDIA закончилась на Kepler. Поэтому карта не
просто простаивает, а обесточена, и это заметно экономит батарею. Ничего при этом не теряется: все экраны
на этой машине выводит встроенная графика.

## Внешние мониторы

Вывод по HDMI и по USB-C/Thunderbolt работает.

Есть особенность этого железа: после сна или горячего подключения внешний экран иногда возвращается с
неправильным режимом или не зажигается вовсе. `tools/displayfix.swift` — небольшая утилита для этого: она
смотрит текущую конфигурацию экранов и может вернуть корректный режим.

```bash
swiftc -O tools/displayfix.swift -o ~/tools/displayfix
~/tools/displayfix              # показать текущее состояние
~/tools/displayfix --autofix    # найти и исправить
```

`scripts/com.local.displayguard.plist` запускает её с `--autofix` в фоне. Ставится как LaunchAgent
(сначала поправьте пути — там плейсхолдер `YOUR_USERNAME`):

```bash
cp scripts/com.local.displayguard.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.local.displayguard.plist
```

Именно `launchctl bootstrap`, а не устаревший `launchctl load` — последний на современных macOS падает с
невнятным `Load failed: 5`.

## Thunderbolt 3

`SSDT-TB3_JHL7540TitanRidge.aml` и `SSDT-TB3HotPlug.aml` описывают контроллер Titan Ridge, а ACPI-патч
`NTFY → XFTY` отвечает за горячее подключение. Вывод изображения и USB через Type-C работают.
