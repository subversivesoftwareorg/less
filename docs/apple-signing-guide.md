# Apple Code Signing, Notarization & Gatekeeper Guide

A practical guide for signing and notarizing Tapped for distribution outside the Mac App Store.

## Overview

Apple requires three layers for a Mac app to launch without warnings:

1. **Code signing** — a Developer ID certificate proves the app comes from you
2. **Notarization** — Apple scans the app for malware and issues a ticket
3. **Stapling** — the notarization ticket is embedded in the DMG so verification works offline

Without all three, users see "this app cannot be opened" or the dreaded "unidentified developer" dialog.

## Prerequisites

### Developer ID Application certificate

You need a **Developer ID Application** certificate (not just "Apple Development").

**Check if you have one:**

```bash
security find-identity -v -p codesigning | grep "Developer ID"
```

You should see something like:

```
C623D6F8... "Developer ID Application: Your Name (TEAM_ID)"
```

**If missing:** Create one at [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates) → "+" → "Developer ID Application". Requires a paid Apple Developer Program membership ($99/year). Only the Account Holder role can create these.

### App-specific password

Notarization requires an app-specific password (not your Apple ID password).

**Create one:**

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign-In and Security → App-Specific Passwords
3. Generate a new password, name it "Tapped Notarization"
4. Save it somewhere secure

### Tools

All tools come with Xcode Command Line Tools:

```bash
xcode-select --install   # if not already installed
```

## Building a signed, notarized DMG

The build script handles everything:

```bash
# Full build: sign + notarize + staple
APPLE_ID=you@email.com ./scripts/build-dmg.sh

# Build and sign only (skip notarization for testing)
./scripts/build-dmg.sh --skip-notarize
```

The script will prompt for your app-specific password if not set via `APP_PASSWORD` env var.

## Manual step-by-step

If the script fails or you need to do steps individually:

### 1. Build

```bash
xcodebuild -project Tapped.xcodeproj \
    -scheme Tapped \
    -configuration Release \
    -derivedDataPath build/DerivedData \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    clean build
```

### 2. Sign

```bash
codesign --force --deep --options runtime \
    --sign "Developer ID Application: Your Name (TEAM_ID)" \
    --timestamp \
    build/DerivedData/Build/Products/Release/Tapped.app
```

### 3. Create DMG

```bash
# Using create-dmg (brew install create-dmg)
create-dmg --volname "Tapped" \
    --icon "Tapped.app" 175 190 \
    --app-drop-link 425 190 \
    build/Tapped-1.0.1.dmg \
    build/dmg-staging/

# Sign the DMG itself
codesign --force --sign "Developer ID Application: Your Name (TEAM_ID)" \
    --timestamp build/Tapped-1.0.1.dmg
```

### 4. Notarize

```bash
xcrun notarytool submit build/Tapped-1.0.1.dmg \
    --apple-id you@email.com \
    --team-id YOUR_TEAM_ID \
    --password "your-app-specific-password" \
    --wait \
    --timeout 15m
```

### 5. Staple

```bash
xcrun stapler staple build/Tapped-1.0.1.dmg
```

## Verification commands

### Check code signature

```bash
codesign --verify --verbose=2 Tapped.app
```

**Good output:**

```
Tapped.app: valid on disk
Tapped.app: satisfies its Designated Requirement
```

### Check signing identity and details

```bash
codesign -dv --verbose=2 Tapped.app
```

Look for:

```
Authority=Developer ID Application: Your Name (TEAM_ID)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
Runtime Version=14.0.0   (or higher)
```

The three `Authority` lines show the full trust chain. `Runtime Version` confirms Hardened Runtime is enabled (required for notarization).

### Check Gatekeeper acceptance (the real test)

For an app:

```bash
spctl --assess --verbose Tapped.app
```

For a DMG:

```bash
spctl --assess --verbose --type open Tapped-1.0.1.dmg
```

**Good output:**

```
Tapped.app: accepted
source=Notarized Developer ID
```

**Bad output:**

```
Tapped.app: rejected
source=Insufficient Context
```

"Insufficient Context" means not notarized or the ticket isn't stapled.

> **Note:** `spctl --assess --type open` on DMGs can give false negatives. If the DMG check fails but the app inside passes, you're fine — Gatekeeper checks the app at launch, not the DMG.

### Check stapling

```bash
xcrun stapler validate Tapped-1.0.1.dmg
```

**Good output:**

```
The validate action worked!
```

### Check if the binary is universal

```bash
lipo -archs Tapped.app/Contents/MacOS/Tapped
```

**Good output:**

```
arm64 x86_64
```

## Checking notarization status

### List all submissions

```bash
xcrun notarytool history \
    --apple-id you@email.com \
    --team-id YOUR_TEAM_ID \
    --password "your-app-specific-password"
```

### Check a specific submission

```bash
xcrun notarytool info SUBMISSION_ID \
    --apple-id you@email.com \
    --team-id YOUR_TEAM_ID \
    --password "your-app-specific-password"
```

### View the notarization log (shows why it failed)

```bash
xcrun notarytool log SUBMISSION_ID \
    --apple-id you@email.com \
    --team-id YOUR_TEAM_ID \
    --password "your-app-specific-password"
```

The log is a JSON file that lists every issue found. Common problems:

- `"The signature does not include a secure timestamp"` — add `--timestamp` to codesign
- `"The executable does not have the hardened runtime enabled"` — add `--options runtime` to codesign
- `"The binary is not signed"` — a nested framework/helper wasn't signed (use `--deep`)

## Troubleshooting

### "Operation not permitted" during signing

Your certificate may have expired or been revoked. Check:

```bash
security find-identity -v -p codesigning
```

If it shows `0 valid identities found`, re-create the certificate at developer.apple.com.

### Notarization hangs (runs for hours)

The `--wait` flag polls Apple's servers until completion. If it hangs:

1. Kill the process (Ctrl+C)
2. Check if the submission actually went through:

   ```bash
   xcrun notarytool history --apple-id ... --team-id ... --password ...
   ```

3. If status is "Accepted", staple manually:

   ```bash
   xcrun stapler staple build/Tapped-1.0.1.dmg
   ```

4. If status is "In Progress", wait and check again in a few minutes
5. Check [developer.apple.com/system-status](https://developer.apple.com/system-status/) for service outages

The build script uses `--timeout 15m` to prevent indefinite hangs.

### "Insufficient Context" after stapling

This usually means the DMG was rebuilt after notarization. The ticket is tied to the exact binary hash — if you rebuild, you need to re-notarize. Always staple the same DMG that was submitted.

### App works on your machine but not another

Check that the other machine's macOS version meets the deployment target:

```bash
# On the other machine
sw_vers -productVersion
```

Tapped requires macOS 14.0+. Also verify the binary is universal:

```bash
lipo -archs Tapped.app/Contents/MacOS/Tapped
# Should show: arm64 x86_64
```

### Simulating what a user sees (Gatekeeper test)

To test the full Gatekeeper experience as if the DMG was downloaded from the internet:

```bash
# Add quarantine flag (simulates a Safari/Chrome download)
xattr -w com.apple.quarantine "0081;$(printf '%x' $(date +%s));Safari;$(uuidgen)" Tapped-1.0.1.dmg

# Open it — macOS will run Gatekeeper checks
open Tapped-1.0.1.dmg
```

If properly signed and notarized, it opens normally. If not, you'll see the security warning dialog.

## Quick reference

| What you want to check | Command |
|------------------------|---------|
| Do I have a Developer ID cert? | `security find-identity -v -p codesigning \| grep "Developer ID"` |
| Is the app signed? | `codesign --verify --verbose=2 Tapped.app` |
| Who signed it? | `codesign -dv --verbose=2 Tapped.app` |
| Will Gatekeeper accept it? | `spctl --assess --verbose Tapped.app` |
| Is the notarization ticket stapled? | `xcrun stapler validate Tapped-1.0.1.dmg` |
| Is it a universal binary? | `lipo -archs Tapped.app/Contents/MacOS/Tapped` |
| What notarizations have I submitted? | `xcrun notarytool history --apple-id ... --team-id ... --password ...` |
| Why did notarization fail? | `xcrun notarytool log SUBMISSION_ID --apple-id ... --team-id ... --password ...` |
