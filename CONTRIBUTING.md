# Contributing

## Build and test

```bash
swift test
./scripts/build-app.sh
```

`./scripts/build-app.sh` builds a release binary, wraps it in `AutoClicker.app`, and code-signs it. Published builds are signed on a Mac that has the Apple Development identity. A self-signed certificate has no Team ID, so macOS asks for Accessibility again after every update.

## Layout rules

- `Models.swift` is data only.
- `Engine/` owns clicks, keys, hotkeys, and point picking. Views never call `CGEvent` or Carbon.
- Views talk only to `AppModel`.
- New runner behavior gets a test with `FakePoster` and `ControllableClock`.
- Interval minimum stays 10 ms.
- Shipped builds are signed with the Apple Development identity so Accessibility survives updates. Ad-hoc signing is only the fallback when that identity is missing.

## Pull requests

1. Keep changes focused on one concern.
2. Run `swift test` before opening a pull request.
3. Follow the layout rules above when adding modes, engine behavior, or UI.
