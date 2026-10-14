# 09 - Players, teams and the game database

Phase 1 RE spec, subsystem `players`. Covers:
- the roster database (players, squads, team ratings and roles);
- the team, kit, stadium and head tables;
- tournament schedule files;
- the match-time player model: fatigue/energy, injuries, substitutions, and the market rating/value.

Extractor: `tools/openrugby_tools/rosterdb.py`. Run it as `python -m openrugby_tools.rosterdb --src extracted/data.gob --out extracted/db`. It writes these files to `extracted/db/`:
- `players.json`
- `teams.json`
- `stadiums.json`
- `heads.json`
- `competitions.json`
- `schema.json`

Tests are in `tools/tests/test_rosterdb.py` and use synthetic data only.

**Labels.** Each claim is marked **[O]** observed, **[I]** inferred, or **[U]** unknown. Evidence is cited as an REA Evidence ID (`ev_...`), or as `LOCAL:<addr>` for offline disassembly with `.omc/research/rules/funcasm.py`, which inlines the SecuROM stolen instructions. Data-file evidence is given as the `data.gob` member hash.

**REA evidence used:**
- `ev_bea565bc580c7eee861ed2933217cc8b5543b2187a1b41395a5bfc1251e85896`: function naming on the repaired binary, sha256 aba7a647...
- `ev_6a365c0e3135099b9ba047c44658c1f563e9c5f97353fb7dfd7b333c876c3c06`: energy curve.
- `ev_314ded6f420dab8850cd2e3ac0fe426a7078f808e9603c6c87cccd0b90766198`: injury chance.
- `ev_9e712b90...`: the loader. Ghidra truncates it at a SecuROM trampoline, so the layout was read with `LOCAL:0x4d3070`.

## 1. Scope and entry points

| Address | Name | What it does | Conf. |
|---|---|---|---|
| 0x4d3070 | players_LoadDatabase | Loads `frontend/database/rugby0.0.14.0.rdf` (string 0x8ccdcc). Checks the version, reads three tables, rewrites team byte +0x5b as 6-x, then reads `xml/config/playermanager.xml`. | high |
| 0x5b2a30 / 0x5b7960 / 0x5b0440 | players_GetPlayerTable / GetTeamTable / GetCreatedTable | Return the player table (2000 x 100 B at 0x9fb2d0), the team table (143 x 104 B at 0xa2d0f0) and the created-player table (90 x 48 B at 0xa2c010). | high |
| 0x5b0450 | players_FindById | Linear search of the 2000 player records by u16 id. Returns NULL if not found. | high |
| 0x5b7840, 0x5b78b0 | players_FindTeamRecordById, players_GetTeamRolesById | Team lookup by the id at record +0x3c. The second returns a pointer to the role array at +0x40. | high |
| 0x5b7910, 0x5b8060 | players_InitTeamIds, players_RemovePlayerEverywhere | Set team[i].id = i. Remove a player id from every squad. | high/med |
| 0x557b80 | players_RestoreTeamSetPlayBytes | Copies team bytes +0x5c..+0x5f, for all 143 teams, back from a saved profile block. | med |
| 0x5b03f0, 0x571b00 | players_CreatedFindFreeSlot, players_CreatePlayerCommit | Create-player flow. 90 slots. The created slot index is stored in the player's head-id field, and flag bit 0x1000 is set in the u32 at +0x5c. | med/low |
| 0x5b0b70 | players_CalcMarketRating | Player market rating, built from position-weighted stats, ability bonuses and a key-stat multiplier (section 2.4). | high |
| 0x5b2640 | players_CalcMarketValue | Market value band 1..41, taken from the market rating. | high |
| 0x6558b0 -> 0x655480 | setpiece_PlayerAttrGet (named by the set-piece lead) | Stat getter by engine stat index (section 4.1). | high |
| 0x8bad50 | players_FatigueTunablesInit | Static initialiser for the fatigue constants (section 3). | high |
| 0x656190 | players_EnergyCurve | Energy E from Stamina and fatigue time. `ev_6a365c0e...` | high |
| 0x6563c0, 0x60fe20 | players_GetEnergyPercent, players_PlayerGetEnergyPercent | Energy percent, 9..100. | high |
| 0x656d10, 0x4c0540, 0x61c2f0, 0x61c840, 0x61c7c0 | players_TeamGet/Set/AddFatigueTime, players_TeamAddFatigueMinutes, players_TeamHalfTimeRecovery | Per-shirt fatigue timers on the team object. | high |
| 0x656510 | setpiece_AttrFatiguePenalty | Fatigue penalty applied to Passing, Tackling and Rucking. | high |
| 0x608b70 | players_PassQualityWithFatigue | Pass skill minus the fatigue penalty. | med |
| 0x656c10, 0x60b060, 0x60b470 | players_InjuryChance, players_ShouldInjure, players_InjuredStateEnter | Injury model. `ev_314ded6f...` | high/med |
| 0x618aa0, 0x61b8d0 | players_TeamHasFitReplacement, players_TeamFindFreeSubRecord | Replacement availability and the substitution log. | high/med |
| 0x61ada0 | players_TeamPossessionPercent | Possession percent (team +0x130). Shares the array base with the fatigue timers. | med |

All of these are named in REA and listed in `.omc/research/functions/players.tsv`.

## 2. Behaviour

### 2.1 Loading [O] (LOCAL:0x4d3070)

1. The u32 version is checked. Byte 3 and byte 2 must be 0 and byte 1 must be 0x0D. Otherwise the game logs "version on player database bad.." and still continues. The shipped file has version 0x00000D00.
2. 200 000 B are read into the player table: 2000 records of 100 B.
3. 14 872 B are read into the team table: 143 records of 104 B.
4. 4 320 B are read into the created-player table: 90 records of 48 B.
5. The total, 4 + 200 000 + 14 872 + 4 320 = 219 196 B, equals the decoded file size exactly.
6. For each of the 143 team records, the byte at +0x5b becomes 6 - byte.
7. `xml/config/playermanager.xml` is parsed. This is data.gob member `730eef3f`, which holds the kit and head tables.

### 2.2 Squads [O]/[I]

- **Slot index.** The team record index equals the team id (1..142). Slot 0 is unused. [O]
- **Squad size.** A squad has 30 player ids. [O]
- **Starters.** Slots 1..15 are the starting XV in shirt-number order. All 120 shipped squads match the position profile: 1 LHP, 2 HK, 3 THP, 4-5 locks, 6-7 flankers, 8 N8, 9 SH, 10 FH, 11-15 backs. [O]
- **Match-day squad.** The match-day team object holds 22 records indexed by shirt-1: 15 starters plus 7 bench players. [O]
- **Bench source.** Slots 16..22 of the DB squad are taken to be the bench and 23..30 the reserves. [I]
- **Dangling ids.** 25 squad ids are not in the player table. The game treats them as empty (players_FindById returns NULL). [O]/[I]

### 2.3 Fatigue and energy [O] (`ev_6a365c0e...`, LOCAL:0x6563c0, 0x61c2f0, 0x61c7c0, 0x632f10)

**Fatigue time.** Each team object keeps a float fatigue time per shirt, in match-clock seconds. It is stored at team+0x130+4*shirt.
- Every frame, players on the pitch (shirts 1..15) get `fatigue += dt_match`. [O]
- `dt_match` is the match-clock delta from the rules lead's `rules_AdvanceMatchClock` (0x632f10): `dt_real x 40 / half_minutes`. A full match is always 4800 match-seconds.
- At half time, every shirt (1..22) gets `fatigue = max(0, fatigue - 300)`. That is 5 match-minutes of recovery. [O]

**Energy E** (players_EnergyCurve), with Sta = the Stamina stat (record +0x36) and t = fatigue time:

$$s = \max\!\left(0, \frac{Sta - 40}{100 - 40}\right),\quad x = \mathrm{clamp}\!\left(\frac{t}{4800},0,1\right)^{2}$$
$$E_{hi} = 100,\quad E_{lo} = 40 + (90-40)\,s,\quad E = \mathrm{clamp}\big(E_{lo} + (E_{hi}-E_{lo})(1-x),\ 40,\ 100\big)$$

**Energy percent** (players_GetEnergyPercent):

$$P = \mathrm{trunc}\ \mathrm{clamp}\!\left(9 + 91\,\frac{E-40}{100-40},\ 9,\ 100\right)$$

So a player with Stamina at or below 40 ends a full match at P = 9. A player with Stamina 100 ends it at about P = 85.

**Stat penalty** (setpiece_AttrFatiguePenalty), subtracted from the stat. Integer division is used.

| Engine stat | Penalty |
|---|---|
| idx 6 Passing | (100-P)/3 |
| idx 9 Tackling | (100-P)/2 |
| idx 11 Rucking | (100-P)/2 |
| any other stat | 0 |

**Where the penalty is applied** (observed in each case):
- pass quality 0x608b70;
- ruck strength 0x655900;
- ruck contest 0x659760.

The stat getter itself does not apply fatigue. [O]

**Other uses of energy:**
- **Ruck AI.** In 0x660980, energy below 40, with Discipline < 50 or Aggression > 80, gives a 2.5 % chance of a maximal over-commit (intensity 110). [O]
- **Interval function 0x610090.** It computes $60/(25 - 7P/100) + U(0,0.5)$ s. The AI lead named it as a big-hit interval. A breathing or puff cadence is equally plausible. [I]

### 2.4 Market rating and value [O] (LOCAL:0x5b0b70, 0x5b2640)

These are used by World League economics: salaries and the transfer screens. The callers are 0x51ccb0 and 0x5225b0.

**Rating** (primary position only):

$$R = \mathrm{trunc}\Big(\big(\textstyle\sum_i w_{pos,i}\, stat_i + \sum_{abilities} bonus\big)\cdot K_{pos}\cdot M_{pos}\Big)$$

- **Weights $w$.** Listed in `rosterdb.RATING_WEIGHTS`. Examples:
  - props: Scrummaging 0.35, Strength 0.2, (lb-100) x 0.06, ...
  - wing: Speed 0.35, Acceleration 0.15, Agility 0.12, ...
  - Locks and No. 8 add (height_in-60) x 0.125.
- **$K_{pos}$:**

  | Position | $K_{pos}$ |
  |---|---|
  | prop | 0.3 |
  | hooker | 0.35 |
  | lock | 0.4 |
  | flanker | 0.45 |
  | No. 8 | 0.4 |
  | scrum half | 0.4 |
  | fly half | 0.5 |
  | wing | 0.5 |
  | centre | 0.4 |
  | full back | 0.4 |

- **Ability bonuses:**

  | Ability | Bonus |
  |---|---|
  | GoalKicker | +35 |
  | Scoring | +25 |
  | BallWinner | +20 |
  | Playmaker | +20 |
  | Passer | +15 |
  | CrashBall | +10 |
  | DefensiveOrganisation | +10 |
  | Jumper | +10 |
  | Tackling | +10 |
  | TacticalKicking | +10 |
  | Scrummager | +5 |
  | TackleBreaker | +5 |
  | Command | +20 |

- **Key-stat multiplier $M$.** Forwards use 1. For backs a table is indexed by a key stat:
  - SH: key stat Passing; table covers 71..90; above 90, M = 2.0.
  - FH: key stat Kicking; table covers 74..85; above 85, M = 2.0.
  - WG: key stat Speed; table covers 85..100.
  - CE: key stat Speed; table covers 85..100.
  - FB: key stat floor((Kicking+Speed)/2); table covers 71..85; above 85, M = 1.7.
- **Exceptions:**
  - A player whose id is in the 30-entry static list at 0x993508 skips $M$ (`rosterdb.UNRATED_PLAYER_IDS`; all 30 are low-rated roster players). players_CalcMarketValue checks the same list first and returns 1. The purpose of the list is unknown.
  - A 20-entry career override list (career +0xdc4, stride 12) replaces R outright.
  - Position 0 returns 0.
- **Shipped range.** R runs from 10 to 157.

**Value band** (players_CalcMarketValue):

| R | Value |
|---|---|
| below 16 | 1 |
| below 18 | 2 |
| below 20 | 3 |
| below 23 | 4 |
| below 26 | 5 |
| below 28 | 6 |
| below 31 | 7 |
| below 33 | 8 |
| 33 or more | min(41, 9 + floor((R-33)/2)) |

The extractor exports both numbers as `market_rating` and `market_value`.

### 2.5 Injuries [O] (`ev_314ded6f...`, LOCAL:0x60b060, 0x60b470)

**When it is checked.** players_ShouldInjure is called:
- at ruck end (0x662550);
- from `Player::OnGroundState` (0x6942b0), i.e. after being tackled.

**When it returns false:**
- the player is the special player returned by 0x429fa0 (the human-controlled player [I]);
- 0x6bac10 reports training/practice [I];
- 0x62db80 vetoes it;
- the team has no fit replacement (players_TeamHasFitReplacement);
- the player's current action vetoes it.

**Debug override.** If qadebug `always_injured` (byte 0x9bee3c) is set, it returns true.

**Probability.**

$$p_0 = (4 - IR)\times 0.001,\qquad
f = \begin{cases} \lfloor v/60\rfloor & v\le 60 \\ 1 + 9\,\frac{v-60}{40} & v>60\end{cases}$$

- IR is the injury-resistance level 0..3, from ability bits 13-15.
- v is the match-settings byte at +0x22e. It is the injury-frequency option, 0..100 [I].
- So every v below 60 disables injuries, and v = 100 gives 10x.
- Then p = p0 x f.
- If the current animation id is 0x532d, add 0.3.
- If the animation flag is set, multiply by 15.
- Clamp p to [0, 1] and draw a Bernoulli.

**Injured state** (players_InjuredStateEnter). The severity starts as slight (1).
- If the team has a pending-request slot free (0x61cfc0):
  - animation 0x532d gives serious with p = 0.15;
  - otherwise there is a 50 % chance of serious (2).
- If the team has no free substitution record, the injury is forced to slight.
- **Serious:** the match record sets +0x61 = 1 (injured). This leads to replacement, via the Serious Injury Controller and GEVENT_INJURY_SUB_SELECTED.
- **Slight:** Stamina in the match copy is set to 0 and the fatigue time to 4800. The player stays on at energy percent 9 for the rest of the match.
- Game event 0x8e is posted in both cases.
- Career mode reports weeks out ("%s is injured and will be out for %d week%s"). The length rule was not traced. [U]

### 2.6 Substitutions [O]/[I]

- **Fit replacement.** A fit replacement is a bench shirt 16..22 whose match record has +0x61 == 0 and a high nibble of 0 in +0x15. [O]
  - In the DB, +0x15 holds only pos3 in its low nibble.
  - The high nibble is therefore a runtime "already used/replaced" flag. [I]
- **Substitution log.** The team match data has 7 substitution records at +0xbfc, stride 8. Once all 7 are used, players_TeamFindFreeSubRecord returns NULL. This is the 7-replacement limit. [O]/[I]
- **Not traced:** the user and CPU substitution policy ("Substitution Controller" 0x4a2e8f, GEVENT_SUBSTITUTION_REQUESTED). [U]

### 2.7 Player switching (human control)

Not covered. It belongs to the input/AI leads.

## 3. Constants and tunables

| Name | Value | Unit | Where | Evidence |
|---|---|---|---|---|
| RdfVersionByte1 | 0x0D | - | loader check | LOCAL:0x4d311c |
| PlayerSlots / TeamSlots / CreatedSlots | 2000 / 143 / 90 | records | loader | LOCAL:0x4d3128.. |
| PlayerRecordSize / TeamRecordSize / CreatedRecordSize | 100 / 104 / 48 | bytes | loader, lookups | LOCAL:0x5b0450, 0x5b7840, 0x5b03f0 |
| SquadSize / MatchdaySquad / Bench | 30 / 22 / 7 | players | team records, 0x618aa0 | LOCAL |
| MaxSubstitutionRecords | 7 | subs | 0x61b8d0 | LOCAL |
| FatigueStaminaFloor | 40 | stat points | energy curve, a320c0 | LOCAL:0x8bad50 |
| EnergyMax | 100.0 | energy | a320c4/a320c8 | LOCAL:0x8bad50 |
| EnergyMinAtLowStamina | 40.0 | energy | a320cc | LOCAL:0x8bad50 |
| EnergyMinAtFullStamina | 90.0 | energy | a320d0 | LOCAL:0x8bad50 |
| FatigueExponent | 2.0 | - | a320d4 | LOCAL:0x8bad50 |
| FatigueFullTime | 4800 | match-seconds | 0x656190, 0x421ab0 | `ev_6a365c0e...` |
| HalfTimeRecovery | 300 | match-seconds | 0x61c7c0 | LOCAL |
| EnergyPercentFloor | 9 | % | 0x6563c0 | LOCAL |
| FatiguePenaltyDivisor Passing / Tackling / Rucking | 3 / 2 / 2 | - | 0x656510 | LOCAL |
| InjuryBaseChancePerIRStep | 0.001 | probability | 0x656c10 | `ev_314ded6f...` |
| InjurySliderNeutral / Max / MaxMultiplier | 60 / 100 / 10 | option units | 0x656c10 | `ev_314ded6f...` |
| InjurySpecialAnimBonus / FlagMultiplier | +0.3 / x15 | probability | 0x60b060 | LOCAL |
| SeriousInjuryChance (normal / special anim) | 0.5 / 0.15 | probability | 0x60b470 | LOCAL |
| BallWinnerRuckBonus | +30 | ruck strength | 0x655900, 0x659760 | set-piece lead |
| Market K, weights, bonuses, key tables | section 2.4 | - | 0x5b0b70 | LOCAL |
| Unrelated, also set by 0x8bad50 | bool 0, 0, int 80 | - | a320b4/b8/bc | LOCAL (meaning [U]) |

## 4. Data structures

### 4.1 Player record (100 B; identical to the in-memory block at player+0x10) [O]

Verified byte for byte against the developer roster dump `453779c3...txt` for all 2059 name-unique rows, covering every attribute, height, weight, positions, nation, abilities, injury resistance and head id.

| Off | Type | Field | Range / meaning |
|---|---|---|---|
| 0x00 | u16 | player_id | 1..32767. The table is sorted descending. Ids match World League swaps. |
| 0x02 | u16 | commentary_name_id | Surname speech id (dat_eng `NNNN_<Surname>.dat`). 0 = none. 1342 of 1904 players have one. [O] by name match |
| 0x04 | char[16] | name | cp1252 "I.Surname". A '^' suffix marks some stars (meaning [U]). |
| 0x14 | u8 | pos1 (low nibble), pos2 (high nibble) | Position enum (section 9) |
| 0x15 | u8 | pos3 (low nibble) | The high nibble is runtime only (section 2.6) |
| 0x16 | u16 | weight | lb - 100 |
| 0x18 | u32 | nationality bitmask | Bit = nation (section 9). Exactly one bit is set in the shipped data. |
| 0x1c | u8 | height | in - 60 |
| 0x1d / 0x1e / 0x1f | u8 | birth year-1900 / month / day (bits 0-4) | Bits 5-7 of 0x1f are [U] (4 in 99 % of records) |
| 0x20 | u8 | player_type | PlayerTypes 0..10 (section 9). Correlates with position. [I] by enum match |
| 0x21..0x32 | u8 x18 | Attack, Defense, Speed, Acceleration, Agility, Handling, Passing, Kicking, KickingPower, GoalKicking, Tackling, Strength, Rucking, Scrummaging, Hooking, LineOuts, Discipline, Aggression | 0..100 |
| 0x33..0x35 | u8 x3 | reserved | Always 0. These are probably XML attributes SetPlaySuccess, CrashBallRating and GapDefense. [I] |
| 0x36..0x3b | u8 x6 | Stamina, Consistency, Temperament, Creativity, Bravery, Fitness | 0..100. Fitness is mostly 100 or 50. |
| 0x3c, 0x3d | u8 | fitness_2, fitness_3 | Copies of Fitness, reachable as engine idx 23/24 ([U] meaning) |
| 0x54 | u16 | abilities | Bits 0..12: Command, Passer, Playmaker, Scoring, GoalKicker, TacticalKicking, CrashBall, TackleBreaker, Tackling, BallWinner, DefensiveOrganisation, Scrummager, Jumper. Bits 13..15: InjuryResistance 0..3 (higher = fewer injuries). |
| 0x56..0x59, 0x5c..0x5f | - | unknown | [U]. 0x5c bit 12 of the u32 = created player. |
| 0x5a | u16 | head_id | Face model / `playermanager.xml` location. For created players: the created slot. |
| 0x61 | u8 | runtime: injured | Match copy only |

Engine stat index (getter 0x6558b0):
- 0..7 map to offsets 0x21..0x28.
- 8..16 map to 0x2a..0x32.
- 17..24 map to 0x36..0x3d.
- KickingPower (0x29) is read directly (goal kick 0x7418c0).

### 4.2 Team record (104 B) [O] except where marked

| Off | Type | Field | Notes |
|---|---|---|---|
| 0x00 | u16 x30 | squad | Player ids. Slots 1-15 = XV by shirt. |
| 0x3c | u32 | team_id | Equals the slot index |
| 0x40 | u16 x7 | roles | Slot 0 = captain [O] (Pichot, Gregan, Vickery, Umaga). Slot 1 = vice-captain [I] (McCaw for NZ). Slots 2-6 = long goal kicker, short goal kicker, long punter, short punter, kick-off taker [I] (Designations enum order). |
| 0x4e | u8 x10 | ratings 0..100 | Labels [I] from UI strings 112-121: Attacking, Defending, Scrummaging, Line-outs, Loose, Kicking, Technique, Stamina, Flair, Overall. Placeholder teams have all 5s. |
| 0x58 | u8 x8 | tactics | [U]. Exported raw as stored in the file (the loader's 6-x on +0x5b is NOT applied, and build_rdf writes the raw value back). Ranges: 0..10, 0..2, 0..1, 0..5 (engine stores 6-x), then four 0..13 bytes restored from the profile (set-play assignments [I]). |
| 0x60 | u8 | home_stadium | Stadium id (stadium XML Index). 0 = none. |
| 0x61..0x67 | - | zero | |

### 4.3 Side tables (data.gob members)

| Member | Content | Key fields |
|---|---|---|
| `be2970b0...xml` (hbstool `team`, 116 rows) | Team table | Index (= team id), Active, Type, CodeId, FeGroup (international/super14/european/representative), StringTableId (name in the .english table), TeamName, Abbreviation, HomeColour/AwayColour (RGBA), Logo |
| `28d3f14b...xml` | Older team table | Different ids from 60 upward; not used by the extractor. Adds TeamNameShort and FlagCharacter. |
| `730eef3f...xml` = `xml/config/playermanager.xml` | `teams/team(name, location, id)/kit(name, location, collar)` and `players/player` | Heads: location = head id, name, skin 1..4, med/low hair style, eartape, scrumCap, gloves. 759 heads. Not well-formed XML (attributes run together). |
| `119ba3f3...xml` | Stadium table (60) | Index, Active, CodeId, StadiumName, StringTableId, FileName, City/Country (string ids), HomeTeam, FeGfxPackage, intro/anthem scripts, `camera` indices, `environment` (type day/night/overcast, breath, DirtType, ProbabilityDirt, ProbabilityPrecipitation) |
| `119ba3f3...csv` | Legacy stadium list (104 rows) | Has Capacity and City. Its index space differs from the XML. |
| `20f6cf7c...xml` | Stadium render config (42) | id -> asset folder and enum. Fills in ids missing from the XML (e.g. 15 Stoop). |
| `*.rsg` (19) | Tournament schedules | `tournament(name)`, `teams/team(id, alias, Index = team id)`, `locations/location(id, alias, Index)` (Index space unverified [U]), `round/pool/game(location, hometeam, awayteam, year, month, day, environment)` |
| `2de97b25...xml` | World League config | Base balances, starting swaps (player ids). Owned by the modes lead. |
| `a2ff503e/e28cf5be/44a7f679/00001aaa/258aa7ca/e513890` xml | Enum tables | PlayerAttributes, Positions, Skills, PlayerTypes, Designations, FormPositions |
| `453779c3...txt` | Developer roster dump (72 teams) | Superseded by the rdf. It confirms the field meanings. |
| `c21f969b...match` | Legacy 88-byte player records (NZ squad) | Older layout; not used [I] |

## 5. Mod hooks

- **Whole database.** The rdf is fixed-size. A mod rebuilds it with `rosterdb.build_rdf`, or, better, the Godot build reads `players.json`/`teams.json` directly.
- **Player data.** Per-player stats, abilities, injury resistance, positions, player type, head id and commentary name id.
- **Squad data.** Squads (30), the role slots (captain and kickers), team ratings and the home stadium.
- **Fatigue tunables.** FatigueStaminaFloor, the energy min/max values, FatigueExponent, FatigueFullTime, HalfTimeRecovery and EnergyPercentFloor. Also which stats receive a fatigue penalty, and their divisors.
- **Injury tunables.** InjuryBaseChancePerIRStep, the slider mapping, the serious-injury chance and the always-injured debug flag.
- **Substitutions.** The bench size and the substitution limit (7).
- **Market rating.** Weights, K, bonuses and key tables, used by career economy mods.

## 6. Acceptance tests (GDScript-assertable)

1. Loading a DB whose version u32 has byte 1 != 0x0D logs a version error.
2. The player record for id 28321 decodes to:
   - name "A.Pichot^", Scrum Half;
   - 175 cm (69 in), 77 kg (171 lb) (the dump truncates: cm = int(in x 2.54), kg = int(lb x 0.454545));
   - born 1974-08-22;
   - Passing 94, KickingPower 82;
   - abilities {Passer, Playmaker, DefensiveOrganisation}, InjuryResistance 2.
3. Team 13 (New Zealand):
   - starting XV shirt 10 is D.Carter;
   - captain role is T.Umaga;
   - home stadium is 51 (Dunedin);
   - ratings [92, 90, 84, 82, 90, 89, 100, 90, 84, 94].
4. EnergyPercent(Sta = 100, t = 0) == 100.
5. EnergyPercent(Sta = 40, t = 4800) == 9.
6. EnergyPercent(Sta = 100, t = 4800) == 84. Working: E = 90, so P = 9 + 91 x 50/60 = 84.83, truncated to 84.
7. After half time, a player's fatigue time drops by 300 and never below 0.
8. With energy P = 70: the passing penalty is 10, the tackling penalty is 15, and every other stat's penalty is 0.
9. InjuryChance(IR = 3, slider = 60) == 0.001.
10. InjuryChance(IR = 0, slider = 100) == 0.04.
11. InjuryChance(any IR, slider = 59) == 0.
12. A slight injury sets energy to 9 % for the rest of the match. A serious injury flags the player for replacement.
13. No eighth substitution is possible.
14. A scrum half with Passing 91, only the Passer ability and every other stat 0 has market rating 36. Working: (0.33 x 91 + 15) x 0.4 x 2.0 = 36.02, truncated to 36.
15. Market value(33) == 9.
16. Market value(97) == 41.

## 7. Open questions / unknowns

- `unk_1cf3fe5ee3698a3c81680f6f57314f5d8255a8404057851e8522589ea66b6622`: the team rating labels/order, and the 8 tactic bytes, including where they are copied into the runtime team (CRugbyTeam +0x58 attack style, teamdata +0xbca, +0xbd8..bda set-play slots, according to the AI lead).
- `unk_1bbb1424c9b7b883e7d3a8703782387ce0e85284f405207bce81b34a8561769c`: the unknown player bytes 0x56..0x59 and 0x5c..0x5f, the top bits of 0x1f, fitness_2/3, and the high nibble of 0x15.
- Not traced:
  - form/morale application in matches (the Form XML grades, attribute bonus AP 7 .. D -5);
  - the career injury length in weeks;
  - the CPU substitution policy;
  - the created-player 48-byte layout;
  - the meaning of the 30-entry list at 0x993508.
- The rsg `location Index` space does not match the stadium XML ids (e.g. Calvisano -> 36).
- The '^' name suffix.

## 8. Confidence summary

- **High:**
  - rdf file layout and all three table sizes;
  - every player field verified against the dev dump;
  - squad and team-id structure, captain slot and home stadium;
  - the fatigue/energy model and constants;
  - the injury probability formula;
  - the market rating and value formulas;
  - the extractor output.
- **Medium:**
  - roles slots 1-6;
  - the 7-substitution limit;
  - slight/serious injury semantics;
  - player_type;
  - commentary name id (75 % exact name match, the rest are sound-alikes);
  - the set-play bytes.
- **Low / unknown:**
  - team rating labels;
  - tactic bytes;
  - the remaining unknown player bytes;
  - form, the substitution AI and player switching (not covered).

## 9. Answers for implementation (S1 team)

**(1) Attribute list** (stored ids = record offsets; every value is a u8, 0..100; engine idx = getter index):

| Engine idx | Attribute | Off | Meaning / gameplay use |
|---|---|---|---|
| 0 | Attack | 0x21 | General attacking ability (rating) |
| 1 | Defense | 0x22 | General defensive ability |
| 2 | Speed | 0x23 | Top speed. Key stat for WG/CE/FB rating. |
| 3 | Acceleration | 0x24 | |
| 4 | Agility | 0x25 | |
| 5 | Handling | 0x26 | |
| 6 | Passing | 0x27 | Pass quality, minus a fatigue penalty of (100-P)/3 |
| 7 | Kicking | 0x28 | Kick accuracy (goal kick base accuracy) |
| - | KickingPower | 0x29 | Kick power (goal-kick power stat), read directly |
| 8 | GoalKicking | 0x2a | Place kicks |
| 9 | Tackling | 0x2b | Fatigue penalty (100-P)/2 |
| 10 | Strength | 0x2c | Ruck strength term Strength/5 |
| 11 | Rucking | 0x2d | Ruck strength base. Fatigue penalty (100-P)/2. Ruck AI category (>=90, >=80). |
| 12 | Scrummaging | 0x2e | |
| 13 | Hooking | 0x2f | |
| 14 | LineOuts | 0x30 | |
| 15 | Discipline | 0x31 | Ruck AI infringement gate (<50) |
| 16 | Aggression | 0x32 | Ruck strength Aggression/20. Ruck AI gate (>80). |
| 17 | Stamina | 0x36 | Fatigue curve (section 2.3) |
| 18 | Consistency | 0x37 | |
| 19 | Temperament | 0x38 | |
| 20 | Creativity | 0x39 | FH AI thresholds 60/80 (AI lead) |
| 21 | Bravery | 0x3a | Ruck strength Bravery/20 |
| 22 | Fitness | 0x3b | 50 or 100 mostly. Use [U]. |
| 23, 24 | Fitness2, Fitness3 | 0x3c, 0x3d | [U] |

- **Abilities.** 13 boolean flags plus InjuryResistance 0..3 (section 4.1).
- **Physical.** Height in inches (165-208 cm in the data). Weight in lb (68-140 kg).

**(2) Positions.** The position enum in player records:

| Id | Position |
|---|---|
| 0 | None |
| 1 | Loosehead Prop |
| 2 | Hooker |
| 3 | Tighthead Prop |
| 4 | Second Row |
| 5 | Blindside Flanker |
| 6 | Openside Flanker |
| 7 | Number Eight |
| 8 | Scrum Half |
| 9 | Fly Half |
| 10 | Wing |
| 11 | Centre |
| 12 | Full Back |

Shirt and slot numbers (the Positions XML Index is shirt-1):

| Shirt | Slot |
|---|---|
| 1 | LH Prop |
| 2 | Hooker |
| 3 | TH Prop |
| 4 | Second Row 1 |
| 5 | Second Row 2 |
| 6 | Blindside |
| 7 | Openside |
| 8 | No. 8 |
| 9 | Scrum Half |
| 10 | Fly Half |
| 11 | Wing 1 (left [I]) |
| 12 | Inside Centre |
| 13 | Outside Centre |
| 14 | Wing 2 (right [I]) |
| 15 | Full Back |
| 16-22 | Replacements (match-day bench) |
| 23-30 | Squad reserves (not in the match) |

Positions collapse to 10 "form positions": PROP, HOOKER, SECONDROW, FLANKER, NUMBEREIGHT, SCRUMHALF, FLYHALF, CENTRE, WINGER, FULLBACK.

**(3) Kits.** The only kit data is in `playermanager.xml`. Each team has 2 kits, with fields:
- name: Home/Away or Main/Alternate;
- location: texture folder `homekit` / `awaykit`;
- collar: style A, BWide or CWide (37 / 7 / 18 teams).

Team colours are HomeColour and AwayColour, as RGBA in the team table. There are no pattern-type fields. Patterns live in the kit textures (FSH; see `02-fsh-textures.md`).

**(4) Pitch dimensions.** None are stored in the roster, team or stadium tables, or in the XML tunables. Drill data gives only indirect values:
- the touchline is at x = ±33.65 m (DropGoalDrill comment);
- goal posts are 5.6 m wide, at z ≈ 50 m from halfway (drop-goal zone centre at 52.8 m, 2.8 m behind the posts);
- that is consistent with a 100 m field of play.

The shared physics constants specify an in-goal depth of 14.1 m (dead-ball line at |z| = 64.1 m); see `docs/re/06-physics.md` §2.1. This replaces the earlier roster-side statement that the depth was not found. The pitch constant is observed, while any per-stadium variation remains unknown. [O/U]

## 10. Godot Resource mapping proposal

```
PlayerProfile (Resource)
  id:int, name:String, commentary_name_id:int, head_id:int
  positions:PackedInt32Array (enum Position, up to 3)
  height_cm:int, weight_kg:int, nationality:StringName, birth_date:Dictionary{y,m,d}
  player_type:int (PlayerType)
  stats:Dictionary[StringName,int]  (the 24 attributes above, 0..100)
  abilities:int (bitmask Ability), injury_resistance:int (0..3)
  appearance:PlayerAppearance  (skin, hair_med, hair_low, ear_tape, scrum_cap, gloves)
Team (Resource)
  id:int, name, short_name, abbreviation, code_id, type, group, active:bool, logo
  home_colour:Color, away_colour:Color, kits:Array[Kit], home_stadium:Stadium
  squad:Array[int] (30; [0..14] XV by shirt, [15..21] bench, [22..29] reserves)
  roles:Dictionary {captain, vice_captain, long_goal_kicker, short_goal_kicker,
                    long_punter, short_punter, kickoff_taker} -> player id
  ratings:Dictionary (10 labels, 0..100), tactics:PackedByteArray (8, raw until decoded)
Kit (Resource)
  name:String, texture_set:String (homekit/awaykit), collar:StringName (A/BWide/CWide)
Stadium (Resource)
  id, code_id, name, file_name, city, country, home_team, capacity (from legacy CSV)
  intro_script_anthem, intro_script_normal, cameras:PackedInt32Array
  environment: {time_of_day, breath, dirt_type, p_dirt, p_precip}
FatigueModel (Resource, tunables section 3)
InjuryModel (Resource, tunables section 3)
Competition (Resource) : name, teams[], locations[], rounds[pools[games[]]]
```

`rosterdb.py` exports exactly these fields, so a Godot import script can map the JSON one to one.
