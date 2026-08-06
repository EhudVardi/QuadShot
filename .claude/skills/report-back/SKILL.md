---
name: report-back
description: The house format for reporting findings, results, diagnoses, measurements or completed work back to the human on QuadShot. Use this whenever you are about to summarise what you did, what a bench measured, what a bug turned out to be, what you recommend, or what changed - including short answers and follow-up questions about earlier work. Structure every such reply as Goal / Terms / What I found / Try it yourself / What's next, and define every term the human has not personally used first. Whenever the report asks the human to fly, judge or confirm something, it MUST also give them the exact quickest command and route to reproduce that situation.
---

# Reporting back

## Why this exists

The human asked for it, in these words:

> *"I think that when you work with yourself, you start producing your own
> terminology, so when you report back you use it, assuming i was there with you
> all along."*

That is exactly what happens, and it is worth understanding the mechanism rather
than just obeying a rule. While working you read the code, the design doc and the
bench output continuously, so a phrase like *"the sight-clamp"* or *"best flak 0%
(dent 9.7)"* becomes ordinary to you within minutes. The human was not in that
loop. Every one of those coinages is a private word, and using it in a report
silently asks them to either interrupt or nod along.

Nodding along is the real damage. The human said so directly: they want to
*"avoid waving things that you say as true"* and to be able to push back. **A
report they cannot fully parse cannot be argued with**, so unexplained jargon
quietly converts a collaborator into an audience. Defining terms is not politeness
— it is what keeps their disagreement available to you, which is the most valuable
thing they give you.

They also said: *"it may be longer with words, but it would be much more
readable."* Length is not the cost to optimise. Comprehension is.

## The structure

Five sections, in this order. The first three are always required. "Try it
yourself" is required whenever a human verdict is being asked for, and only then.
"What's next" is optional.

```
## Goal
One or two sentences: what I set out to do and why, in plain words.

## Terms
Every term, abbreviation, filename, metric or number-format the human may not
know - one line each, plain language. Omit the section only if genuinely empty.

## What I found
The actual report. Findings, results, what changed, what broke.

## Try it yourself
Required whenever the report asks the human to judge, fly, look at or confirm
something that is not one obvious click away. The exact quickest route.

## What's next
Optional. Recommendations, open decisions, things waiting on them.
```

Use these as literal headings. The human is scanning; consistent headings let
them jump to the part they want.

## "Try it yourself" — the section that unblocks them

Added by the human 2026-08-06, and the trigger was concrete: a report said *"the
aegis pacing question is waiting on you"* and *"nothing here has been flown by
hands"* — and then did not say how to meet an aegis. They went looking, could not
find one, and had to come back and ask. **The judgement they were being asked for
was blocked on information only the agent had.**

Their rule, in their words:

> *"when you need me to do something that is not straight forward (like this
> specific encounter with the aegis), you should also give me the most correct and
> quickest way to put myself in the situation that you need me to give judgement."*

**Include this section whenever the report asks for a human verdict.** "Please
fly this", "does this feel right", "not flown by hands", "waiting on your call
about the pacing" — every one of those is a request that must ship with its route.

What it has to contain:

- **A literal command line, copy-pasteable**, with the real executable path and
  the real flags. Not `<godot> --path .` in a sentence — the actual line.
- **Where the thing will be** once they are in: which direction, how far, how long
  until it happens. A specimen 90 metres behind the spawn is a specimen they will
  not find.
- **What they should be looking for**, in one line, so they know when they have
  seen it. Also what would count as it being WRONG.
- **The quickest route, not the most representative one**, when those differ - and
  then say so, and give both. A dev-room specimen that appears in five seconds
  usually beats a campaign node that needs three menus, but if only the campaign
  shows the real thing, say which is which and why.
- **Verify the route before writing it down.** Run the command, or at minimum
  confirm the node/seed/scene actually contains what the report claims. A route
  that does not work costs more than no route, because they will assume the
  feature is broken rather than the instructions.

If the report asks for nothing, omit the section. If it asks for a verdict and
omits the section, the report is incomplete.

## Choosing what goes in Terms

The hard part is not writing the definitions — it is **noticing** that a word
needs one. Your sense of "obvious" is calibrated by an afternoon of reading this
codebase and theirs is not. Apply these tests; if any hits, define it:

- **Did I coin it, or did the project?** `sight-clamp`, `cleared fraction`, `the
  bridge`, `the escort rule`. Project vocabulary counts even when it predates
  this session, unless the human has used the phrase themselves.
- **Is it an abbreviation?** SDI, EW, FCS, SDI, VTX, P2.6, W.q8, H6. Design-doc
  IDs are abbreviations too — say what the section is about, do not just cite it.
- **Is it a file, function, class or config field?** `SortieRunner`,
  `fire_assist_miss_m`, `WarManifest.DOCTRINE`. Say what the thing does, not just
  where it lives.
- **Is it a bench column or a raw output line?** `dent`, `hull 100%`, `best flak
  0%`. These are the worst offenders because they look like plain English.
- **Would a competent developer who has never seen this repo need to guess?** If
  yes, define it.

When unsure, define it. A redundant one-liner costs the human three seconds; a
missing one costs them a search or, worse, a silent misunderstanding.

## Numbers need a unit and a meaning

A bare number from a tool is not a finding. `dent 9.7` is not a report — it is a
cell reference. Give the number its unit, its scale, and what it implies:

**Weak:** best flak 0% (dent 9.7)
**Better:** flak was the best of the three weapons, and it still finished 0 sorties
out of 3 — but it destroyed 9.7 "strength" worth of the enemy garrison first, out
of the 15.5 that node had. So the pilot took apart about two thirds of the node
and then died.

The same applies to distances, times and versions. `125 m` should say *125 metres
away from the target, horizontally* if there is any chance of it being read as
altitude.

## Tone and pushback

This is a collaboration and the human has explicitly asked to be challenged. So:

- **State disagreement plainly** when you have it, with the reasoning. They said
  they will simply reject a push they disagree with and keep the final call.
- **Separate what you measured from what you concluded.** Findings are evidence;
  recommendations are opinion. Label which is which.
- **Say when you were wrong**, including predictions that did not survive. Do it
  in one line, without ceremony, and move on.
- **Flag confidence honestly.** "I verified this" and "I believe this" are
  different claims and should read differently.

## Worked shape

A short report still uses the structure — it just gets shorter, not looser.

```markdown
## Goal
Find out why the campaign map showed nodes that felt empty when you flew them.

## Terms
- **node** — one hexagon on the campaign map; one place you can fly a mission to.
- **garrison** — the enemy units defending a node.
- **sight range** — how far an enemy can see; beyond it, it ignores you entirely.

## What I found
Enemies only chase and shoot you inside their sight range. The game was placing
them in a ring 48 metres from the middle of the fight, while the turret type can
only see 45 metres. So they sat 3 metres too far out and never joined in...

## What's next
Two options, and I lean towards the second...
```

## When NOT to use this

Do not wrap trivial exchanges in headings. If the reply is one sentence — "Yes,
that file is committed" — just say it. The structure is for reports: anything
where you are handing over findings, results, a diagnosis, or a decision the
human needs to act on.
