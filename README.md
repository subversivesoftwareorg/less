# Less is More

A macOS app that makes your spending and consumption visible. Drag in bills, receipts, and statements — Less is More extracts the details, categorizes your spending, and surfaces insights to help you consume less and waste less.

## Why Less is More exists

Most people have a vague sense of where their money goes, but the specifics hide across dozens of accounts, statements, and email receipts. The same is true for energy, water, and waste — you pay the bill and move on. Less is More pulls all of that into one place so you can actually see the patterns.

The philosophy is simple: you can't reduce what you can't see. Once your consumption is visible, the app helps you find the levers — subscriptions you forgot about, costs that crept up, waste you didn't realize you were producing.

## How it works

### 1. Get your documents in

Less is More accepts PDF files — the kind you already have:

- **Mail** — scan or photograph paper bills and statements (your phone's scanner produces PDFs)
- **Email receipts** — save as PDF from your email client, or use the built-in Gmail import
- **Statements** — download from your bank, utility, or service provider

Drag and drop PDFs onto the app window. You can also import via File > Import Documents or capture receipts with your Mac's camera.

### 2. AI-powered extraction

The app analyzes each document using AI to extract:

- Individual line items and amounts
- Vendor names and categories (groceries, utilities, subscriptions, etc.)
- Dates and billing periods
- Consumption types (money, energy, water, waste)

Processing runs on-device by default using Apple Intelligence. You can optionally configure Anthropic (Claude) or any OpenAI-compatible API in Settings for higher accuracy on complex documents.

### 3. Insights over time

As you add more documents, Less is More builds a picture of your consumption patterns and surfaces actionable insights:

- Spending trends by category and vendor
- Period-over-period comparisons
- Anomaly detection (unusual charges, cost increases)
- Reduction suggestions based on your actual data

The more data the app has, the sharper the insights become.

## Features

| Area | What it does |
|------|-------------|
| **Dashboard** | Spending overview with charts broken down by category and consumption type |
| **Documents** | Browse imported documents with extracted details and status |
| **Line Items** | Searchable list of every extracted charge across all documents |
| **Periods** | Month-by-month breakdown to track changes over time |
| **Categories** | Per-category deep dives showing vendors and trends |
| **Insights** | AI-generated observations and suggestions based on your data |
| **Gmail Import** | Connect your Google account to pull in email receipts directly |
| **Camera Capture** | Photograph physical receipts using your Mac's camera |

## Privacy

- All data stays on your machine, encrypted at rest (SQLCipher)
- AI analysis runs on-device by default — no data leaves your Mac unless you configure a cloud provider
- No accounts, no cloud sync, no tracking
- Your API keys are stored in the macOS Keychain

## Building

Less is More is a Swift Package Manager project targeting macOS 14+.

```sh
swift build              # debug build
swift build -c release   # release build
```

## Distribution

To create a signed, notarized DMG for distribution:

```sh
brew install create-dmg
./Scripts/create-dmg.sh                   # full build + sign + notarize
./Scripts/create-dmg.sh --skip-notarize   # build + sign only
```

The script builds a universal binary (arm64 + x86_64), signs with your Developer ID certificate, creates a DMG with drag-to-install layout, and optionally notarizes with Apple. See the script header for environment variable options.

## Project structure

```
Sources/Less/
  LessApp.swift              # App entry point, menus, window management
  Database/                  # SQLCipher database layer (GRDB)
  Models/                    # Data models (Document, LineItem, Vendor, etc.)
  Views/                     # SwiftUI views organized by feature
  ViewModels/                # View models for each major view
  Services/                  # PDF extraction, LLM providers, Gmail, camera
  Utilities/                 # Keychain, settings, debug logging
Resources/                   # App icon, entitlements
Scripts/                     # Icon rendering, DMG creation
Packages/GRDB.swift          # Local GRDB dependency (with SQLCipher)
```
