# game-names.json

The game names and Game Boy / Game Boy Advance details that Emura bundles, so it can recognise a game file.

- **Source:** [libretro-database](https://github.com/libretro/libretro-database), commit `fbeefcb46c2e1b20a7e2945f34a694a41b2d6f90` (its No-Intro DATs and metadat), by the libretro team and No-Intro.
- **Changes:** reshaped into one file keyed by each release's SHA-1 (3DS: product code), with details as `[developer, publisher, genre, year, players]` and genres mapped to Emura's own list. Built by `Scripts/build-game-names.py`.
- **Licence:** [Creative Commons Attribution-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-sa/4.0/), like its source. You may share and adapt it under the same licence.

This licence covers this data file only, not the Emura app.
