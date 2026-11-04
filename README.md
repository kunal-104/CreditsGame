# CreditsGame

Two products, each with a **website** (installable PWA, works offline) and a **Flutter app** (Android, iOS, web).

| Product | Website | Flutter app | What it is |
|---|---|---|---|
| **Sudoku Sensei** | [`sudoku/web`](sudoku/web) | [`sudoku/app`](sudoku/app) | Sudoku that teaches you, from your first digit to grandmaster techniques |
| **Curio** | [`facts/web`](facts/web) | [`facts/app`](facts/app) | Fact or myth? Surprising facts about the world, plus unlimited live Wikipedia modes |

## Run locally

Websites (any static server works):

```bash
npx serve sudoku/web
```

```bash
npx serve facts/web
```

Flutter apps (Flutter 3.47+):

```bash
cd sudoku/app && flutter pub get && flutter run
```

```bash
cd facts/app && flutter pub get && flutter run
```

See each product's README for how the content is generated.
