# Contributing

## Build and test

```bash
swift test
./scripts/build-app.sh
```

`./scripts/build-app.sh` builds a release binary, wraps it in `AutoClicker.app`, and code-signs it. Without an Apple Development identity it ad-hoc signs the app. After every ad-hoc rebuild, grant Accessibility again in **System Settings → Privacy & Security → Accessibility**.

## Layout rules

- `Models.swift` is data only.
- `Engine/` owns clicks, keys, hotkeys, and point picking. Views never call `CGEvent` or Carbon.
- Views talk only to `AppModel`.
- New runner behavior gets a test with `FakePoster` and `ControllableClock`.
- Interval minimum stays 10 ms.
- Shipped builds stay ad-hoc signed until a Developer ID exists.

## Pull requests

1. Keep changes focused on one concern.
2. Run `swift test` before opening a pull request.
3. Follow the layout rules above when adding modes, engine behavior, or UI.
