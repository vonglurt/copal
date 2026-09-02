# Giving Back Without Pushing: Copal and Its Upstreams

*A position paper. 2 September 2026.*

## The question

Copal is a very different distribution from the projects it draws on. It is
Alpine on a Raspberry Pi, a PC or a UTM guest, installed by one re-runnable
script; Linux Antiquity is a Hyprland theme for Arch, with a quickshell bar
and a design thesis; Omarchy is an opinionated Arch desktop; wofi and Hyprland
are the tools underneath. Yet the goals overlap almost entirely — a desktop a
person can understand, that looks like somebody meant it, on hardware nobody
else bothers with — and diinki's goals in particular are so well articulated
that Copal has quoted them (see `THEME.md`).

So the obligation to attribute is clear and is met. The open question is the
other direction: **when, if ever, should Copal send work upstream?** The
temptation after a session like the menu rework is to open pull requests
everywhere. The news is full of maintainers who would rather we did not.

## What the maintainers are complaining about

The complaints have a shape, and it is worth being precise because the shape
is the test:

1. **Unasked-for.** The change solves a problem the maintainer did not have,
   on a platform they do not run, in a style they did not choose.
2. **Cheap to make, expensive to review.** A generated patch costs its sender
   minutes; reading it, testing it, and writing a kind refusal costs the
   maintainer an evening. The asymmetry is the injury.
3. **Attribution as motive.** Some are sent to have a commit in a known
   project, not to fix anything. Maintainers can tell.
4. **Volume.** One of these is a Tuesday. Twenty are a reason to close the
   tracker.

Nothing in that list says "do not contribute". It says: do not make your work
the maintainer's problem.

## Where Copal's changes actually belong

Sort this session's changes by who has the problem they solve:

| Change | Who has the problem | Belongs |
|---|---|---|
| `copal-menu` cache, headings, session at top level | Copal alone; upstream has no such menu | Copal |
| Hyprland submap for the menu's arrows | Copal alone; it serves `copal-menu` | Copal |
| `copal-halt` asking with wofi on Wayland | Copal alone | Copal |
| `copal-unplug` on a Pi | Copal alone; the upstreams do not target a Pi | Copal |
| wofi 1.5.3 stalls with `--lines` past ~100 rows | **wofi's users, everywhere** | a bug report to wofi, with the reproduction from `menu-lab-report.md` §B |
| wofi's `key_custom_n` only arms an exit code | nobody: the manual says so | nothing |
| Hyprland resets a submap when a virtual keyboard appears | arguable; possibly intended | nothing, unless asked |
| Antiquity's configs translated to Alpine and Wayland-native tools | Copal, and anyone else putting the theme on a non-Arch system | the fork, visible, per `THEME.md` §IX |

The pattern: nearly everything Copal makes is Copal's concern, because Copal's
whole reason to exist is the gap the upstreams do not cover. The exceptions
are **defects found in the upstream's own product, on the upstream's own
terms**, and those are bug reports, not pull requests. A bug report with a
reproduction is the one contribution every maintainer wants and few get.

## The rule

1. **Attribute always, in the code and in the docs.** Done, and kept: the
   MIT notice travels to the card and the installed system; the theme
   report names diinki as the author of the theme, the art and the thesis;
   the menu's comments say its structure is Omarchy's. Attribution is owed
   whether or not anything is ever sent upstream.

2. **Report defects; do not fix them by surprise.** When Copal finds
   something broken in an upstream on that upstream's own platform, it files
   a report with a reproduction and the measurements, and offers a patch in
   the report if it has one. Whether the patch becomes a pull request is the
   maintainer's call, made after reading the report. That is the one form
   of "PR" the complaints above do not describe: it was asked for.

3. **Pull requests only when an audience suggests it.** A change of Copal's
   goes upstream as a PR when one of these is true: the maintainer asks; a
   user of the upstream, not of Copal, raises the same need on the upstream's
   tracker; or the change has run in Copal long enough that people using both
   projects say it belongs there. "We think it is a major improvement" is not
   on the list, because that is the sender's opinion, and the complaints are
   precisely about senders' opinions.

4. **Keep the work visible instead.** The fork planned in `THEME.md` §IX is
   the mechanism: Copal's branch of Linux Antiquity, public, with its changes
   committed cleanly and its README pointing at diinki's original. Anyone —
   including diinki — can pull from it when they want to, on their own
   schedule, and nobody has to review anything they did not ask to see. A
   standing offer costs the maintainer nothing until they take it up.

5. **Small, single-purpose, on their platform, when it does happen.** A PR
   that is eventually sent fixes one thing, is tested on the upstream's own
   target, follows the upstream's style, and says in its first line what
   prompted it and who asked.

## Why this is not timidity

It would be easy to read the rule as "never contribute". It is the opposite.
Bug reports are contributions; a public fork with clean history is a
contribution; documentation that credits the origin of an idea is a
contribution. What the rule refuses is the *form* of contribution that
transfers work from the sender to the receiver without consent. Copal's
position is that of a downstream that has read the upstream carefully, says
so, and waits to be invited — which, if the work is good and visible, tends
to happen.

## What follows from it now

- File the wofi `--lines` stall as a report on wofi's tracker, with the
  bisection table and the exit-status probe from the lab report. Offer the
  finding, not a patch: the fix inside wofi is wofi's to design.
- Create the Linux Antiquity fork, its Copal `main` and the `original-fork` tag, per
  `THEME.md` §IX, so that the translations exist somewhere diinki could look
  at them without being handed them.
- Add a line to Copal's README naming the upstreams and stating this policy
  in one sentence, so a reader knows what to expect from us.
- Send nothing else.
