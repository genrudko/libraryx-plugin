# Release process / Процесс релизов

## Русский

Каждое пользовательски значимое изменение LibraryX должно быть доступно не только
в исходниках, но и как готовый ZIP в **GitHub Releases**.

### Когда выпускать новый релиз

Новый релиз нужен после изменений, которые пользователь может заметить на устройстве:

- исправления UI/UX;
- исправления падений, навигации, обложек, сканирования или индекса;
- новые функции;
- изменения совместимости с KOReader;
- изменения локализации, влияющие на интерфейс;
- изменения упаковки или установки.

Чисто внутренние тесты, рефакторинг без изменения поведения и документация сами по
себе не требуют нового бинарного релиза.

### Версионирование

До стабильного 1.0 используется SemVer с prerelease-суффиксами:

- `v0.1.0-beta` — текущая beta-линия;
- исправления: `v0.1.1-beta`, `v0.1.2-beta`, ...;
- заметные новые возможности: `v0.2.0-beta`, и т. д.

### Обязательные артефакты

Каждый GitHub Release должен содержать:

- `libraryx-<tag>.koplugin.zip`;
- `libraryx-<tag>.koplugin.zip.sha256`;
- release notes на русском и английском.

Workflow `.github/workflows/release.yml` автоматически собирает ZIP из
**точного тега релиза**, проверяет архив и прикладывает ZIP + SHA-256.

### Перед релизом

```bash
./tools/check.sh
./tools/package.sh
unzip -t dist/libraryx-debug.koplugin.zip
git diff --check
```

Рабочее дерево должно быть чистым, а релизный тег должен указывать на проверенный commit.

---

## English

Every user-visible LibraryX change should be available not only as source code,
but also as a ready-to-install ZIP in **GitHub Releases**.

### When to publish a release

Publish a new release after changes that users can observe on the device:

- UI/UX fixes;
- crash, navigation, cover, scanning or index fixes;
- new features;
- KOReader compatibility changes;
- localization changes that affect the UI;
- packaging or installation changes.

Internal-only tests, behavior-preserving refactors and documentation-only changes
do not require a new binary release by themselves.

### Versioning

Before 1.0, use SemVer prereleases:

- `v0.1.0-beta` — current beta line;
- fixes: `v0.1.1-beta`, `v0.1.2-beta`, ...;
- substantial new features: `v0.2.0-beta`, etc.

### Required artifacts

Every GitHub Release must contain:

- `libraryx-<tag>.koplugin.zip`;
- `libraryx-<tag>.koplugin.zip.sha256`;
- release notes in Russian and English.

The `.github/workflows/release.yml` workflow automatically builds the ZIP from
the **exact release tag**, verifies it and uploads the ZIP + SHA-256.

### Before releasing

```bash
./tools/check.sh
./tools/package.sh
unzip -t dist/libraryx-debug.koplugin.zip
git diff --check
```

The working tree must be clean and the release tag must point to the verified commit.
