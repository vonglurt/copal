<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 paulr@sdf.org -- copal-alpine-linux -->

# Automation: what to type, what calls what, and what can be driven

Three front doors do the same work, and the only difference is how much you
want to type:

| | Example | Use it when |
|---|---|---|
| **`./copal`** | `./copal build vm` | You want to be asked. It shows a flow chart, a board menu and a briefing per target *before* anything is erased. |
| **`make`** | `make image` | You know what you want. This is the real interface; everything else wraps it. |
| **`bin/*.sh`** | `bin/vm.sh` | Muscle memory and tab completion. Each is two lines that `exec make <target>`, so they cannot disagree with the Makefile. |

`make chain` prints the whole map at any time, including which targets call
which — the thing that is genuinely invisible in a Makefile, because a
recursive `$(MAKE)` inside a recipe does not show up in `make -n` until it
runs, and never shows up in `make help`.

---

## Doing all of it

```sh
make release PURGE=1
```

That is the whole thing, from nothing:

```
make release PURGE=1
  └─ purge YES=1     empty build/, delete both UTM machines
  └─ auto            ./copal build vm --auto   (unattended; script(1) supplies a tty)
  └─ verify          image stamp vs checkout vs remote
  └─ video           record the install, render GIF + mp4 + stills
  └─ gallery         regenerate docs/gallery.html from docs/media
```

`PURGE=1` is off by default on purpose. Purging destroys the payload cache (a
re-download) and any VM disk, and "regenerate the web page's images" should
not quietly cost an hour and a virtual machine somebody was using. Without it,
`make release` still rebuilds the image from scratch — it just keeps the cache.

Knobs: `MODEL=vm` `LEVEL=f` `MINUTES=12` `SPEED=8`.

### Everything, for every board

```sh
make all        # cache + build every board + register both UTM machines
```

Serial by necessity: every board's boot partition carries the same label, so
two builds cannot be mounted at once. This is the long one.

---

## Which runner: QEMU or UTM?

This is the decision that matters most, and it has a clean answer.

| | `make vm` (QEMU) | `make utm` (UTM) |
|---|---|---|
| Serial console | **a real tty on your terminal** | inside UTM's own window |
| Scriptable | yes — `expect`, pipes, redirection | yes, by typing into the window (`make utm-type`) |
| Recordable | yes — `asciinema` wraps it | not directly |
| Graphical desktop | a plain window | a proper app, clipboard, shared folder, NAT |
| Use it for | automation, capture, CI, `--check` | actually using the machine |

**Automate with QEMU. Live in UTM.** Everything in `make capture`, `make
video` and `make check` goes through `copal-vm.sh` for exactly one reason:
its serial console is a file descriptor, so a script can read and write it.

---

## Controlling UTM: what is possible, and what is not

Asked directly: **can UTM's tty input be controlled?** Yes — by typing into
the window (§2 below), which needs one Accessibility approval and then works
from a Makefile. What you cannot do is *open* its serial as a device, and the
reason is worth writing down because it looks like you should be able to.

UTM launches QEMU with the serial wired to a SPICE port:

```
-chardev spiceport,id=term0,name=com.utmapp.terminal.0 -serial chardev:term0
```

Not a pty. There is no device node and no socket to write bytes into; UTM's
own window is the only client that speaks to that port. Two things that look
like escape hatches are not:

- **`Serial:0:Mode = Ptty` in the VM's `config.plist`** is accepted and then
  ignored for this backend. Setting it changes nothing: QEMU is still
  launched with `spiceport`, and no new pty appears.
- **`utmctl attach`** is documented as *"Redirect the serial input/output to
  this terminal"* and is a stub. In UTM 4.7.4 it prints
  `WARNING: attach command is not implemented yet!` and exits.

So there are three real ways to make a UTM machine do something, in order of
how much they are worth:

### 1. Don't. Use QEMU for the part that must be scripted.

`copal-vm.sh` boots the same image, from the same file, with a genuine tty.
Anything you would have scripted against UTM can be scripted against that,
and the capture pipeline already does. UTM's advantages — clipboard, shared
folder, NAT, a window that survives the terminal closing — are all
interactive advantages, and none of them matter to a script.

### 2. Type into the window — `make utm-type`

**This is the answer to "can you control UTM's tty input".** You cannot open
its serial, but you can type into the window, and the characters reach the
guest's tty exactly as if a person had typed them.

```sh
make utm-type TEXT=root
make utm-type TEXT='sh /media/vda1/copal-init.sh'
make utm-type TEXT=f                 # a level, at the guided prompt
```

Each call raises the machine's serial window, types the line, and presses
Return. It touches that window and nothing else — no windows are moved, and
nothing is read back.

**The human step, and it happens once.** Sending keystrokes to another
application needs an Accessibility grant, which macOS records against the
process doing the asking. A terminal is a poor asker: the prompt does not
reliably appear, and a denial is remembered. So when it is refused, the
script is written to `build/copal-utm-type.applescript` and opened in Script
Editor — read it, press Cmd+R, approve the two prompts. Script Editor is
Apple-signed, asks cleanly, and is remembered; after that one approval,
`make utm-type` is silent and scriptable.

That is the whole trade: one dialog, once, in exchange for a UTM machine you
can drive from a Makefile.

`make layout-auto` is the batch version of the same mechanism: it arranges
the windows, waits for `login:` to appear in the console's *accessibility
text*, and types the whole opening sequence. It is how an unattended install
is started in UTM today.

`make layout --probe` answers, in about a second and while touching nothing,
whether UTM publishes its terminal text to accessibility on *this* Mac with
*this* UTM — which is the assumption the whole autotype rests on.

### 3. `utmctl exec` — the one that is not built yet, and should be

UTM already gives every machine a QEMU guest agent channel:

```
-device virtserialport,chardev=org.qemu.guest_agent,name=org.qemu.guest_agent.0
```

and `utmctl` exposes it:

```sh
utmctl exec  <vm> --cmd sh -c 'command'     # run something in the guest
utmctl exec  <vm> --input --cmd ...         # ...with stdin forwarded
utmctl file  <vm> ...                       # copy files in and out
utmctl ip-address <vm>                      # what address did it get
```

That is real programmatic control — better than keystrokes, because it
returns the command's exit status and output instead of hoping the right
characters landed in the right window.

**It needs `qemu-guest-agent` running inside the guest, and Copal does not
install it.** Alpine packages it. Adding it to a stage would make every UTM
machine scriptable with no Accessibility grant and no AppleScript at all,
and would also make `utmctl ip-address` work — which today is the reason
`utm-vm.sh ip` has to guess. This is the obvious next improvement to the UTM
path; it is written down here rather than done because it changes what gets
installed on every machine, which is a decision rather than a fix.

### The UTM commands that do work today

```sh
make utm                         # register (once) and start
utm/utm-vm.sh status  --target aarch64
utm/utm-vm.sh stop    --target aarch64
utm/utm-vm.sh refresh --target aarch64 --image build/copal-vm.img
utm/utm-vm.sh delete  --target aarch64
utm/utm-vm.sh share   --target aarch64 --share ~/Downloads/SharedVM
utm/utm-vm.sh progress --target aarch64   # how far the install has got
utm/utm-vm.sh log      --target aarch64   # follow the install transcript
utm/utm-vm.sh type     --target aarch64 --text root    # type into the console
```

`progress` and `log` reach the guest over **SSH**, not over the serial — which
is the other honest answer to "can you control it": once stage 1 has run and
the key is installed, the machine is reachable like any other machine, and
that is the supported way to drive an installed system.

---

## Finishing an install in UTM by hand

The intended flow when you want to watch it rather than record it:

1. `make utm` — registers the machine if needed, starts it.
2. In the UTM window: **Displays → Terminal 1** for the serial console.
3. Log in as `root` (no password on a fresh card).
4. `sh /media/vda1/copal-init.sh`
5. Choose a level: `s`, `m` or `f`. Then walk away.

Or drive those same four steps from the Makefile once the Accessibility
grant is in place:

```sh
make utm
sleep 20 && make utm-type TEXT=root
make utm-type TEXT='sh /media/vda1/copal-init.sh'
make utm-type TEXT=f
```

Stage 3 reboots once, on its own, and resumes. When it is done,
`utm/utm-vm.sh progress --target aarch64` will tell you how far it got
without your having to read the console.

---

## Capturing what happened

| Command | Produces | Notes |
|---|---|---|
| `make capture` | `install-cast.gif`, `guided-levels.gif` | records the serial console of a QEMU boot |
| `make video` | those plus `install.mp4` (`.webm` if ffmpeg can) | same cast, so the frames are provably identical |
| `make screens` | `screen-N.png` | QEMU `screendump`: the guest's real framebuffer |
| `make gallery` | `docs/gallery.html` | generated from `docs/media`, so it cannot list an image that is not there |

`make screens` is the only route to a picture of the **desktop**. A compositor
draws to a framebuffer, not to a serial console, so `asciinema` cannot see it;
QEMU's monitor can, headless, with nothing on your screen. It needs an image
that already has a desktop installed — it photographs one, it does not build
one.

**A caveat worth knowing before trusting `make release` unattended:** the
`expect` script that drives the install is timing-sensitive. A 25-minute run
once reached the installer but never matched the level prompt, while a
4-minute run on the same image matched it in 10.6 s. `cast-trim` reports when
a marker is missing and the caller currently only warns, so a release can
still ship a stale still. Check the output.

---

## Verifying before publishing or tagging

```sh
make verify        # reads the image, does not boot it
make verify-boot   # ...and boots it headless to a login prompt
```

Six questions, none of which anyone can answer from memory:

1. does the image carry a build stamp;
2. does that stamp name a source revision;
3. is that revision this working tree's `HEAD`;
4. was the tree clean when it was built, and is it clean now;
5. is `HEAD` behind its remote;
6. is the payload's Alpine version the one `copal-prep.sh` pins today.

It reads the stamp with `strings` rather than mounting the image — a verifier
should not hold a write-capable handle on the thing it is verifying, and a
stray mount here collides with a card already in a reader. It never fetches,
either: a script that mutates the repository it is checking, and fails on an
aeroplane, is the wrong shape. It reports what the last fetch knew and says so.

---

## Clearing up

| Command | Removes | Keeps |
|---|---|---|
| `make clean` | build artefacts | the payload cache, the UTM machines |
| `make distclean` | those **and** the cache | the UTM machines |
| `make purge` | those **and** both UTM machines and their disks | nothing |

`make purge` asks for a typed `yes`; `YES=1` skips the prompt, which is what
`make release PURGE=1` uses. It only ever touches the two machines named
`Copal-aarch64` and `Copal-x86_64` — any other UTM machine is left alone.
