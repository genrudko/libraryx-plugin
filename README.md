# LibraryX for KOReader

**Русский** · [English](#english)

LibraryX — индексированный библиотечный интерфейс для KOReader, ориентированный на навигацию и плотность информации AlReaderX. Чтение книг остаётся за штатным `ReaderUI` KOReader.

> Проект находится в активной разработке. Основное тестирование сейчас ведётся на Kindle Paperwhite 11 (PW5). Скриншоты будут добавлены позже.

## Возможности

- **Все книги / Авторы / Серии / Названия / Папки**
- поиск, сортировки, обратный порядок и быстрый переход **А–Я**
- фильтры по языку, жанрам, датам, новизне файлов и формату
- случайная книга
- реальные обложки и карточки с автором, языком, серией и жанрами
- адаптивная плотность списка: **Авто** или **3–10 книг на экран**
- неполная последняя страница растягивает карточки на доступную высоту
- отдельный экран информации о книге перед открытием ReaderUI
- long-press: **Читать / Удалить / Перейти / Избранное**
- переход ко всем авторам книги, серии и каталогу
- многометочное избранное: **К прочтению / Уже прочитано / Может быть позже / Стоящая книга / Мусор / Что-то непонятное**
- запуск KOReader сразу в LibraryX через штатное **Start with / Запускать с**
- русский и английский интерфейс; язык может следовать KOReader или задаваться отдельно

## Настройки

В меню **LibraryX → Настройки** доступны:

- **Список книг**:
  - плотность: `Автоматически` или `3–10`;
  - размер шрифта списка: `80–120%`;
  - жанры, язык, номер в серии, формат/размер файла — отдельными переключателями;
- **Превью книги**:
  - основной текст: `70–130%` (по умолчанию `90%`);
  - заголовок: `80–130%`;
  - обложка: `60–110%`;
  - показ жанров, метаданных и пути к файлу;
- **Язык интерфейса**: как в KOReader / Русский / English;
- сброс настроек LibraryX по умолчанию.

В режиме `Автоматически` количество карточек рассчитывается по реальной высоте экрана
и ограничивается диапазоном 3–10. Ручное значение всегда имеет приоритет.

## Установка

### Рекомендуемый способ — GitHub Releases

Откройте раздел **Releases** репозитория и скачайте готовый файл:

```text
libraryx-<версия>.koplugin.zip
```

Для каждой пользовательски значимой версии ZIP публикуется вместе с SHA-256 и двуязычными release notes.

### Сборка ZIP

```bash
git clone https://github.com/genrudko/libraryx-plugin.git
cd libraryx-plugin
./tools/package.sh
```

Будет создан:

```text
dist/libraryx-debug.koplugin.zip
```

Распакуйте каталог `libraryx.koplugin` в каталог плагинов KOReader.

Kindle:

```text
/mnt/us/koreader/plugins/libraryx.koplugin
```

Другие устройства:

```text
<каталог KOReader>/plugins/libraryx.koplugin
```

После копирования полностью перезапустите KOReader.

### Установка из исходников

Скачайте репозиторий, поместите его содержимое в каталог `libraryx.koplugin` и скопируйте его в `koreader/plugins/`.

```text
koreader/
└── plugins/
    └── libraryx.koplugin/
        ├── _meta.lua
        ├── main.lua
        ├── libraryui.lua
        └── ...
```

## Первый запуск

1. Перезапустите KOReader.
2. Откройте меню **LibraryX**.
3. Выберите **Папка библиотеки**.
4. Запустите **Сканировать библиотеку**.
5. Откройте **LibraryX**.

Чтобы KOReader открывался сразу в LibraryX:

```text
Настройки → Запускать с → LibraryX
```

Точное название пункта зависит от версии KOReader; LibraryX добавляется в штатное меню `Start with`.

## Обновление

Замените каталог `libraryx.koplugin` новой версией и перезапустите KOReader. Индекс и настройки LibraryX хранятся в каталоге настроек KOReader, а не внутри каталога плагина.

## Языки

- Русский (`ru`)
- English (`en`)
- для остальных языков используется английский fallback

---

## English

LibraryX is an indexed library frontend for KOReader inspired by AlReaderX navigation and information density. KOReader's native `ReaderUI` remains the actual reading engine.

> The project is under active development. Primary device testing is currently done on Kindle Paperwhite 11 (PW5). Screenshots will be added later.

### Features

- **All books / Authors / Series / Titles / Folders**
- search, sorting, reverse order and fast **A–Z** navigation
- filters by language, genres, dates, file novelty and format
- random book
- real covers and cards with author, language, series and genres
- adaptive density: **Automatic** or **3–10 books per screen**
- short final pages expand their rows to use the available viewport
- dedicated book-details screen before opening KOReader ReaderUI
- long-press actions: **Read / Delete / Go to / Favorites**
- navigation to every author of a book, its series and catalog
- multi-label Favorites: **To read / Already read / Maybe later / Worth reading / Trash / Something unclear**
- optional native **Start with LibraryX** integration
- English and Russian UI, either following KOReader or explicitly selected

### Settings

Open **LibraryX → Settings**.

- **Book list**:
  - density: `Automatic` or `3–10`;
  - list font size: `80–120%`;
  - independent toggles for genres, language, series number and file format/size;
- **Book preview**:
  - body text: `70–130%` (default `90%`);
  - title: `80–130%`;
  - cover: `60–110%`;
  - toggles for genres, metadata and file path;
- **Interface language**: follow KOReader / Russian / English;
- reset LibraryX settings to defaults.

`Automatic` density derives the row count from the real viewport and clamps it to
3–10. A manual value always overrides automatic density.

### Installation

#### Recommended — GitHub Releases

Open the repository **Releases** page and download:

```text
libraryx-<version>.koplugin.zip
```

Every user-visible release includes the ready-to-install ZIP, SHA-256 checksum and bilingual release notes.

#### Build the ZIP

```bash
git clone https://github.com/genrudko/libraryx-plugin.git
cd libraryx-plugin
./tools/package.sh
```

This creates:

```text
dist/libraryx-debug.koplugin.zip
```

Extract the `libraryx.koplugin` directory into KOReader's plugin directory.

Kindle:

```text
/mnt/us/koreader/plugins/libraryx.koplugin
```

Other devices:

```text
<KOReader directory>/plugins/libraryx.koplugin
```

Restart KOReader completely after copying the plugin.

#### Install from source

Download the repository and place its contents inside a directory named `libraryx.koplugin` under `koreader/plugins/`.

```text
koreader/
└── plugins/
    └── libraryx.koplugin/
        ├── _meta.lua
        ├── main.lua
        ├── libraryui.lua
        └── ...
```

### First run

1. Restart KOReader.
2. Open the **LibraryX** menu.
3. Choose **Library folder**.
4. Run **Scan library**.
5. Open **LibraryX**.

To start KOReader directly in LibraryX:

```text
Settings → Start with → LibraryX
```

The exact wording may vary slightly between KOReader versions; LibraryX is added to KOReader's native `Start with` menu.

### Updating

Replace the `libraryx.koplugin` directory with the new version and restart KOReader. LibraryX settings and its index live in KOReader's settings directory, not inside the plugin directory.

### Languages

- English (`en`)
- Russian (`ru`)
- other KOReader languages fall back to English
