# Interface Simplification for the Technically Capable User: A Design Study of the Copal Linux Desktop

*Lab Report — IEEE Format*

<!-- SPDX-License-Identifier: MIT -->
Copyright (c) 2026 paulr@sdf.org. MIT licensed — see `LICENSE`. Copal Linux is
an aggregation of Alpine Linux, not a derivative work of it; Alpine and its
packages remain under their own licences.

---

## Abstract

This report documents a series of interface interventions made to the Copal
Linux desktop — a tiling environment (Hyprland under Wayland, i3 under X11)
running on hardware between a 512 MB ARMv6 single-board computer and a
virtualised 64-bit guest — and extracts from them a design position that can be
applied to further work. The population under study is not the general computer
user. It is the *technically capable* user: someone who can read a shell script,
edit a configuration file, and recover a system from a console, and who is
therefore poorly served by interfaces whose simplification consists of removing
capability. The hypothesis under test is that simplification for this population
is a distinct discipline with a distinct method — that what should be removed is
*ambiguity, indirection and unnecessary recall*, and that capability should be
left intact and moved behind a documented escape hatch rather than deleted. Five
interventions are described: unification of two competing menus into one
two-pane menu; correction of a scroll direction that inverted the host's; the
pairing of a destructive action with its safe counterpart on one key; the
introduction of a declarative workspace layout (`copal-desk`); and the
replacement of remembered facts with an on-machine, session-correct key list.
Results are reported as static path-cost analysis rather than as a user study,
and the distinction is stated explicitly because no user study was performed.
Twelve design principles are derived and offered as the standing basis for
further Copal work.

## I. Objective

1. Characterise the user population Copal is built for, in terms specific enough
   to decide interface questions by argument rather than by taste.
2. Document five interface interventions made to the Copal desktop, each with
   the defect it addressed and the cost it incurred.
3. Measure, where measurement is honest, the change in interaction cost.
4. Derive a set of design principles that generalise beyond the five cases, and
   state them in a form that can be applied to — or used to reject — future
   changes.
5. Record explicitly which claims in this report are observations and which are
   inferences, in keeping with § VI-E of the original lab report [1].

## II. System Under Test

| Item | Detail |
|---|---|
| Distribution | Copal Linux (an aggregation of Alpine Linux 3.24) |
| Compositor A | Hyprland (Wayland), stage 16, with the *Linux Antiquity* theme [2] |
| Compositor B | i3 (X11), stage 4 |
| Menu / picker | wofi (Wayland), dmenu and jgmenu (X11) |
| Shell / bar | waybar; quickshell where obtainable (it is not, on Alpine) |
| Input stack | libinput, via `xf86-input-libinput` (X11) and natively (Wayland) |
| Hardware, low end | Raspberry Pi Zero / Zero W — ARMv6, 512 MB, no usable GPU |
| Hardware, typical | Raspberry Pi 4/5, or a UTM guest on an Apple Silicon Mac |
| Subject software | `copal-menu`, `copal-launcher`, `copal-desk`, the generated `hyprland.conf`, `/etc/X11/xorg.conf.d` |

**Scope.** This is a design study of a system the author builds and uses. It is
not a controlled experiment, it has one operator, and § V reports path costs
computed from the configuration rather than times measured from users. Every
claim about what a *user* would experience is inference and is marked as such.

## III. Background and Rationale

### A. The population, stated precisely

Mainstream desktop design optimises for a user who must not be harmed by their
own curiosity. Its methods follow from that premise: hide the filesystem, refuse
the dangerous verb, replace configuration with a small set of vetted choices,
and reduce the visible surface until nothing remains that could be misused.

The premise does not hold here. The Copal user has a shell, reads the installer,
and will edit `hyprland.conf` before the end of the first week. For this user the
mainstream method inverts: hiding the filesystem removes their fastest tool,
refusing the dangerous verb means the machine cannot do what they came to it to
do, and a small set of vetted choices is a smaller set than they already know how
to want.

But the opposite failure is at least as common in this segment, and it is the one
Copal exists in reaction to. The traditional answer for capable users has been to
present *everything*, unranked and unexplained, and to call the result power.
That is not power; it is an unpaid transfer of work from the system's author to
its user. A menu of three hundred packages in installation order, a compositor
that ships with no way to change focus from the keyboard, a launcher that lists
executables but cannot say what any of them is for — each of these is capability
without design, and each costs its user hours that the author could have spent
once.

The position taken here is that these are not the only two options, and that the
discipline in between has a definable method:

> **Simplify the interaction, never the capability.** Remove ambiguity,
> indirection and recall. Keep every verb, including the dangerous ones. When a
> simplification would cost capability, do not perform it — move the capability
> behind an escape hatch, document the hatch in the same place, and make the
> default the thing that is right nine times in ten.

### B. Prior art, and what is taken from each

**Omarchy** [3] contributes two ideas used directly. The first is the *one-level-
at-a-time* menu: a flat picker showing ten items, where choosing a category
redraws the same picker rather than drawing a tree. The second is *numbered
workspaces with fixed contents* — the same kind of thing always on the same
number. Omarchy also contributes, by counter-example, the two-menu split
corrected in § IV-A: it ships both a launcher and a system menu, on adjacent
keys, each missing the other's half.

**Competitive real-time strategy**, and specifically the macro/micro drill
literature associated with Day[9] [4], contributes the argument for fixed
positions. The claim is not that layout is tidy. It is that expert speed comes
from moving decisions out of deliberation and into the hands, that the hands can
only learn a position which does not move, and that the drill's purpose is to
make the position unconditional. Ten interchangeable workspaces defeat this by
construction: what was opened first is on 1 today and on 3 tomorrow, so every
switch begins with a look at the screen to find out where one is.

**Raskin** [5] contributes the rule that a system must not have modes the user
cannot see, and the standard by which § IV-C is judged: an interface should make
the irreversible action *distinguishable*, not merely *available*.

**Hick–Hyman** [6] and **Fitts** [7] contribute the two cost models used in § V:
decision time rises with the log of the number of visible alternatives, and
pointing time rises with distance over target size. Both are cited here as
*models used to reason about a design*, not as measurements taken from this
system.

## IV. Interventions

### A. Two menus with no path between them → one menu with two panes

**Defect.** Super+Space opened `wofi --show drun`: a flat, searchable list of
`.desktop` files, with no categories, no settings, no session control, and — on
a machine where most programs are terminal programs with no `.desktop` file —
missing the majority of what was installed. Super+Z was advertised in the
on-machine key list as opening the structured menu, and was bound to nothing at
all in the Hyprland configuration. The two menus were on adjacent keys, each
missing the other's half, and one of them was unreachable.

**Intervention.** `copal-menu` was given two panes and `copal-launcher` was
reduced to an `exec` of it. The left pane is the union of every advertised
`.desktop` entry and every installed row of the package catalogue —
deduplicated by label, sorted, filtered by typing. The right pane is the former
top level: key list, categories, Development, Emulators, Style, *Install
software*, guides, System, Session. Left and Right cross between the panes.

**Mechanism, and its cost.** wofi draws one list and will never draw two, so the
panes are one list shown twice with the arrow keys swapping which. Arrow
crossing is implemented with wofi's `key_custom_0`/`key_custom_1`, which cause
an exit status in the 10–29 range; an older wofi ignores an unrecognised
`--define` and simply retains the arrows for text editing. The cost is real and
is stated at the point of the trade, in the source, in the on-machine key list
and in the handbook: **on Wayland the arrow keys no longer move the cursor
within the search box.** Each pane's first entry performs the same crossing, so
the mouse and the X11/dmenu fallback — which have no custom keys — are not
excluded.

**Retained capability.** Super+Z still exists and still opens the structured
side, via `copal-menu --system`. jgmenu, the X11 pointer-driven tree, reads the
same generated CSV unchanged and simply gains one more submenu.

### B. Scroll direction inverted relative to the host

**Defect.** libinput's default scroll direction is the 1990s one: the wheel moves
the scrollbar, so rolling away from the body sends the page up. Copal's most
common deployment is a virtual machine on a Mac, where the host has already
applied the opposite convention. The guest therefore undid the host's
transformation halfway down a single physical gesture.

**Intervention.** Natural scrolling in both sessions: `natural_scroll = true` in
Hyprland, twice — a mouse does not read the `touchpad` block, and only the
touchpad line existed — and a new `/etc/X11/xorg.conf.d/30-scrolling.conf` with
separate `InputClass` sections for pointers and touchpads, since `MatchIsPointer`
and `MatchIsTouchpad` are matches rather than filters and a single combined
section would offer `Tapping` to a wheel mouse.

**Note on the class of defect.** This is the most instructive of the five,
because nothing was *broken*: every layer reported success, the default was the
documented default, and the configuration was the upstream configuration. The
defect existed only in the relationship between the system and the body using
it. A correct default on a machine is not a correct default in a hand.

### C. Two window-destroying verbs, one key and one modifier apart

**Defect.** The two window-destroying verbs are not the same operation.
`killactive` asks the window to close, the way its own titlebar button does; the
program runs its "save changes?" and may refuse. `forcekillactive` sends SIGKILL:
nothing is asked and nothing is saved. These were bound to Super+backtick and
Super+Escape — two unrelated keys, of which the destructive one was the
*shorter reach* and sat beside Tab.

**Intervention.** Both verbs moved onto one key, distinguished by a modifier:
**Super+Escape** closes, **Super+Shift+Escape** kills. `Super+Q` is retained as
the conventional close. The backtick binding was removed rather than left as a
third way to do the same thing.

**Rationale.** An irreversible action should not be *hidden* from a capable user
— they will need it, on the day a program stops answering — but it should cost a
distinguishable, deliberate motion, and it should be legible as the dangerous
sibling of the safe one. A modifier is the cheapest available marker of
deliberation: it makes the pair learnable as a pair, and makes the destructive
member impossible to reach by a single slipped finger.

### D. Ten interchangeable workspaces → one declarative layout

**Defect.** A tiling desktop with ten empty workspaces has no positions, only
slots. Nothing is anywhere in particular, so every workspace switch is preceded
by a visual search, and the cost is paid on every switch for the life of the
machine.

**Intervention.** `copal-desk` (Super+Shift+D), which reads a text layout file
and places programs on fixed workspaces. The shipped `code` layout: nothing on 1
(where the user is left standing), editor and terminal side by side on 2, a
Claude Code session already in `~/code` on 3, the browser on 5. Workspace 4 and
6–10 are left empty deliberately — a layout that fills every workspace leaves
nowhere for the thing that was not planned for.

**Method notes.** Roles (`editor`, `terminal`, `browser`, `files`, `music`,
`claude`) resolve against what the machine actually has, so one layout file is
correct on a Pi Zero and on a workstation; a role the machine cannot fill is
reported at the end and skipped rather than aborting the run. Two escape hatches,
`run:` and `term:`, take a command line as written. On Hyprland each window is
placed before it opens (`[workspace N silent]`), so the layout builds behind the
user; i3 has no per-exec placement, so there the tool switches workspace before
each program and returns at the end. The inter-window delay is a documented
setting rather than padding: two windows opening in the same instant race to be
the first half of the split, which is the one thing the layout exists to decide.

**Deliberately not an autostart.** Five programs starting during login is the
slowest possible moment for them to start on a 512 MB board, and a layout that
runs itself is one that cannot be declined on the morning an empty machine was
wanted. The handbook documents the single line that makes it one.

### E. Remembered facts → an on-machine, session-correct key list

**Defect.** The i3 key list was bound to Super+/ on both desktops. On the
Hyprland desktop it is the *wrong* list: the modifier is the same and almost
nothing else is. A user who presses Super+/ and receives a list they believe, and
which does not match their desktop, is further from working than a user who
received nothing.

**Intervention.** A second list, written from the same block of the installer
that writes the bindings, selected at runtime by asking the session rather than
by asking what is installed (`WAYLAND_DISPLAY` is set by the compositor for its
own clients and by nothing else). The same question governs the menu's Session
entries, so the Wayland desktop is never offered "Reload i3".

**Standing rule derived from it.** *A wrong answer is worse than a refusal.* Any
generated document that can go stale must either be generated from the same
source as the thing it describes, or must not be offered.

## V. Results

No user study was conducted, and no timing data was collected. What follows is
static path-cost analysis: the number of discrete decisions and keystrokes
required to reach a goal, computed from the configuration before and after each
intervention. This measures the *structure* of the interface. It does not
measure a user, and no claim is made that it does.

**A. Path costs, selected tasks.** "Decisions" counts points at which the user
must choose among visible alternatives; ∞ marks a task not reachable by that
route at all.

| Task | Before | After |
|---|---|---|
| Launch a graphical app by name | Super+Space, type, Enter (1 decision) | unchanged |
| Launch a *terminal* program by name (most of the system) | ∞ by launcher; menu: Super+Z, category, item (2 decisions) | Super+Space, type, Enter (1 decision) |
| Reach shutdown from the launcher | ∞ — no path | Super+Space, →, Session, Shut down (3) |
| Reach the structured menu at all | ∞ — Super+Z was unbound on Hyprland | Super+Z (0) |
| Read the key list for *this* desktop | wrong list served on one of two desktops | Super+/ , correct by session (0) |
| Kill an unresponsive window | Super+Escape — shorter reach than close | Super+Shift+Escape — one modifier dearer than close |
| Reach a known working set of five windows | ~12 keystrokes and 4 workspace switches, positions non-deterministic | Super+Shift+D, positions fixed |

**B. Visible alternatives at the top level.** The right-hand pane presents 10–14
entries depending on what is installed; the left pane is unbounded but is
addressed by typing rather than by scanning, so Hick–Hyman applies to the former
and not to the latter. This is the structural reason for the split: *a list you
search and a list you scan should not be the same list.* (Inference from [6], not
a measurement.)

**C. Capability retained.** No verb was removed by any of the five
interventions. One binding was removed (Super+backtick) and its function is
available on two other keys. One behaviour was lost as a stated cost: arrow-key
cursor movement inside wofi's search field, on Wayland only.

**D. Regressions and residual risk.** (i) The wofi custom-key exit-status range
is taken from wofi's documented behaviour and verified only by construction here;
an older or divergent build falls back to arrows-edit-text, which is degradation
rather than failure. (ii) `copal-desk`'s inter-window delay is a heuristic; on a
slow board it may need raising, and the tool says so. (iii) Natural scrolling is
correct for the common deployment and wrong for a user who prefers the older
convention; both files carry the line to set it back. (iv) The two scroll
configurations — Hyprland's and X's — are not kept in step by anything but the
operator, and the handbook says so rather than implying otherwise.

## VI. Discussion — the principles worth continuing

The following are stated as standing rules for further Copal work. Each is
derived from at least one intervention above or from an existing decision in the
installer, and each is falsifiable in the sense that a future change can be
checked against it.

**1. Simplify the interaction, not the capability.** Every dangerous verb stays.
What gets removed is ambiguity about which verb one is invoking. (§ IV-C.)

**2. One thing should have one implementation, and may have several doors.**
Super+Space, Super+D and Super+Z now open one menu with different starting
panes. Two implementations of one idea diverge within a week; two doors into one
implementation cannot.

**3. Make the absent discoverable.** Software the user does not have is not
findable by definition, which is why the menu carries an *Install* branch built
by inverting the same catalogue that drives the installer. A search box can only
find what is already there; a designed interface must also present what is not.

**4. Fixed positions beat clever placement.** Muscle memory can only learn a
position that does not move. Prefer determinism the user can rely on to
optimisation the user must re-read. (§ IV-D, [4].)

**5. The dangerous sibling costs one modifier.** Not hidden, not confirmed by
dialog, not renamed — one deliberate extra motion, adjacent to the safe verb so
the pair is learnable as a pair. (§ IV-C, [5].)

**6. Defaults must be correct in the hand, not merely correct in the
specification.** The upstream default, the documented default and the inherited
default are all evidence; none of them is the answer. (§ IV-B.)

**7. A wrong answer is worse than a refusal.** Generated help must come from the
same source as the thing it describes, or must not be offered. Ask the session,
not the filesystem, when the question is "which desktop is this?". (§ IV-E.)

**8. Degrade along a stated path, and never silently.** quickshell → waybar,
wofi → dmenu, graphical editor → nvim in a terminal, hyprshot → grim+slurp. Each
fallback is written down at the point where it is chosen, and a role that cannot
be filled is reported rather than skipped in silence.

**9. State the cost where the trade is made.** The lost arrow keys are recorded
in the source, in the on-machine key list and in the handbook. A design that
hides its own costs cannot be audited by the next person, who is usually the
same person a year later.

**10. Configuration is a text file, and there is always an escape hatch.**
Layouts are text; roles cover the common case; `run:` and `term:` cover
everything else. The general form: *a good default, a named vocabulary for the
common cases, and a raw hole for what nobody anticipated.*

**11. Generate configuration; never edit the vendored tree.** Deviations from
upstream belong in the generating stage, where they are readable as a list of
decisions, not spread through copied files where they are invisible. (Existing
practice, [2]; worth restating because it is what makes § IV auditable at all.)

**12. Do not autostart what the user might want to decline.** Convenience that
cannot be refused is a policy. Offer the key, document the one line that makes it
automatic, and let the user choose. (§ IV-D.)

**A note on what these are not.** None of the twelve is an argument for
minimalism as an aesthetic. Copal ships three hundred packages in its catalogue
and a menu branch for installing the ones absent. The claim is narrower and, the
author would argue, more useful: for a capable user, *interface* complexity and
*system* capability are independent axes, and the entire craft is in reducing
the first without touching the second.

## VII. Conclusion

Five interventions were made to the Copal desktop, addressing a split menu with
an unreachable half, a scroll direction inverted relative to its host, an
irreversible action bound more cheaply than its safe counterpart, an environment
with slots but no positions, and generated help that could serve the wrong
desktop. Path-cost analysis of the configuration shows two previously
unreachable tasks becoming reachable, one common task falling from two decisions
to one, and no capability removed; one behaviour was traded away and is recorded
in three places. No user study was performed and none of these results should be
read as one.

The design position derived from the work is that simplification for technically
capable users is neither the mainstream method (remove capability until nothing
can be misused) nor its usual opposite (present everything and call it power),
but a third discipline: remove ambiguity, indirection and recall; keep every
verb; make the dangerous one distinguishable rather than absent; make positions
fixed so hands can learn them; and write the cost down wherever a trade is made.
The twelve principles in § VI are offered as the standing basis for further Copal
work, and as the criteria against which the next change should be argued.

## VIII. Appendix A — Three houses, informally

*What follows is written in a different register from the rest of this report:
first person, no citations to speak of, and argued rather than measured. It is
here because the question "what does each of these projects actually believe?"
kept being answered inside technical sections where it did not belong. § III-B
records what was borrowed. This records what was believed, including the parts
that were not borrowed.*

### The three houses

Copal's desktop is downstream of two other projects with strong opinions, and
the three disagree in interesting places.

**Linux Antiquity believes the desktop is a place, and that places have a
subject.** diinki's stated design method starts by refusing the obvious
aesthetics — retro, flat, Aero, liquid glass — on the grounds that you can
imagine each of them before it is built, which makes building one an exercise
rather than an experiment. What replaces them is deliberately far from
computing: old scientific illustration, armillary spheres, anthropomorphised
suns and moons, the four humours, tarot. The interesting consequence is
structural, not decorative. If your subject is celestial mechanics, workspaces
become planets on an orbit and the active one grows solar flares; the power menu
becomes three tarot cards; the weather widget reports in humours. Nothing radial
exists in Qt Quick, so the curve primitives were written from scratch. That is
the theme's real claim: **an aesthetic thesis is only serious if it survives
contact with layout.** Anything that stops at colours is a palette pretending
to be a position.

Two more things it believes, both worth keeping. *Aliveness* — the bodies rotate
slightly, because "they have faces, so it would be weird if they were static";
motion as characterisation rather than as feedback. And, stated flatly in the
same breath as all the art: **usability is non-negotiable.** Menus close on
outside click, the launcher searches, the widgets are configurable in a settings
window. It is a maximalist aesthetic with no tolerance for the usual maximalist
excuse.

**Omarchy believes that taste is a deliverable.** Its position is that the
expensive part of a Linux desktop was never the software — it is the six months
of decisions, and that a curated set of them, shipped whole and pre-integrated,
is the actual product. Hence: one opinionated stack rather than a menu of
equivalents, themes that apply to *everything* at once rather than to the bar
alone, a menu that shows ten things at a time instead of a tree, workspaces
numbered by purpose, and documentation written as a manual rather than as a wiki.
Underneath is a claim about learning — that a good default is *teaching
material*, and that the way you learn a configurable system is by living inside
someone's finished configuration and then editing it. This is the direct
descendant of the "convention over configuration" argument its author made about
web frameworks, moved onto a desktop.

Where I part company with Omarchy is at the edges of that generosity. Nineteen
themes is nineteen surfaces to keep correct; an opinionated stack that assumes a
GPU is an opinion the hardware can veto; and two menus on adjacent keys — a
launcher that cannot log you out, a system menu that cannot search your
applications — is a curation that stopped one step early. § IV-A is the whole of
my disagreement, and it took forty lines of shell to state.

**Copal believes the constraint is a design partner.** Every position in this
report has a 512 MB ARMv6 board somewhere behind it. When the machine has one
slow core, "just install a nicer launcher" is not available and you are forced
to find out what the launcher was actually for. That is a gift, not a hardship.
Half of the good decisions here — the terminal that renders on the CPU, the menu
that is a text file walked by `sh`, the clipboard history in fifty lines because
the Go one has no armhf build — are the shape they are because the easy answer
was unavailable and the constraint made us think.

The rest of what Copal believes, stated as plainly as I can:

- **The machine must explain itself, offline, in its own words.** A key list
  written from the same block that writes the bindings. Eleven guides on the
  disk. A menu branch listing what you have *not* installed, because software
  you do not have is not discoverable by definition. Copal targets machines that
  are sometimes not on a network, and a system whose documentation lives on
  someone else's server is not a system you own.
- **Nothing is hidden, and nothing is precious.** Every deviation from upstream
  is a legible line in a generating stage rather than an edit smuggled into a
  vendored file. The installer is re-runnable. No binaries are tracked. You are
  meant to read it, and if you read it, it should hold up.
- **Degrade honestly and say so.** quickshell → waybar, wofi → dmenu, a
  graphical editor → nvim in a terminal. Every fallback is written down at the
  point where it is chosen, so what you have got is never a mystery. A silent
  fallback is a lie the system tells about itself.
- **A wrong answer is worse than a refusal.** The i3 key list served on the
  Hyprland desktop was worse than no key list, because it was believed.
- **Write down what a decision cost.** The lost arrow keys in § IV-A appear in
  the source, in the on-machine key list and in the handbook. Not because the
  cost is large, but because a design that hides its costs cannot be audited by
  the next person — who is, most of the time, the same person a year later.

### Where the three actually disagree

| | Antiquity | Omarchy | Copal |
|---|---|---|---|
| The desktop is… | a painting you can interact with | a finished set of decisions | a machine you can read |
| First loyalty | the aesthetic thesis | coherence across the whole stack | the constraint, and the truth about it |
| Configuration is… | a canvas to be redrawn | a default to live inside and then edit | a text file with an escape hatch |
| Beauty is… | the point | a feature of the system, applied everywhere | welcome, if it fits in 512 MB and degrades honestly |
| Failure mode | a shell that cannot be packaged | curation that assumes your hardware | an essay where a sentence would do |

That last cell is not false modesty. This project's characteristic mistake is
explaining at length in a comment what a better-designed interface would not
have needed explained. Every one of the twelve principles in § VI is, read
uncharitably, a note-to-self about that.

### What I would tell someone starting a desktop for capable users

Pick a population and say it out loud, because "everyone" resolves to the
mainstream method by default and you will remove capability without noticing.
Then: keep every verb; make the dangerous ones distinguishable rather than
absent; give one thing one implementation and as many doors as it needs;
put things in fixed places so hands can learn them; make what you *don't* have
as discoverable as what you do; and write the cost down wherever you trade.

Then use it for a week on the worst hardware you support. That week will tell
you more than this report did.

## References

[1] P. Richeson, "Bringing up a minimal TUI/GUI windowing environment on the
Raspberry Pi Zero 1 and Zero 2 W using Alpine Linux," *Copal Linux lab report*,
`docs/lab-report.md`, 2026.

[2] P. Richeson, "Porting *Linux Antiquity* to Copal Linux: vendoring,
transformation, and an exclusive Wayland session on Alpine," *Copal Linux
technical report*, `docs/THEME.md`, 2026.

[3] D. H. Hansson *et al.*, "Omarchy," an opinionated Arch/Hyprland desktop
configuration. [Online]. Available: https://omarchy.org

[4] S. Plott (Day[9]), "The Day[9] Daily — macro mechanics and drill-based
practice," *Day[9] TV*. [Online]. Available: https://day9.tv

[5] J. Raskin, *The Humane Interface: New Directions for Designing Interactive
Systems*. Reading, MA: Addison-Wesley, 2000.

[6] W. E. Hick, "On the rate of gain of information," *Quarterly Journal of
Experimental Psychology*, vol. 4, no. 1, pp. 11–26, 1952; and R. Hyman,
"Stimulus information as a determinant of reaction time," *Journal of
Experimental Psychology*, vol. 45, no. 3, pp. 188–196, 1953.

[7] P. M. Fitts, "The information capacity of the human motor system in
controlling the amplitude of movement," *Journal of Experimental Psychology*,
vol. 47, no. 6, pp. 381–391, 1954.

[8] Hyprland contributors, "Hyprland wiki — dispatchers, binds and variables."
[Online]. Available: https://wiki.hyprland.org

[9] libinput contributors, "libinput documentation — scrolling and device
configuration." [Online]. Available: https://wayland.freedesktop.org/libinput/doc/latest/

[10] P. Richeson, "Copal Linux handbook," `docs/copal-handbook.md`, 2026.
