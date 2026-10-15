# S3 independent test inventory

Status: test-author handoff for [S3 rules/referee spec](S3-rules-referee.md). The cases derive from
RE 05 §§2–7 and the applicable S1/S2 lifecycle contracts, not from implementation. Names below are
test IDs, not required GDScript file or function names. Use typed fixtures and test-owned S2/S4
fakes; do not inspect production implementation to decide expected results.

## Test fixture contract

- Construct matches through S1's `MatchConfig`, `MatchFlowConfig`, `RulesConfig`, seeded `MatchSim`
  and `SimSystem` lifecycle. Use the reviewed S1 public test API for result construction. Keep
  separate law observations, expected report, score, restart award and committed output assertions.
- S2 observations must use the frozen typed observation value agreed under S3 spec §3. Until it is
  documented, these cases are design inventory only; no test may fabricate an undocumented S2
  result shape.
- Test and implementation vectors use S1's canonical frame. Convert an RE value with
  `(x_S1, y_S1, z_S1) = (z_RE, y_RE, x_RE)`; preserve signs and directions. Thus the RE examples
  `z_RE=6`, `z_RE=15`, `z_RE=-20` and `z_RE=+10` are S1 `x=6`, `x=15`, `x=-20` and `x=+10`.
  The touch crossing itself is on the configured S1 `z` boundary.
- S4 results use test-owned typed values after the S3/S4 interface is agreed. Do not instantiate
  set-piece scenes or depend on animation.
- Freeze one seed per random-path fixture. For probability logic, test pure threshold boundaries
  with explicit roll values where the implementation exposes a pure decision function, and use a
  deterministic multi-seed conformance set for full paths. Do not assert an exact referee speech or
  presentation variant.
- For every S3 event-producing case, assert no event is visible before commit, exactly one ordered
  event/award after commit, and exact state restoration after injected checked failure and retry.
  Run each applicable gameplay case through direct tick and replay and compare detached outputs and
  S3 snapshots.

## A. Report, decision and transaction behavior

| ID | Setup / action | Expected result |
|---|---|---|
| S3-RPT-01 | Submit an unhandled report at match time `t`. | The accepted report is stamped `t`; caller-supplied non-empty source time is preserved. |
| S3-RPT-02 | Submit while referee is inactive. | No whistle, award, score or committed event; rule state unchanged. |
| S3-RPT-03 | Submit a report while quick option is pending and untaken. | The quick-option controller receives the report; ordinary stoppage is not awarded yet. |
| S3-RPT-04 | Submit a report which must go back to stored advantage; then complete the tick. | Original mark/report is awarded once and advantage clears. |
| S3-RPT-05 | Inject failure after report resolution but before tick commit. | No event escapes; report, restart, score, advantage, RNG, snapshot and pending outputs equal pre-tick state. Retry commits one event batch. |
| S3-RPT-06 | Unknown decision or restart enum enters mapping. | Explicit unresolved/error result; no fallback kick-off or fabricated restart. |

## B. Scoring and kick restarts (RE 05 T-01, T-13)

| ID | Setup / action | Expected result |
|---|---|---|
| S3-SCORE-01 | Counters: 2 tries, 1 conversion, 1 penalty goal, 1 drop goal. | Total is `2×5 + 2 + 3 + 3 = 18`. |
| S3-SCORE-02 | Valid try by onside team A, no opposing advantage. | Team A +5 and one try; touchdown event; conversion award. |
| S3-SCORE-03 | Try while team B owns advantage. | Return to stored offence; no try or conversion award. |
| S3-SCORE-04 | Offside attacker grounds ball. | Offside decision replaces try; no points. |
| S3-SCORE-05 | Team A penalty try against team B. | Team A +5, try counter +1, S1 mark `x_S1=+50` (RE `z_RE=+50`), whistle and conversion award. Kicker identity is not asserted. |
| S3-SCORE-06 | Successful conversion / penalty goal / drop goal by A. | Add 2 / 3 / 3 respectively; kick-off award to B; correct score/result event once. |
| S3-SCORE-07 | Missed conversion; missed drop goal dead in-goal; missed penalty goal dead in-goal. | Kick-off; 22 drop-out; inferred 22 drop-out respectively, with inferred status visible for the last case. |
| S3-SCORE-08 | Team B grounds in its own in-goal after the last touch/kick by A. | Decision 22 drop-out (reason `0x2d`); last-touch subcases not resolved by RE remain separate unresolved inputs. |

## C. Ball in touch and restart selection (RE 05 T-14–T-17)

Use direction A `+x_S1` (= `+z_RE`); use configured S1 `z` touchline geometry. Assert awarded side, mark, restart kind,
and S4 throw/feed team separately.

| ID | Setup / action | Expected result |
|---|---|---|
| S3-TOUCH-01 | Kick-off crosses touch with S1 length position `|x_S1|=6` (RE `|z_RE|=6`). | Centre scrum to non-kicking team. |
| S3-TOUCH-02 | Kick-off goes on full at S1 `x_S1=15` (RE `z_RE=15`), then after bounce at same crossing. | On full: centre scrum. Bounced: line-out at crossing to non-kicking side. |
| S3-TOUCH-03 | 22 drop-out goes out on full, then bounced. | On full: scrum at kicking side's 22; bounced: line-out at crossing; non-kicking side restarts. |
| S3-TOUCH-04 | Team A penalty kick from S1 `x_S1=+30` (RE `z_RE=+30`) crosses touch. | Line-out at crossing; team A throws. |
| S3-TOUCH-05 | Open-play kick from outside own 22 at S1 `x_S1=-20` (RE `z_RE=-20`), crossing touch at length `x_S1=+10` (RE `z_RE=+10`); test on-full and bounced variants. | On full: no-gain line-out at `x_S1=-20`, set-no-gain event. After a bounce: line-out at crossing, touch-kick-gain event. |
| S3-TOUCH-06 | Open-play kick from S1 `x_S1=-35` (RE `z_RE=-35`) after both kick origin and receive/take are in own 22, crossing at S1 `x_S1=+10` (RE `z_RE=+10`). | Line-out at crossing and touch-kick-gain event. |
| S3-TOUCH-06B | Open-play kick starts in own 22 but the ball was received/taken outside it before the kick. | Do not grant the own-22 gain exception; decision follows the outside-own-22 rules. |
| S3-TOUCH-07 | Carried ball goes into touch. | Line-out at crossing to side that did not carry out. |
| S3-TOUCH-08 | Goal kick type 5/6 goes into touch. | Observed goal-kick-miss handler and kick-off decision; do not assert unresolved subpath beyond documented behavior. |
| S3-TOUCH-09 | Change stadium touchline width and repeat boundary crossing. | Detection follows geometry resource; no hard-coded width. |
| S3-TOUCH-10 | Kick-off crossing at exactly 10 m from halfway. | Verify source's strict `< 10` condition: not the less-than-10 centre-scrum branch. Remaining branch follows full/bounce result. |

## D. Pass law, knock-on and offside (RE 05 T-21–T-26)

| ID | Setup / action | Expected result |
|---|---|---|
| S3-LAW-01 | Team A attacks `+x_S1` (= `+z_RE`); throw length component `+0.02 m/s`. | Forward-pass report, scrum to other side, 2 s whistle delay. |
| S3-LAW-02 | Components `-0.001 m/s` and `+0.005 m/s`; then exact `+0.01` and `+0.010001`. | First three are legal; only value strictly over 0.01 toward attack is forward. |
| S3-LAW-03 | Horizontal throw speed 7 m/s and would-be forward component; then 8 m/s. | Assist bends component to -0.01 m/s; boundary remains `<= 8`. |
| S3-LAW-04 | Faster forward pass at each documented option level 0–5. | Chance table `[0,.5,.6,.7,.8,.9]` is used; option field stays injected/provisional, not UI-derived by guess. |
| S3-LAW-05 | Team A drops at S1 `x_S1=0`, ball bounces and moves 0.11 m forward before B holds; then 0.10 m / 0.05 m. | First is knock-on with advantage to B; equality/below threshold is not. |
| S3-LAW-05B | Team A drops at S1 `x_S1=0`, ball bounces, then B picks it up at S1 `x_S1=0.5`; repeat with A picking it up. | First is a knock-on played with advantage to B; same-team pickup is an immediate scrum to B. |
| S3-LAW-06 | Dropper re-gathers before bounce; tracked pass later bounces. | No knock-on from either path under this detector. |
| S3-LAW-07 | Kicker A at S1 `x_S1=10`; A teammate at `x_S1=12` receives, then compare case where onside A teammate first passes `x_S1=12`. | First receiver is offside; second is onside. No 10 m open-play law. |
| S3-LAW-08 | Ruck at S1 `x_S1=0`, defender attacks `-x_S1`; defender at `x_S1=0.6` vs `0.8`. | Offside line 0.7; first incurs offside on the qualifying act, second does not. |
| S3-LAW-09 | Delayed formation check at exactly 0.2 s with retreat speed -0.5, -0.49, forward 0.1, and >0.1 m/s; include a separate player-holding-ball case. | Boundary values follow source: `<= -0.5` tolerated; forward over `0.1` or holding ball penalised. |
| S3-LAW-10 | Exercise each resolved exemption, line clamp, stop/out clear; do not provide unknown role exemptions. | Resolved exemptions/clearing/clamp behave as specified; unknown role claims remain disabled/provisional. |
| S3-LAW-11 | A seeded sample of torpedo tackles and ordinary/mild dangerous tackles. | Torpedo penalty is observed about 90% of trials; dangerous tackle uses 90%, mild case 7% under its documented flags. Keep seeded and report counts; do not assert every trial. |
| S3-LAW-12 | A ruck stays unavailable for `8 + L/18` seconds. | Scrum award to the team in possession, subject to the unresolved source-of-`L` marker. |
| S3-LAW-13 | Maul collapses 4 m from A's attacking try line with B responsible. | Penalty try to A: +5, try counter, conversion award; record B as the discipline offender because the collapse is within 22 m. |
| S3-LAW-14 | Run 10,000 fixed-seed notice trials for hands-in-ruck and kill-ball reports; repeat the same seeds to verify determinism. | Observed frequencies are consistent with the approximate 0.8 and 0.6 notice chances in RE 05 §2.4 (within 3 binomial standard errors). For noticed events, award an immediate penalty against the nearest offending player and post the quick-penalty check. Do not assert an exact roll cutoff or seed-to-result mapping as recovered behavior. |
| S3-LAW-15 | Dangerous-tackle report: same-team tackler/carrier; then opponent tackle clearly within referee view (10°, 10 m), then clearly outside (170°, 50 m). | Same-team case is immediate; visible opponent foul is immediate; unseen opponent foul goes through advantage. Exact boundary equality remains source-dependent. |
| S3-LAW-16 | Delay-of-game report at mark; slow lineout before and after `10 + L/18` seconds; second-stage check at `0.75 × limit`. | Delay free kick mark is `+2 m` in attack direction. Slow-lineout free kick uses the observed limit; second-stage 0.75 factor is marked inferred. `L` source stays inferred/injected. |
| S3-LAW-17 | Test S4 reports for ruck in-goal, ball dead beyond dead-ball line without grounding, and defensive grounding with known attacking last touch. | Ruck in-goal gives scrum; non-grounded dead in-goal gives 5 m scrum; defensive ground after attack kick gives 22 drop-out. Unknown carried-in/last-touch variants are not asserted. |
| S3-LAW-18 | S4 reports collapsed scrum, scrum feed offence, scrum-half offence and scrum rotation beyond limit. | Map to penalty, free kick, free kick and scrum reset respectively, preserving source O/I tags and leaving S4 mechanics to S4. |
| S3-LAW-19 | Maul collapse 10 m from A's attacking try line with B responsible. | Penalty to A; record offender for discipline because collapse is within 22 m. |

## E. Advantage (RE 05 T-08–T-12)

| ID | Setup / action | Expected result |
|---|---|---|
| S3-ADV-01 | Offside by B at S1 `x_S1=0` while A attacks `+x_S1`; A carries to `x_S1=15.1`. | Begin then advantage-over; play on; no penalty. |
| S3-ADV-02 | Same setup; B gains possession before advantage ends. | Penalty to A at original `x_S1=0` mark. |
| S3-ADV-03 | Same setup; A knocks on at `x_S1=5` while penalty advantage active. | Original penalty is awarded, not a scrum. |
| S3-ADV-04 | A carries at `x_S1=-2`, no progress, for 30.1 s. | Return to original penalty mark. |
| S3-ADV-05 | At time up, a period-ending stoppage arrives during advantage. | Award original offence rather than ending period. |
| S3-ADV-06 | Non-offender gains exactly 15 m vs >15 m while carrying / qualifying kick in field. | Equality does not end advantage; >15 with one qualifying possession/kick condition does. |
| S3-ADV-07 | Offender wins reported contest or possesses ball; then same/offending side creates another report. | First returns immediately; same-side replacement only under the source comparison, whose exact mark test remains marked unresolved. |
| S3-ADV-08 | Same-side scrum report while stored report is penalty. | With Classic config `advantage_downgrade_penalty_to_scrum=true`, stored report is replaced as observed. |
| S3-ADV-09 | Unresolved 25 s pending-stoppage branch and unknown runtime-keyed calls. | Tests assert explicit configured/injected outcome or unresolved status; no guessed Classic threshold semantics. |

## F. Penalty options, cards and sin-bin (RE 05 T-28–T-35)

| ID | Setup / action | Expected result |
|---|---|---|
| S3-DISC-01 | Enumerate penalty vs free kick/mark options. | Penalty offers goal, punt, scrum, tap; free kick/mark offers punt, scrum, tap; no goal attempt for free kick/mark. |
| S3-DISC-02 | Select each penalty option: kick at goal, punt for touch, scrum and tap-and-run; also select scrum at a free-kick/mark. | Goal option creates a place-kick restart; penalty punt gives the awarded side the throw; scrum is at the mark with the awarded side feeding; tap makes the ball live at the mark. |
| S3-DISC-03 | Compare mark, 10 m retreat and kick-at-goal touch margin. | Mark does not move forward; opponent line is 10 m; inferred 5 m kick spot margin is isolated as inferred. No Classic 15 m-in. |
| S3-DISC-04 | Player shirts 1, 2, 3; then third team player carded while two are off. | Front row never carded or warned; third card becomes warning. |
| S3-DISC-05 | Profile 0, zero initial pressure/depth, deterministic no-card R1=51 then card R1=50; test R2=400 and 401 in separate card cases. | Card iff R1 <= 50; yellow iff R2 <= 400, else warning. No-card roll increases pressure by 10; creating a card decreases it by 20, floored at zero. |
| S3-DISC-06 | Existing yellow receives another card; foul play after advantage with straight-red roll. | Second yellow produces red; 5% straight-red path exists, otherwise normal roll. |
| S3-DISC-07 | Own-22 repeat offences 1st through 5th+. | Chance table `[0,10,20,30,55]%`; team-flag owner remains explicitly unresolved/injected. |
| S3-DISC-08 | With 5-minute halves, sin-bin player at game time 1000; process stoppage at 1600, then first stoppage after 1600. | Player remains off at 1600 and returns only at first stoppage with game time `> 1600` (about 75 real seconds later); posts expiry event. |
| S3-DISC-09 | Red-carded player across any later stoppage/period. | Does not return; retains one of two off-field slots. |
| S3-DISC-10 | Inject transaction failure after discipline state changes. | Card counters, player availability, card pressure, sin-bin timer, events and RNG restore exactly; retry commits once. |
| S3-DISC-11 | Select penalty option 1 and option 4 as described in RE 07's rules-facing handoff test. | Option 1 yields scrum; option 4 yields tap-and-run. S4 receives the typed scrum award; UI labels remain a separate presentation choice. |

## G. Clock, period-end and extra time (RE 05 T-02–T-07, T-18–T-19)

| ID | Setup / action | Expected result |
|---|---|---|
| S3-CLOCK-01 | Half-length option 1 for 300 real seconds. | Game clock goes 0 to 2400 and clamps there. |
| S3-CLOCK-02 | Options 4 and 0. | Rates 1.0 and 20.0 respectively. |
| S3-CLOCK-03 | At time up submit knock-on, eligible ball-dead/scrum, eligible touch/line-out, defensive ground/22, and unrelated report. | Knock-on awards a scrum and leaves period in time-up; eligible dead-ball/scrum, touch/line-out, and defensive-ground/22 end at report time `>= 2400` (half-time event and no set piece); unrelated report does not. |
| S3-CLOCK-04 | Successful conversion after try at time up. | Conversion is still taken; its result immediately ends period. |
| S3-CLOCK-05 | Try is scored at time up. | Conversion is still awarded/taken; conversion result then ends period. |
| S3-CLOCK-06 | At 4800, non-knockout match level vs behind. | Level non-knockout ends full time; no extra time. |
| S3-CLOCK-07 | **Deferred** until S1's variable-period clock contract and the qualifying-knockout match input are approved. Fixture: two 2400-game-second regular periods, three 600-game-second extra periods, tied score, and an explicitly qualifying knockout format. | Once the clock and match-format inputs are supported, verify extra time 1 ends at 5400, the three extra-period boundaries are 5400, 6000 and 6600, and a still-level qualifying match enters the shoot-out at 6600. Until then, this is a source-mapped expectation, not an executable S3 acceptance gate. |
| S3-CLOCK-08 | Golden-point event or shoot-out kick sequence. | Inventory blocked until RE resolves early-stop, count, positions and sudden death; do not invent expected outcomes. |
| S3-CLOCK-09 | Period transition under S1 tick/flow. | Same S1 `MatchClock` advances and S1 transaction publishes the transition; no second clock or wall-time dependency. |
| S3-CLOCK-10 | Advance ticks during a scrum, line-out, conversion, kick-off and injury stoppage while the period is running. | Match clock continues through each ordinary stoppage. Cutscene/world-pause behavior remains unresolved and is not asserted. |

## H. Integration, replay and invariant checks

| ID | Setup / action | Expected result |
|---|---|---|
| S3-INT-01 | Register S3 with a documented S2 observation provider and a following S4 fake; run one event. | S3 reads detached observations and S4 fake receives one detached award; no sibling scene/node lookup. |
| S3-INT-02 | Mutate caller/returned report, award, observation and nested container copies. | Published tick/log/snapshot values remain unchanged (or mutation is unavailable for immutable public fields). |
| S3-INT-03 | Same seed, same frames and same typed S2 outcomes; live run twice and replay both logs. | Equal rule snapshot, scores, awards and ordered output values; identical future RNG state. |
| S3-INT-04 | Failed capture/system/flow/output/append/commit path then retry. | Full S1 transaction semantics hold; no double whistle, card, score, restart or RNG consumption. |
| S3-INT-05 | Mods disabled, enabled with one RulesConfig override, then disabled. | Override takes effect only while enabled; Classic result hashes return after disabling. |
| S3-INT-06 | S2 observation missing, malformed, stale or unresolved for a required law. | Checked build/tick failure or explicit unresolved rule output; never a plausible guessed Classic decision. |
| S3-INT-07 | Pick referee voice with England/England, England/France; request a kick/knock-on/advantage cue. | Shared nation weight is ×20; England and France are excluded for England/France; cue category and speech line range match RE 05. Other relative nationality weights remain unresolved data. |

## Source coverage map

| RE 05 source acceptance | Inventory coverage |
|---|---|
| T-01 | S3-SCORE-01 |
| T-02–T-07 | S3-CLOCK-01–05 |
| T-08–T-12 | S3-ADV-01–05 |
| T-13 | S3-SCORE-06 |
| T-14–T-16 | S3-TOUCH-01–08, S3-TOUCH-06B |
| T-17 | S3-SCORE-08 |
| T-18–T-19 | S3-CLOCK-06–08 |
| T-20 referee nationality weight | S3-INT-07 |
| T-21–T-27 | S3-LAW-01–10, S3-LAW-05B, S3-LAW-12 |
| T-28 | S3-LAW-13 |
| T-29 | S3-LAW-11 |
| T-30–T-35 | S3-DISC-01–10 |
| RE 07 T-31 rules handoff | S3-DISC-11 |

Additional RE 05 §2.4–2.7 law and option behavior is covered by S3-LAW-14–19 and S3-DISC-02–03;
these supplement the numbered acceptance cases above.

The RE 07 set-piece tests remain owned by S4's inventory; S3/S4 integration is covered by
S3-INT-01 and test-owned result fakes, not by running a live scrum/ruck/line-out/maul.
