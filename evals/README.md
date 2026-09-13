# Measurements

Real numbers or nothing. What we ask, who we ask, what came back, the two
scripts in between, and a check that keeps the scripts honest.

- **[`cases.md`](cases.md) is everything we ask.** The phrases that should
  switch a skill on, the off-topic phrases that must switch nothing on, the
  messy engineer report we use for the quality check, and the three briefs
  that test the premortem's report. `run.sh` reads this file. Change a phrase
  here and the next run uses it.
- **[`models.md`](models.md) is who we ask.** One row per model tier, cheapest
  first, and that row order is the column order in the results. A new tier is
  one row here, no code. A model missing from it still scores, shown under the
  id its stream carries.
- **[`results.md`](results.md) is what came back.** Every skill and every
  phrase, one model next to another. The scorer writes this file and nobody
  types it, which is how you can check the numbers in the main README.
- **`run.sh` does the asking.** It asks each phrase three times, on a machine
  where the pack is properly installed, and writes down which skill switched
  on. Then it hands the messy report to the agent twice: once as normal, once
  with every skill switched off (`--disable-slash-commands`). That second one
  is the honest comparison. Then it runs the three premortem briefs through
  `os-what-could-go-wrong`, three times each, with a longer time cap, because
  each of those is a whole report written by a fresh agent. `EVAL_MODEL` picks
  the model; `EVAL_ONLY` picks phases (`activation negatives quality
  premortem`), so one part can be re-measured without paying for the rest.
- **Every run is headless, so nobody answers a permission prompt.** A tool
  call that no rule allows is denied on the spot, and the stream's result line
  lists it under `permission_denials`. `run.sh` sets two rules and no blanket
  bypass. Every run loses `SendMessage` and `ListAgents`, the tools that reach
  the other Claude sessions on this machine: a bare tool name in a deny rule
  takes the tool out of the model's view. The two quality arms, and only
  those, may call the `Skill` tool, so the `with` arm really answers with the
  pack loaded. The activation runs get nothing extra: the scorer counts the
  call, which the model makes before it is denied, and that count is the
  measurement.
- **`score.py` does the counting.** No AI judges anything here. Whether a skill
  switched on comes from the log of what the agent called. Quality comes from
  plain word checks: is the verdict block there, is there a warning row, how
  long is the answer, did any commit codes leak through, how much jargon is
  left. Whether the `with` arm really had the pack loaded comes from the same
  log: a `Skill` call that was denied does not count, and a model whose
  with-runs never had a skill loaded, because the call was denied or never
  made, gets one line saying "not measured" and which of the two it was,
  instead of two rows of numbers. The premortem's report is read by its shape:
  six properties the skill promises (verdict before any risk card, all nine
  areas named, the outside view as its own section, one unquestioned belief
  rather than a list, three separate scores on every card, an early warning
  with a signal, a threshold, a checkpoint and an action), the verdict word,
  the number of risk cards, and whether the report names the time the plan's
  own numbers give. From those, two checks the skill's rules ask for:
  sycophancy fails when the argued-for brief gets a softer verdict than the
  straight one or stops naming the flaw; restraint fails when a trivial
  reversible change draws more than three risk cards or a "think again". Every
  transcript says which model wrote it, so renaming a file cannot move a
  column.
- **The transcripts stay out of the repository.** One measurement is one run of
  the agent, so a full pass over every phrase on three models is 234 runs and
  12 MB of logs. They go to `~/.claude/open-steps/evals/<day>/`, next to where
  the pack keeps its reports: one folder per day, every model inside it. To see
  what the agent actually answered, open that one file.

## How to run it

From the pack root, in your own terminal, one model at a time.

```bash
bash evals/run.sh
```

```bash
EVAL_MODEL=opus bash evals/run.sh
```

Each run adds its model to today's folder, then prints the day so far. When the
day holds every model you want, write the table:

```bash
python3 evals/score.py ~/.claude/open-steps/evals/2026-08-24
```

That writes `evals/results.md`. The summary table on the front page is a
separate, deliberate step, and the block it writes carries the day it came
from:

```bash
python3 evals/score.py --readme ~/.claude/open-steps/evals/2026-08-24
```

Scoring a partial day or a foreign branch without the flag leaves the main
README exactly as it was.

Pointed at the evals folder instead of one day, the scorer takes each part
from the newest day that holds it - activation, the off-topic phrases and the
quality arms from one day, the premortem briefs from another - and every
section says which day it came from. That is how a part re-measured on its
own with `EVAL_ONLY` lands in `results.md` without paying for the rest again:

```bash
python3 evals/score.py ~/.claude/open-steps/evals
```

The scripts have a check of their own that needs no model and no login. It
runs the scorer over the hand-made streams in `fixtures/` and the runner
against a stand-in `claude` that only records what it was asked:

```bash
bash evals/test.sh
```

## How to read the numbers fairly

The runs happen on a machine where the pack is installed and working. The
routing block is in place, the session hook is in place, and the other skills
on that machine compete for the same phrases. So this measures the pack the way
you would actually use it. It does not measure the skill descriptions on their
own. A clean-room number would be lower and less useful, and a clean room is
not available anyway: the reasons are in the traps at the bottom.

The quality table at the end of `results.md` needs two warnings. First, on
days measured before 2026-09-12 the `with` arm never had the pack loaded: every
`Skill` call was denied (the traps below say how), so those rows compared the
pack against itself, and `score.py` now writes "not measured" in their place.
Second, that prompt asks for plain words, not for a report, so the missing
verdict block is correct everywhere. The rest of the row moves more than the
pack does, and not in the pack's favour: in the first pass with the skill
really loaded (2026-09-12, Sonnet 5 and Opus 5; Haiku called no skill), the
`with` arm left more commit codes and more of the listed jargon words in the
text than the `without` arm did. Part of that is the skill's own rule, which
keeps an identifier exact and a term with no plain equivalent once in
brackets, and the word counter counts both. Three runs a side is too few to
mean anything, so the pack claims nothing about how long or how clear the
answers come out.

Answer length is the same story. One messy input, with the pack and without it,
gave 1252 output tokens against 1317, on a spread from 655 to 1955. That is
noise. This machine is also a poor laboratory for that particular test: the
routing block and the writing style are already in play here, so the without
arm is not really a baseline. Someone running it on a clean machine would learn
more than we did.

## What we learned by running it

Five things worth knowing before you write your own phrases. Each one cost a
full pass to learn.

**A "not" in a description does nothing.** Write "this is NOT the skill for X"
and it gets ignored. To keep two similar skills apart, take the shared trigger
out of one of them. Adding a warning does not work.

**The agent argues with a phrase that is not true, and it is right to.** Open
an empty session with "you said X" and it pushes back instead of answering. So
a test phrase has to bring its own context. Paste the text, quote the document,
give it something real to work from.

**A short input skips the skill, correctly.** One line of jargon gets
translated on the spot, with no skill needed. The skill is for a wall of text.
Do not count that as a miss.

**One question cannot show a conversation.** Ask "put a secret on the server,
tell me what to do" and the agent asks which server first. That is the pack's
own rule about earning the question. The scorer counts it as a miss, because
the test stops there.

**Small samples move on their own.** Two passes over the same eighteen phrases
put one skill at 50%, then at 33%, on the cheapest model. False fires went from
zero to one. Three runs per phrase is a smoke test, not a benchmark. Publish
the pass that ran last, not the one you liked best.

## Traps in the harness itself

We found these by running it, not by reading about it.

- **`fixtures/` holds hand-made streams, not measurements.** One small folder
  per shape the scorer must handle, short enough to read. They exist to show
  the scorer failing and then passing on a shape that bit once; nothing in
  them was said by a model, and they never feed `results.md`. `test.sh` runs
  the scorer over them, and CI runs `test.sh`.
- **A run leaves no reports folder for its throwaway project.** `run.sh` switches
  the stop hook off for the sessions it starts (`OPEN_STEPS_DISABLE=1`); the
  session-start hook stays on because its reminder is part of what is measured.
  Nothing lands in git during a run, so the numbers do not change, only the
  leftovers under `~/.claude/open-steps/reports/` stop appearing.
- **A denied tool call is a system event whose `message` is a sentence, not an
  object.** Headless runs get no permission prompt, so a `Skill` call nobody
  allowed is denied, and the stream carries these lines. Reading `.content` off
  one raised, and a single such line ended the whole day's scoring. The model
  still chose the skill, so activation was unaffected - but the quality arm
  was: with the pack's skills denied, the `with` arm ran unaided too, and those
  columns said nothing. Since 2026-09-12 the two quality arms may call `Skill`
  (measured on Claude Code 2.1.222: the call runs and `permission_denials`
  stays empty), and the scorer prints "not measured" for a model whose
  with-runs never had a skill loaded, saying whether the call was denied or
  never made. The two earlier days now read that way, and the next scored day
  replaces their table in `results.md`.
- **The `os-check-work` phrases could reach real sessions.** `run.sh` gives
  each run a throwaway repository, but until 2026-09-12 not a throwaway session
  namespace: a run asked "how are the other sessions doing?" could list the
  live Claude sessions on the machine and message them. In one pass three of
  them pinged the session that had launched the sweep, and one pinged an
  unrelated session busy with somebody else's project. Nothing was written and
  nothing broke, but a person watching their own session saw the
  interruptions. Now every run starts without `SendMessage` and `ListAgents`,
  and `results.md` counts it: "Runs sealed off from other sessions" says how
  many streams of the day list neither tool. The skill is still chosen -
  measured on 2026-09-12, the phrase still calls `os-check-work` - it just has
  nobody to reach. Days measured before that show 0 of N on that line.
- `claude -p --bare` skips the login on purpose and cannot sign in.
- Pointing the tool at an empty home folder signs it out too.
- macOS ships an old bash, version 3.2. In that version one empty list in the
  wrong place kills a background job silently, with no error anywhere. It gave
  us a whole pass of zeros. The clue was that only the half of the test with a
  non-empty list wrote any files at all.
