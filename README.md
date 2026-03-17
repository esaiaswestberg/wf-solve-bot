# wf-solve-bot

`wf-solve-bot` is a Wordfeud solver project built around a mobile-first Flutter app and a Python reference solver. The long-term direction is to provide a polished solver experience on iOS and Android, while keeping the original solver prototype in this repository as the technical foundation for the app.

Today, the main application lives in [`./flutter/`](./flutter/) and uses Dart code based on the original solver logic. It does not run the Python code from [`./py-solver/`](./py-solver/) directly. In the future, this repository will also include a fully automatic Wordfeud bot that can play automatically, but that work has not started yet.

The app is intended for release on the App Store and Google Play, but it is not available in either store yet.

## Current Status

This repository currently contains:

- A Flutter app for solving Wordfeud boards from images/screenshots
- A Python-based solver library and prototype implementation
- Bundled dictionaries, board templates, and supporting assets used by the solver workflow

## Repository Structure

### `flutter/`

The Flutter app is the primary product in this repository. It targets mobile platforms and contains the Dart implementation of the solver used by the app.

Current app responsibilities include:

- Loading bundled dictionary and template assets
- Letting the user pick an image from their device
- Parsing a Wordfeud board and rack from the image
- Generating and displaying ranked move suggestions

Planned distribution:

- iOS via the App Store
- Android via Google Play

Status:

- Not published yet

### `py-solver/`

`py-solver/` contains the original Python solver and image-processing prototype that the Flutter app is based on. It remains useful as a reference implementation and as a place to experiment with solver logic, parsing, scoring, and templates.

This Python code is not what runs inside the Flutter app. Instead, the app uses a translated Dart version of the same underlying ideas.

## Roadmap

The repository is expected to grow in two directions:

- Continue improving the Flutter solver app for iOS and Android
- Add a fully automatic Wordfeud bot that can play automatically

The automatic bot has not been started yet.

## Local Development

### Flutter App

Requirements:

- Flutter SDK
- A supported iOS or Android development environment

From the project root:

```bash
cd flutter
flutter pub get
flutter run
```

### Python Reference Solver

Requirements:

- Python 3
- A virtual environment tool such as `venv`

From the project root:

```bash
cd py-solver
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py examples/Screenshot_20260317-094138_Wordfeud.png
```

The Python solver expects an input screenshot path and uses the dictionaries and templates in `py-solver/`.

## Notes

- The Flutter app is based on the Python solver, but it does not embed or execute the Python runtime.
- The root project is still in active development.
- No App Store or Play Store release is available yet.
