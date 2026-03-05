<p align="center">
  <img src="banner.png" alt="Whisper Free" width="800">
</p>

<p align="center">
  <a href="#english">English</a> • <a href="#russian">Русский</a>
</p>

---

<a id="english"></a>

## English 🇺🇸

### Free Professional macOS GUI for local Voice-to-Text — No Subscriptions, 100% Privacy

**WhisperKiller** is a hyper-fast, high-performance macOS application designed to transcribe your voice to text instantly using OpenAI's Whisper models.

> Love the convenience of AI dictation but hate paying monthly subscriptions for professional features? WhisperKiller gives you the "SuperWhisper experience" for free, running locally on your Mac's GPU/NPU or via API.

It is a **fully-featured SuperWhisper alternative** that puts privacy and speed first. No "marketing fluff," just raw performance.

### Features
- **Control**: Lives in the menu bar, triggered by a global hotkey (default `⌥ Space`).
- **Transcription**: Local via [whisper.cpp](https://github.com/ggerganov/whisper.cpp) (GPU/NPU optimized) or cloud via OpenAI API.
- **File Transcription**: Dedicated view for transcribing audio/video files with batch processing queue.
- **Diarization**: Support for AI-powered speaker identification (splitting text by speaker).
- **Workflow**: Results are automatically inserted into the active application via paste or direct typing.
- **Improved Settings**: Redesigned 5-tab interface (App, Capture, Engine, AI Modes, Info) for better organization.
- **Smart Modes**: 4 built-in modes (Dictation, Email, Code, Notes) + create your own custom AI prompts.
- **Intelligent Keys**: API keys for OpenAI/Perplexity only appear when needed for your current engine.
- **AI Refinement**: One-click post-processing via OpenAI or Perplexity to fix grammar and formatting.
- **Persistence**: Optimized deployment script ensures Accessibility permissions stay active after updates.
- **Global**: Supports 18 languages with auto-detection.

### System Requirements
- **macOS**: 14.0 (Sonoma) or newer.
- **Architecture**: **Apple Silicon (arm64)** required. Intel is not supported.
- **RAM**: 8GB Minimum, 16GB+ recommended for large models.

### Setup
1. **Download**: Get `WhisperFree.dmg` from [Releases](https://github.com/iddictive/Whisper-Free/releases).
2. **Install**: Drag to `Applications`.
3. **Permissions**: Grant **Accessibility** and **Microphone** access on first launch.

### Manual Build
```bash
git clone https://github.com/iddictive/Whisper-Free.git
cd Whisper-Free
make install
```

---

<a id="russian"></a>

## Русский 🇷🇺

### Профессиональный GUI для локального распознавания речи на macOS — Без подписок, 100% приватно

**WhisperKiller** — сверхбыстрое и производительное приложение для macOS, которое мгновенно превращает ваш голос в текст, используя модели Whisper от OpenAI.

> Нравится удобство AI-диктовки, но не хочется платить ежемесячную подписку за "PRO"-функции? WhisperKiller — это бесплатная альтернатива SuperWhisper, работающая локально на GPU/NPU вашего Mac или через API.

Это **полнофункциональная замена SuperWhisper**, где в приоритете приватность и скорость. Минимум «маркетинговой воды», максимум производительности.

### Возможности
- **Управление**: Работает из Menu Bar по глобальной горячей клавише (по умолчанию `⌥ Space`).
- **Транскрипция**: Локально через [whisper.cpp](https://github.com/ggerganov/whisper.cpp) (оптимизировано под Apple Silicon) или облако (OpenAI API).
- **Транскрибация файлов**: Отдельный интерфейс для обработки аудио/видео файлов с очередью задач.
- **Диаризация**: Поддержка разделения по ролям (AI-идентификация спикеров).
- **Интеграция**: Результат автоматически вставляется в активное приложение (вставка из буфера или прямая печать).
- **Новый интерфейс**: Полностью переработанные настройки (5 вкладок: App, Capture, Engine, AI Modes, Info).
- **Умные режимы**: 4 встроенных пресета (Диктовка, Email, Код, Заметки) + создание собственных AI-промптов.
- **Умные ключи**: API-ключи OpenAI/Perplexity отображаются только когда они необходимы.
- **AI-коррекция**: Постобработка через OpenAI или Perplexity для исправления грамматики и оформления.
- **Стабильность**: Настроенная подпись и скрипт деплоя сохраняют права Accessibility после обновлений.
- **Языки**: Поддержка 18 языков с автоопределением.

### Системные требования
- **macOS**: 14.0 (Sonoma) или новее.
- **Архитектура**: Только **Apple Silicon (arm64)**. Intel не поддерживается.
- **RAM**: Минимум 8 ГБ, рекомендуется 16 ГБ+ для тяжелых моделей.

### Установка
1. **Скачать**: `WhisperFree.dmg` со страницы [Релизов](https://github.com/iddictive/Whisper-Free/releases).
2. **Установить**: Перетянуть в `Applications`.
3. **Права**: На первом запуске разрешите доступ к **Accessibility** (Универсальный доступ) и **Микрофону**.

### Сборка из исходников
```bash
git clone https://github.com/iddictive/Whisper-Free.git
cd Whisper-Free
make install
```

---
MIT License.
