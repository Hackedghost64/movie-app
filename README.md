# MovieBox Monorepo

Complete reverse-engineered client ecosystem for MovieBox streaming, consisting of a Flutter client app, a Python FastAPI streaming gateway daemon, and reverse-engineering technical research documentation.

## Repository Structure

- `app/`: Cross-platform Flutter client featuring Netflix-style mobile & TV (Android TV / 10-foot UI) spatial navigation, local stream relay, and custom player.
- `wrapper/`: Lightweight Python FastAPI streaming gateway with automatic self-healing protocol extraction, CLI, and TUI.
- `moviebox_client.py`: Standalone Python client implementation for signing and communicating with the gateway API.
- `docs/`: Superpowers planning specifications and architectural designs.

## Getting Started

### Flutter Client
```bash
cd app
flutter pub get
flutter run
```

### Python Streaming Gateway
```bash
cd wrapper
pip install -e .
mbx setup
```
