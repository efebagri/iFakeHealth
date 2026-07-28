# iFakeHealth

A minimal native iOS app that writes fake step, distance and active-energy
samples into Apple Health. Enter a step count, tap the button, done.

Not distributed via the App Store — build and sideload the `.ipa` yourself.

## Requirements

- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A physical iPhone (HealthKit writes don't do anything meaningful on the Simulator)

## Setup

The `.xcodeproj` is generated from `project.yml` and is not committed.

```bash
xcodegen generate
open iFakeHealth.xcodeproj
```

In Xcode, select the `iFakeHealth` target → **Signing & Capabilities** and set
your own **Team** (a free personal Apple ID works). The bundle identifier in
`project.yml` (`dev.efebagri.iFakeHealth`) must be unique to your account —
change it if Xcode complains.

## Running

- **On your iPhone via Xcode**: plug in the device, select it as the run
  destination, hit Run. First launch needs "Trust This Developer" in
  Settings → General → VPN & Device Management.
- **As an `.ipa` to sideload** (AltStore/Sidestore/etc.): Product → Archive,
  then Distribute App → Development, and export the `.ipa`.

## What it does

One screen: a step-count field and a "Write to Health" button. On tap it
requests HealthKit write authorization and saves three samples for a
30-minute window ending now:

- `stepCount` — the entered value
- `distanceWalkingRunning` — steps × 0.762 m
- `activeEnergyBurned` — steps × 0.04 kcal

No settings, no accounts, no other screens.
