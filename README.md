# worldbox-2

Песочница из проб на Godot 4.7. Проба — это одна механика, одна сцена и заметка о том,
что выяснилось, когда в неё поиграли руками. После заметки код замораживается.

Копится здесь не код, а заметки. Смысл — пощупать механики знакомых игр и заодно
разобраться в движке. Игра из этого не собирается: для игры нужен отдельный репозиторий,
с нуля и с пониманием, чего хочешь.

Правила проекта — в [PURPOSE.md](PURPOSE.md), стиль кода — в [STYLE.md](STYLE.md),
формат заметки — в [NOTE.md](NOTE.md), грабли движка — в [GODOT.md](GODOT.md).
Сейчас проб 46, закрыто 45, мультипроб 3.

## Запуск

Нужен Godot 4.7 или новее. Открыть папку как проект и запустить — главная сцена это
сетка запуска: она читает таблицу из `PURPOSE.md` и открывает любую пробу.

Внутри пробы работают две общие клавиши: **F1** — вернуться в сетку, **F2** — снять кадр
для этой галереи. Остальное у каждой пробы своё и подписано прямо на экране.

## Устройство

Пробы не переиспользуют друг друга — общего кода ноль, повторы намеренные. Тестов нет,
приёмка руками. Мультипробы в `mixes/` собирают сущности из нескольких закрытых проб и
проверяют то, чего одиночная проба показать не может.

Комментарии и код на английском, заметки на русском. Снимки в галерее сделаны
`tools/Shot.gd` — он открывает каждую сцену на пару секунд, поэтому часть кадров
показывает пробу в покое, до того как её тронули.

## Чужое

`addons/ocean_waves_fft` — вендоренная копия [2Retr0/GodotOceanWaves](https://github.com/2Retr0/GodotOceanWaves)
(MIT): FFT-океан на compute-шейдерах. Его использует проба 23, где он стоит рядом с
процедурной волной из пробы 22, и проба 24.


## Пробы

| | |
|---|---|
| <img src="img/probes/01_walk.jpg" width="440"><br><b>01_walk</b> — ходьба и прыжок<br><sub><a href="probes/01_walk/README.md">заметка</a> · эталон: Quake 3</sub> | <img src="img/probes/02_orbit.jpg" width="440"><br><b>02_orbit</b> — третье лицо: орбита камеры<br><sub><a href="probes/02_orbit/README.md">заметка</a> · эталон: Godot TPS demo</sub> |
| <img src="img/probes/03_shoot.jpg" width="440"><br><b>03_shoot</b> — стрельба: сцена как заготовка<br><sub><a href="probes/03_shoot/README.md">заметка</a> · эталон: Quake 3</sub> | <img src="img/probes/04_crowd.jpg" width="440"><br><b>04_crowd</b> — толпа: где ломается узел на объект<br><sub><a href="probes/04_crowd/README.md">заметка</a> · эталон: Homeworld</sub> |
| <img src="img/probes/05_truck.jpg" width="440"><br><b>05_truck</b> — шестиколёсник: подвеска и раскладка привода<br><sub><a href="probes/05_truck/README.md">заметка</a> · эталон: SnowRunner</sub> | <img src="img/probes/06_command.jpg" width="440"><br><b>06_command</b> — командование сверху и тактическая пауза<br><sub><a href="probes/06_command/README.md">заметка</a> · эталон: Homeworld</sub> |
| <img src="img/probes/07_psx.jpg" width="440"><br><b>07_psx</b> — стиль как набор ограничений<br><sub><a href="probes/07_psx/README.md">заметка</a> · эталон: PlayStation</sub> | <img src="img/probes/08_boom.jpg" width="440"><br><b>08_boom</b> — взрыв, разобранный на слои<br><sub><a href="probes/08_boom/README.md">заметка</a></sub> |
| <img src="img/probes/09_fx.jpg" width="440"><br><b>09_fx</b> — эффекты без кода: реестр, таймлайн, пул<br><sub><a href="probes/09_fx/README.md">заметка</a></sub> | <img src="img/probes/10_possess.jpg" width="440"><br><b>10_possess</b> — вселение: два взгляда на один мир<br><sub><a href="probes/10_possess/README.md">заметка</a> · эталон: Battlezone</sub> |
| <img src="img/probes/11_turn.jpg" width="440"><br><b>11_turn</b> — ход: мир движется, только когда двигаюсь я<br><sub><a href="probes/11_turn/README.md">заметка</a> · эталон: рогалик</sub> | <img src="img/probes/12_gen.jpg" width="440"><br><b>12_gen</b> — генерация: число на входе, подземелье на выходе<br><sub><a href="probes/12_gen/README.md">заметка</a> · эталон: Rogue</sub> |
| <img src="img/probes/13_dress.jpg" width="440"><br><b>13_dress</b> — одевание: та же сетка, три раза<br><sub><a href="probes/13_dress/README.md">заметка</a> · эталон: Diablo</sub> | <img src="img/probes/14_chunks.jpg" width="440"><br><b>14_chunks</b> — уровень из ручных кусков<br><sub><a href="probes/14_chunks/README.md">заметка</a> · эталон: Diablo</sub> |
| <img src="img/probes/15_data.jpg" width="440"><br><b>15_data</b> — контент как данные<br><sub><a href="probes/15_data/README.md">заметка</a> · эталон: Diablo</sub> | <img src="img/probes/16_save.jpg" width="440"><br><b>16_save</b> — что в мире правда<br><sub><a href="probes/16_save/README.md">заметка</a> · эталон: рогалик</sub> |
| <img src="img/probes/17_sight.jpg" width="440"><br><b>17_sight</b> — зрение: вижу, помню, не знаю<br><sub><a href="probes/17_sight/README.md">заметка</a> · эталон: X-COM</sub> | <img src="img/probes/18_ui.jpg" width="440"><br><b>18_ui</b> — интерфейс руками: сетка, перетаскивание, раскладка<br><sub><a href="probes/18_ui/README.md">заметка</a> · эталон: Diablo</sub> |
| <img src="img/probes/19_hud.jpg" width="440"><br><b>19_hud</b> — боевой HUD: часы и геометрия<br><sub><a href="probes/19_hud/README.md">заметка</a> · эталон: WoW</sub> | <img src="img/probes/20_spec.jpg" width="440"><br><b>20_spec</b> — спека как данные: ресурс, баффы, процы, симулятор<br><sub><a href="probes/20_spec/README.md">заметка</a> · эталон: WoW</sub> |
| <img src="img/probes/21_water.jpg" width="440"><br><b>21_water</b> — вода: шесть слоёв и то, что вокруг неё<br><sub><a href="probes/21_water/README.md">заметка</a> · эталон: Sea of Thieves, MGS2</sub> | <img src="img/probes/22_swell.jpg" width="440"><br><b>22_swell</b> — одна волна, два счётчика<br><sub><a href="probes/22_swell/README.md">заметка</a> · эталон: Корсары</sub> |
| <img src="img/probes/23_fft.jpg" width="440"><br><b>23_fft</b> — два океана под одним небом<br><sub><a href="probes/23_fft/README.md">заметка</a> · эталон: Sea of Thieves</sub> | <img src="img/probes/24_knobs.jpg" width="440"><br><b>24_knobs</b> — ручки, собранные из самого шейдера<br><sub><a href="probes/24_knobs/README.md">заметка</a> · эталон: инструмент</sub> |
| <img src="img/probes/25_map.jpg" width="440"><br><b>25_map</b> — карта: живая, рисованная, запечённая<br><sub><a href="probes/25_map/README.md">заметка</a> · эталон: Diablo, X-COM</sub> | <img src="img/probes/26_path.jpg" width="440"><br><b>26_path</b> — путь: A* против поля потока<br><sub><a href="probes/26_path/README.md">заметка</a> · эталон: X-COM, RTS</sub> |
| <img src="img/probes/27_crowd.jpg" width="440"><br><b>27_crowd</b> — толпа: расступание<br><sub><a href="probes/27_crowd/NOTES.md">заметка</a> · эталон: RTS, MMO</sub> | <img src="img/probes/28_phys.jpg" width="440"><br><b>28_phys</b> — физика: тела, сочленения, повторяемость<br><sub><a href="probes/28_phys/NOTES.md">заметка</a></sub> |
| <img src="img/probes/29_day.jpg" width="440"><br><b>29_day</b> — небо и время суток<br><sub><a href="probes/29_day/NOTES.md">заметка</a></sub> | <img src="img/probes/30_gun.jpg" width="440"><br><b>30_gun</b> — стрельба: выстрел как аккорд<br><sub><a href="probes/30_gun/NOTES.md">заметка</a> · эталон: FEAR, DOOM</sub> |
| <img src="img/probes/31_sound.jpg" width="440"><br><b>31_sound</b> — звук как информация<br><sub><a href="probes/31_sound/NOTES.md">заметка</a></sub> | <img src="img/probes/32_move.jpg" width="440"><br><b>32_move</b> — акробатика от первого лица<br><sub><a href="probes/32_move/NOTES.md">заметка</a> · эталон: Titanfall, Mirror's Edge</sub> |
| <img src="img/probes/33_land.jpg" width="440"><br><b>33_land</b> — рельеф как источник импульса<br><sub><a href="probes/33_land/NOTES.md">заметка</a> · эталон: Tribes</sub> | <img src="img/probes/34_scale.jpg" width="440"><br><b>34_scale</b> — масштаб: как держать мир, который больше экрана<br><sub><a href="probes/34_scale/NOTES.md">заметка</a></sub> |
| <img src="img/probes/35_detail.jpg" width="440"><br><b>35_detail</b> — детализация поверхности<br><sub><a href="probes/35_detail/NOTES.md">заметка</a></sub> | <img src="img/probes/36_forest.jpg" width="440"><br><b>36_forest</b> — лоу-поли лес<br><sub><a href="probes/36_forest/NOTES.md">заметка</a></sub> |
| <img src="img/probes/37_car.jpg" width="440"><br><b>37_car</b> — машина: четыре луча, перенос веса, круг трения<br><sub><a href="probes/37_car/NOTES.md">заметка</a> · эталон: GTA, Halo</sub> | <img src="img/probes/38_tyre.jpg" width="440"><br><b>38_tyre</b> — шина: проскальзывание, нагрузка, дифференциал<br><sub><a href="probes/38_tyre/NOTES.md">заметка</a> · эталон: Gran Turismo</sub> |
| <img src="img/probes/40_hit.jpg" width="440"><br><b>40_hit</b> — попадание: импульс, рычаг, разрушение<br><sub><a href="probes/40_hit/NOTES.md">заметка</a> · эталон: Half-Life 2</sub> | <img src="img/probes/41_ruin.jpg" width="440"><br><b>41_ruin</b> — конструкция: связи, порог, обрушение<br><sub><a href="probes/41_ruin/NOTES.md">заметка</a> · эталон: Red Faction</sub> |
| <img src="img/probes/42_voronoi.jpg" width="440"><br><b>42_voronoi</b> — скол: ячейки Вороного, куски складываются в целое<br><sub><a href="probes/42_voronoi/NOTES.md">заметка</a> · эталон: Red Faction Guerrilla</sub> | <img src="img/probes/43_stuff.jpg" width="440"><br><b>43_stuff</b> — материал: прочность против вязкости, узор ломания<br><sub><a href="probes/43_stuff/NOTES.md">заметка</a> · эталон: Red Faction Guerrilla</sub> |
| <img src="img/probes/44_missile.jpg" width="440"><br><b>44_missile</b> — ракета как аппарат: тяга, сопротивление, рули<br><sub><a href="probes/44_missile/NOTES.md">заметка</a> · эталон: ArmA, DCS</sub> | <img src="img/probes/45_seeker.jpg" width="440"><br><b>45_seeker</b> — головка наведения: захват, сближение, срыв<br><sub><a href="probes/45_seeker/NOTES.md">заметка</a> · эталон: DCS, Ace Combat</sub> |
| <img src="img/probes/46_rocket.jpg" width="440"><br><b>46_rocket</b> — ракета-носитель: тяга, устойчивость, ступени<br><sub><a href="probes/46_rocket/NOTES.md">заметка</a> · эталон: Kerbal Space Program</sub> | <img src="img/probes/47_shoulder.jpg" width="440"><br><b>47_shoulder</b> — пуск с плеча: струя назад, взведение, ведение цели рукой<br><sub><a href="probes/47_shoulder/NOTES.md">заметка</a> · эталон: ArmA · не закрыта</sub> |

## Мультипробы

| | |
|---|---|
| <img src="img/mixes/01_gunrun.jpg" width="440"><br><b>01_gunrun</b> — акробатика и оружие<br><sub><a href="mixes/01_gunrun/NOTES.md">заметка</a></sub> | <img src="img/mixes/02_drive.jpg" width="440"><br><b>02_drive</b> — стрельба с колёс<br><sub><a href="mixes/02_drive/NOTES.md">заметка</a></sub> |
| <img src="img/mixes/03_siege.jpg" width="440"><br><b>03_siege</b> — осада: здание, пушка, скол<br><sub><a href="mixes/03_siege/NOTES.md">заметка</a></sub> |  |
