# Calora

**Persian-first nutrition and calorie tracker built with Flutter.**

Calora is a focused nutrition-tracking app designed to make daily food logging and calorie management simple for Persian-speaking users. It combines personalized calorie targets, a local Persian food database, daily tracking, historical reports, and offline-first persistence.

## Why I built it

The product started from a simple need: make calorie tracking faster and more practical for Persian food and everyday routines.

Instead of building a generic international tracker, Calora is designed around a Persian RTL experience, local food data, and separate calorie targets for **training days** and **rest days**.

The project was built and iterated with an **AI-assisted development workflow using OpenAI Codex + VS Code**.

## Core features

- Persian-first RTL interface
- Activation and onboarding flow
- Configurable calorie targets
- Separate training-day and rest-day targets
- Daily nutrition tracking
- Local Persian food database
- Nutrition history
- Detailed historical reports
- Settings and target management
- Offline local storage
- Background nutrition-day reconciliation
- Persian date/localization support

## User journey

```text
Activation
   ↓
Onboarding
   ↓
Set calorie targets
   ↓
Track today's nutrition
   ↓
Review daily progress
   ↓
View history & reports
   ↓
Adjust targets when needed
```

## Tech stack

- **Flutter / Dart**
- **Riverpod** for state management
- **Hive / Hive Flutter** for local persistence
- **Workmanager** for background reconciliation
- **intl** for localization/date formatting
- **shamsi_date** for Persian calendar support
- **Vazirmatn** for Persian typography
- Local JSON-based Persian food dataset

## Product architecture

The codebase separates the main product concerns into feature modules:

- **Activation**
- **Onboarding**
- **Nutrition**
- **History / reporting**
- **Settings**
- **Navigation**

Nutrition data is reconciled across app lifecycle and background execution so daily records remain consistent even when the application is reopened later.

## AI-assisted development

Calora is a working product project rather than a static prototype.

My development workflow included:

- Product-flow definition
- UX and state-model decisions
- AI-assisted implementation with OpenAI Codex
- Manual review and debugging in VS Code
- Local data-model iteration
- Background-task troubleshooting
- Testing and refinement of Persian RTL flows

I use AI as a **builder multiplier**: it speeds up implementation, but the product structure, acceptance criteria, testing, and final decisions remain deliberate.

## Run locally

Prerequisites:

- Flutter SDK
- Dart
- Android Studio / Android SDK or another Flutter-compatible environment

```bash
flutter pub get
flutter run
```

Quality checks:

```bash
flutter analyze
flutter test
```

## Data & privacy

Calora is designed around local-first storage. The food database and user nutrition records can operate without a cloud backend, and no production user secrets are committed to the repository.

## Portfolio context

Calora showcases how I approach a consumer growth/product problem from both sides: understanding the user journey and **shipping the actual product experience** with AI-assisted coding.

---

Built by **Davoud Abbasi**  
Growth marketer & AI-assisted product builder
