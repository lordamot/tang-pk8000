# MIT License

Copyright (c) 2026 Sergei Lemeshev and contributors (PK8000 Nano)
Copyright (c) 2024-2026 Alexey Gurov, Sergei Lemeshev and contributors
(the parts taken from UKNC Nano: the MCU link, the HDMI encoder, the
tools and the firmware)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

# Лицензия MIT

Copyright (c) 2026 Сергей Лемешев и участники (PK8000 Nano)
Copyright (c) 2024-2026 Алексей Гуров, Сергей Лемешев и участники
(части, взятые из UKNC Nano: связь с МК, HDMI-кодер, инструменты и прошивка)

Данная лицензия разрешает лицам, получившим копию данного программного
обеспечения и сопутствующей документации (в дальнейшем именуемыми
«Программное обеспечение»), безвозмездно использовать Программное
обеспечение без ограничений, включая неограниченное право на использование,
копирование, изменение, слияние, публикацию, распространение,
сублицензирование и/или продажу копий Программного обеспечения, а также
лицам, которым предоставляется данное Программное обеспечение, при
соблюдении следующих условий:

Указанное выше уведомление об авторском праве и данные условия должны быть
включены во все копии или значимые части данного Программного обеспечения.

ДАННОЕ ПРОГРАММНОЕ ОБЕСПЕЧЕНИЕ ПРЕДОСТАВЛЯЕТСЯ «КАК ЕСТЬ», БЕЗ КАКИХ-ЛИБО
ГАРАНТИЙ, ЯВНО ВЫРАЖЕННЫХ ИЛИ ПОДРАЗУМЕВАЕМЫХ, ВКЛЮЧАЯ ГАРАНТИИ ТОВАРНОЙ
ПРИГОДНОСТИ, СООТВЕТСТВИЯ ПО ЕГО КОНКРЕТНОМУ НАЗНАЧЕНИЮ И ОТСУТСТВИЯ
НАРУШЕНИЙ, НО НЕ ОГРАНИЧИВАЯСЬ ИМИ. НИ В КАКОМ СЛУЧАЕ АВТОРЫ ИЛИ
ПРАВООБЛАДАТЕЛИ НЕ НЕСУТ ОТВЕТСТВЕННОСТИ ПО КАКИМ-ЛИБО ИСКАМ, ЗА УЩЕРБ ИЛИ
ПО ИНЫМ ТРЕБОВАНИЯМ, В ТОМ ЧИСЛЕ ПРИ ДЕЙСТВИИ КОНТРАКТА, ДЕЛИКТЕ ИЛИ ИНОЙ
СИТУАЦИИ, ВОЗНИКШИМ ИЗ-ЗА ИСПОЛЬЗОВАНИЯ ПРОГРАММНОГО ОБЕСПЕЧЕНИЯ ИЛИ ИНЫХ
ДЕЙСТВИЙ С ПРОГРАММНЫМ ОБЕСПЕЧЕНИЕМ.

В случае расхождений между текстами английская версия имеет приоритет.

---

# Third-party notices

- `tang/src/pk8000/vm80a.v` - the КР580ВМ80А core, copyright 2014-2018
  1801BM1@gmail.com, Creative Commons Attribution 3.0
  (`tang/src/pk8000/vm80a-LICENSE.md`).  Used verbatim.
- `tang/src/mister/`, `mnano/` - MiSTeryNano by Till Harbaum, as carried
  by UKNC Nano; `mnano/u8g2` is olikraus's u8g2 (BSD).
- `tools/waits_rom.py` reproduces the per-opcode wait-state measurements
  recorded in Emu80's `Pk8000CpuWaits` (Viktor Pykhonin, GPL v3) as the
  hardware measurements they are; the script and the module it emits are
  this repository's.
- `tang/rom/pk8000_v12.rom` and the other ROM images are the ПК8000's own
  firmware, of their original authors (ПО ЭВТ, Penza, 1987); the
  schematics are Mick's (micklab.ru) redrawings.
