# Contributing

## Build and test

```bash
swift test
./scripts/build-app.sh
```

`./scripts/build-app.sh` builds a release binary, wraps it in `AutoClicker.app`, and code-signs it. Releases keep a stable signing identity so Accessibility survives updates. Without that identity, or a Developer ID / Apple Development certificate, the script ad-hoc signs and macOS asks for Accessibility again after every rebuild.

## Layout rules

- `Models.swift` is data only.
- `Engine/` owns clicks, keys, hotkeys, and point picking. Views never call `CGEvent` or Carbon.
- Views talk only to `AppModel`.
- New runner behavior gets a test with `FakePoster` and `ControllableClock`.
- Interval minimum stays 10 ms.
- Shipped builds use the stable Auto Clicker signing identity so Accessibility survives updates. Ad-hoc signing is only the fallback when that identity is missing.

## Pull requests

1. Keep changes focused on one concern.
2. Run `swift test` before opening a pull request.
3. Follow the layout rules above when adding modes, engine behavior, or UI.
