# Curio: Fact or Myth?

A few minutes a day of things you didn't know about the world. Swipe **Fact** or **Myth**, then read the story behind each one and dive into Wikipedia.

## Modes
- **Daily 10**: the same set for everyone each day, with a streak
- **Explore**: 20 topics (countries & cultures, food, laws & norms, languages, geography, science, space, human body, nature, psychology, history, wars, inventions, money, professions, maths, religions & beliefs, ethics & philosophy, games & sports, art & music)
- **World Passport**: you pick your home country, and Curio favours facts from everywhere else. Collect a stamp for each country.
- **Review mistakes**: facts you got wrong come back later (spaced repetition)
- **Time Machine (live)**: real events from Wikipedia's "On this day" feed. Which happened first?
- **Rabbit Hole (live)**: an endless feed of random Wikipedia articles, to read and save
- XP, levels (Curious → Living Encyclopedia), combos, saved collection, knowledge map

## Content
- `data/src/*.json`: 282 hand-curated facts and myths, each with an explanation, country tags and a Wikipedia article. Myths are deliberately common misconceptions.
- `tools/build-data.mjs` validates the sources and writes `facts.json` into `web/data` and `app/assets`:

```bash
node facts/tools/build-data.mjs
```

To add content, append entries to a source file (`r` country codes or `world`, `s` statement, `a` true/false, `e` explanation, `w` Wikipedia title) and rebuild.

The live modes use Wikipedia's public REST API (CC BY-SA, no key needed), so there's no limit on content.
