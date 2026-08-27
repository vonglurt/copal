# COPAL LINUX -- build cards and images, and boot the VM.
#
# A thin front end over copal-prep.sh and copal-vm.sh, which remain the things
# that do the work: this only spells out the combinations worth having a name
# for, and is explicit about the state each one destroys.
#
#   make vm            build if needed, boot, serial console on this terminal
#   make fresh         delete the VM image and build it again from nothing
#   make check         boot headless, print a verdict, exit non-zero if it hung
#   make utm           register the VM with UTM and start it (utm-x86 for x86_64)
#   make layout        arrange the four UTM windows on screen
#   make layout-auto   the same, then log in and start the install
#   make answers       identity and root password for an unattended install
#   make sd-zero2      write a physical card for a Pi Zero 2 W
#   make img-pc        write a bootable disk image for a PC
#   make lint          syntax-check both scripts, including the generated one
#   make redeploy      inside the guest: install this checkout's installer onto
#                      the running machine and re-run stages (STAGES=16)
#   make space         what is here, what it costs, and which target removes it
#   make clean         empties build/, keeping build/cache. Reports what it freed
#   make distclean     clean, and the download cache with it
#
# Run `make` on its own for the full list.

# Everything generated lands under one directory, so the repository root holds
# only files that are tracked. copal-prep.sh takes BUILDDIR too, so an image
# written by the script and one written by make land in the same place.
#
# The cache lives inside it, at build/cache -- but the two are not the same
# thing and the clean targets treat them differently. Build output is worthless
# to anyone else and reproduced by building again; the cache is checksum-
# verified Alpine payloads that cost bandwidth rather than CPU to replace. So
# `make clean` empties build/ while stepping around the cache, and only
# `make distclean` takes both. See the cleaning section for how, and why the
# exclusion is written as an exclusion rather than a list.
BUILDDIR ?= build

# ONE build id per press of make, shared by every image that press produces.
#
# := not =, and that is the whole mechanism: a simply-expanded variable runs
# its shell once, when the Makefile is read, so `make all` stamps its nine
# images with the same eight characters instead of nine different ones. A
# recursively-expanded '=' would re-run od for every image and every reference,
# which is precisely the bug this avoids.
#
# Exported, so copal-prep.sh takes it from the environment rather than
# generating its own. A press is the unit of identity here: the images from one
# `make alldebug` are a set, and being able to see that is the point.
BUILD_ID := $(shell od -An -N4 -tx1 /dev/urandom | tr -d ' \n' | cut -c1-8)
export BUILD_ID
CACHEDIR ?= $(BUILDDIR)/cache

# MODEL FIRST, AND EVERY GENERATED NAME DERIVED FROM IT.
#
# These used to be constants, and the aarch64 name was the constant -- so
# `make fresh MODEL=vmx86` built an x86_64 image and wrote it to
# copal-vm.img, on top of the aarch64 one, with a name saying the opposite of
# what it held. `make auto MODEL=vmx86` did the same to the transcript. The
# only reason it was survivable is that nobody ran the two models on the same
# afternoon; the moment you want both machines at once it is a silent
# clobber, and the evidence it had already happened was sitting in build/ as
# a hand-made copal-prep-auto-x86.log beside the real one.
#
# Deriving them means the filename states the mode, two models never collide,
# and the defaults are unchanged for MODEL=vm -- copal-vm.img and
# copal-vm-check.log are exactly what they were.
MODEL    ?= vm
IMG      ?= $(BUILDDIR)/copal-$(MODEL).img
LOG      ?= $(BUILDDIR)/copal-$(MODEL)-check.log
AUTOLOG  ?= $(BUILDDIR)/copal-prep-auto-$(MODEL).log
MEM      ?= 2048
CPUS     ?= 2

PREP     := ./copal-prep.sh
VMRUN    := ./copal-vm.sh
VARS      = $(IMG:.img=-efivars.fd)

export MEM CPUS BUILDDIR CACHEDIR

# Board names are copal-prep.sh's, not a second vocabulary invented here: the
# stem goes straight through as MODEL, so `make sd-nonsense` gets that script's
# own list of what is valid rather than a different wrong answer from make.
# The one translation is the pi-prefixed spelling of the Zeros, because
# `sd-pizero2` is what fingers type and `zero2` is what the script calls it.
model_of = $(patsubst pizero%,zero%,$(1))

.DEFAULT_GOAL := help
.PHONY: alldebug build-all-debug imagedebug freshdebug purge \
	help menu flow targets boards configure require-tools vm graphical check \
        fresh auto image refresh utm utm-x86 layout layout-auto answers answers-show lint space clean distclean \
        all cache build-all release capture video screens verify gallery chain walkthrough release-cast logs utm-export install \
        redeploy redeploy-check

help:
	@printf '\nCopal Linux -- make targets\n\n'
	@printf '\033[1m  Start here\033[0m\n'
	@printf '  make menu       ./copal -- the front door: flow chart, targets, briefings\n'
	@printf '  make flow       the flow chart alone\n'
	@printf '  make targets    the target list, one per line   \033[2m(make boards is the same)\033[0m\n'
	@printf '  make configure  what this Mac has and what it is missing. Ends in a verdict\n'
	@printf '  bin/ls.sh       the same targets as one-line shell shortcuts, runnable\n'
	@printf '                  from any directory   \033[2m(bin/vm.sh, bin/sd.sh zero2, ...)\033[0m\n'
	@printf '\n'
	@printf '\033[1m  Booting the VM\033[0m\n'
	@printf '  make vm         boot %s, serial console on this terminal\n' '$(IMG)'
	@printf '                  builds it first if absent. Ctrl-A X quits, Ctrl-A C for the monitor.\n'
	@printf '  make graphical  the same, in a window, to watch i3 come up\n'
	@printf '  make check      boot headless, verdict, exit non-zero if no login prompt (log: %s)\n' '$(LOG)'
	@printf '  make utm        register the aarch64 machine with UTM and start it\n'
	@printf '  make utm-x86    the same for x86_64 -- \033[33mthe only way to boot that image\033[0m\n'
	@printf '  make layout     arrange the four VM windows on screen\n'
	@printf '  make layout-auto  the same, then log in and start the install\n'
	@printf '  make answers    identity and root password for an unattended install\n'
	@printf '                  Creates the VM only if there is not one already. Never replaces one.\n'
	@printf '\n'
	@printf '\033[1m  Building the VM image\033[0m\n'
	@printf '  make fresh      delete the image and build it from nothing.\n'
	@printf '                  \033[33mThis is the one to run after changing copal-prep.sh.\033[0m\n'
	@printf '  make auto       fresh, unattended -- answers the step gates itself (image only)\n'
	@printf '  make image      build %s only if absent. Never rebuilds.\n' '$(IMG)'
	@printf '\n'
	@printf '\033[1m  Cards and other boards\033[0m\n'
	@printf '  make sd-BOARD   write a physical card. Prompts for the disk and\n'
	@printf '                  keeps both typed ERASE confirmations.\n'
	@printf '  make img-BOARD  write copal-BOARD.img instead of a card\n'
	@printf '  make refresh    rewrite only the generated files on an existing card\n'
	@printf '                  (MODEL=%s -- set MODEL= to choose)\n' '$(MODEL)'
	@printf '\n'
	@printf '                  BOARD is any name copal-prep.sh takes:\n'
	@printf '                    \033[36mzero zero-w pi1 cm1\033[0m       armhf   (ARMv6)\n'
	@printf '                    \033[36mpi2b\033[0m                      armv7   (Pi 2B v1.1)\n'
	@printf '                    \033[36mzero2 pi3 cm3 pi2b-v12\033[0m    aarch64\n'
	@printf '                    \033[36mpi4 400 cm4 pi5\033[0m           aarch64\n'
	@printf '                    \033[36mpc pc32\033[0m                   x86_64 / x86 (UEFI)\n'
	@printf '                    \033[36mvm\033[0m                        aarch64 (QEMU/UTM)\n'
	@printf '                  pizero2 and pizero work too. e.g. \033[1mmake sd-zero2\033[0m\n'
	@printf '\n'
	@printf '\033[1m  Everything at once\033[0m\n'
	@printf '  make cache      download every architecture'"'"'s payload, build nothing\n'
	@printf '  make all        cache, build all %s boards, register both UTM machines\n' "$$(./copal targets | wc -l | tr -d ' ')"
	@printf '                  \033[33mSerial by necessity -- make -j cannot help here.\033[0m\n'
	@printf '  make alldebug   the same, with the log collection on in every image\n'
	@printf '                  \033[2mDEBUG=1d by default; make alldebug DEBUG=7d, or DEBUG=on for no deadline\033[0m\n'
	@printf '  make imagedebug one board (MODEL=%s), logging on   \033[2malso: make freshdebug\033[0m\n' '$(MODEL)'
	@printf '\n'
	@printf '\033[1m  Housekeeping\033[0m\n'
	@printf '  make lint       sh -n on copal-prep.sh and on the copal-init.sh it generates\n'
	@printf '  make redeploy   \033[2m(run this INSIDE the guest)\033[0m install this checkout onto the\n'
	@printf '                  machine you are on and re-run stages. \033[2mmake redeploy STAGES=16\033[0m\n'
	@printf '  make space      what is taking up room and which target removes it. Removes nothing\n'
	@printf '  make purge      everything: images, payloads, logs AND the UTM machines\n'
	@printf '                  \033[2mAsks first. Their virtual disks go too -- make purge YES=1 to skip the prompt\033[0m\n'
	@printf '  make clean      the images, EFI stores, logs, and the generated config that\n'
	@printf '                  carries the git identity, username and SSH key. Reports what it freed\n'
	@printf '  make distclean  clean, and the verified Alpine payloads in %s as well\n' '$(CACHEDIR)/'
	@printf '\n'
	@printf '  Variables: IMG MODEL MEM CPUS LOG   e.g.  make vm MEM=4096 CPUS=4\n\n'
	@printf '  \033[33mAn existing image is never rebuilt by `make vm`.\033[0m An interrupted install\n'
	@printf '  leaves copal-auto on the boot partition and resumes from there, so a\n'
	@printf '  half-finished image boots into the middle of stage 1 and skips what came\n'
	@printf '  before. Use `make fresh` whenever the result is meant to mean something.\n\n'

# The directory has to exist before script(1) can open a transcript in it, and
# an order-only prerequisite is the way to say "make sure it is there" without
# a fresh mtime on it counting as a reason to rebuild an image.
$(BUILDDIR):
	@mkdir -p $(BUILDDIR)

# ------------------------------------------------------------- front door ---
#
# ./copal is the thing to run first, and these are one target per flag it
# takes -- so make and the script do not become two vocabularies for the same
# three questions. They call the script and nothing else: a second copy of the
# target list here would be a second copy to get wrong.

menu:
	@./copal

flow:
	@./copal --flow

# 'boards' because that is what they are called everywhere else in this file --
# sd-BOARD, img-BOARD -- and 'targets' because that is what ./copal calls them.
targets boards:
	@./copal --targets

# -------------------------------------------------------------- configure ---
#
# What has to be present before any of this works, checked rather than assumed.
# Two kinds, and the difference is whether a miss is an error:
#
#   REQUIRED   copal-prep.sh cannot run without them. All five ship with macOS,
#              so a miss means something is genuinely wrong with the host --
#              and `script`, which `make auto` needs to supply a tty.
#   OPTIONAL   needed only by the path that uses them: qemu for `make vm`, UTM
#              for utm/utm-vm.sh. Reported, never fatal, because the card and
#              PC targets do not touch either.
#
# `make configure` is the human-readable form: it hands the machine profile to
# ./copal --check, which is where that list already lives, then adds what only
# make needs and ends in a verdict -- the one thing ./copal --check does not
# do, since it reports and always exits 0.
#
# `require-tools` is the same check with no narration, and every target that
# builds something takes it as an order-only prerequisite. That way a missing
# tool stops the build on line one with a single clear message, rather than
# four hundred megabytes in when curl turns out to be the thing that is absent.

REQUIRED_TOOLS = curl shasum bsdtar diskutil hdiutil script
# QEMU's aarch64 'virt' machine has no built-in firmware the way a PC does:
# EDK2 arrives as a pflash image inside the qemu formula. copal-vm.sh looks in
# these three places, so configure looks in the same three.
QEMU_FW = $(shell for f in "$$(brew --prefix qemu 2>/dev/null)/share/qemu/edk2-aarch64-code.fd" \
                           /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
                           /usr/local/share/qemu/edk2-aarch64-code.fd; \
                  do [ -f "$$f" ] && { echo "$$f"; break; }; done)

require-tools:
	@_missing=''; \
	for _t in $(REQUIRED_TOOLS); do \
	    command -v "$$_t" >/dev/null 2>&1 || _missing="$$_missing $$_t"; \
	done; \
	[ -z "$$_missing" ] || { \
	    printf '\033[31merror:\033[0m required tool(s) not found:%s\n' "$$_missing"; \
	    printf '       All of these ship with macOS. Run \033[1mmake configure\033[0m for the report.\n'; \
	    exit 1; }

configure:
	@./copal --check
	@printf '\033[1m  Additionally, for these make targets\033[0m\n\n'
	@for _t in script:'make auto -- supplies a tty to the step gates' \
	           qemu-system-aarch64:'make vm, graphical, check' \
	           qemu-img:'utm/utm-vm.sh create' ; do \
	    _n=$${_t%%:*}; _w=$${_t#*:}; \
	    if command -v "$$_n" >/dev/null 2>&1; then \
	        printf '  \033[32m[ok]\033[0m   %-22s %s\n' "$$_n" "$$_w"; \
	    else \
	        printf '  \033[33m[  ]\033[0m   %-22s %s \033[2m(brew install qemu)\033[0m\n' "$$_n" "$$_w"; \
	    fi; \
	done
	@if [ -n "$(QEMU_FW)" ]; then \
	    printf '  \033[32m[ok]\033[0m   %-22s %s\n' "edk2 firmware" "$(QEMU_FW)"; \
	else \
	    printf '  \033[33m[  ]\033[0m   %-22s %s\n' "edk2 firmware" \
	        "edk2-aarch64-code.fd not found -- ships with qemu"; \
	fi
	@if [ -x /Applications/UTM.app/Contents/MacOS/utmctl ]; then \
	    printf '  \033[32m[ok]\033[0m   %-22s %s\n' "utmctl" "utm/utm-vm.sh start and stop"; \
	else \
	    printf '  \033[33m[  ]\033[0m   %-22s %s\n' "utmctl" "absent -- only utm/utm-vm.sh needs it"; \
	fi
	@printf '\n'
	@$(MAKE) --no-print-directory require-tools \
	    && printf '\033[36m==>\033[0m \033[1mReady.\033[0m Every required tool is present.\n' \
	       && printf '    Cards and PC images need nothing else. The VM targets need qemu\n' \
	       && printf '    or UTM, and the lines above say which of those you have.\n\n'

# ---------------------------------------------------------------- booting ---

# No @ and no pipe on these: qemu takes this terminal for the serial console,
# and anything standing between it and the tty takes the keyboard away.
vm: image
	$(VMRUN) $(IMG)

graphical: image
	$(VMRUN) --graphical $(IMG)

check: image | $(BUILDDIR)
	$(VMRUN) --check --log $(LOG) $(IMG)

# --------------------------------------------------------------- building ---

# Deliberately NOT dependent on copal-prep.sh. Editing the script does not make
# the image out of date in a way make should act on by itself: rebuilding means
# destroying a card-sized file and sitting through an install. `make fresh` is
# the explicit way to say that, and the warning in `make help` says so.
image: $(IMG)

$(IMG): | require-tools $(BUILDDIR)
	MODEL=$(MODEL) $(PREP) --image $(IMG)

# One board, with logging on. The single-image counterpart of `make alldebug`.
imagedebug: | require-tools $(BUILDDIR)
	MODEL=$(MODEL) $(PREP) --debug=$(DEBUG) --image $(IMG)

fresh: | require-tools $(BUILDDIR)
	MODEL=$(MODEL) $(PREP) --fresh --image $(IMG)

freshdebug: | require-tools $(BUILDDIR)
	MODEL=$(MODEL) $(PREP) --fresh --debug=$(DEBUG) --image $(IMG)
	@printf '\n\033[36m==>\033[0m Built. Boot it with: make vm   (or: make check)\n'

# Unattended. copal-prep.sh gates each step on a read from /dev/tty, so this
# supplies a tty with script(1) and answers every gate with Enter.
#
# Image only, and safe only because of that: the two typed ERASE confirmations
# exist for cards and are skipped when the target is a file. Never point this
# at a device.
#
# The transcript decides the verdict, not the exit status. The feed has to be
# unbounded -- a fixed count is consumed before the gates are reached and the
# build dies on EOF at step 1 -- and an unbounded feed still writing when the
# child exits makes script(1) report `write master: Input/output error`, which
# has nothing to do with whether the build worked. So: ignore the status, then
# insist on the line copal-prep.sh prints only when it has finished.
#
# One caveat worth knowing before reading the result. The three `sudo fdisk -e`
# calls that set the MBR type bytes get no password this way, so 0xEF and 0x83
# stay unset. The image boots regardless -- EDK2 finds BOOTAA64.EFI by scanning
# the FAT filesystem -- but it is not byte-identical to an attended build.
auto: | require-tools $(BUILDDIR)
	@./copal build $(MODEL) --auto --out $(IMG)
	@printf '\033[36m==>\033[0m Built. Boot it with: make vm   (or: make check)\n'

refresh: | require-tools
	MODEL=$(MODEL) $(PREP) --refresh

# --------------------------------------------------------------------- UTM ---
#
# copal-prep.sh writes an image and stops there on purpose. A UTM machine is
# not a file in this repository: it is a bundle registered inside another
# application's sandbox container, it survives clean, distclean and deleting
# this checkout entirely, and a script whose job is "write a disk image" has no
# business quietly creating one. These targets exist so the step is still a
# single command -- named and asked for, rather than a side effect of building.
#
# `create` refuses to replace an existing machine without --force, which is the
# correct behaviour and would also make `make utm` fail the second time it ran.
# So create happens only when `status` reports there is no machine, and start is
# unconditional. Running either target twice is safe and destroys nothing.
#
# utm-x86 matters more than it looks. copal-vm.sh runs qemu-system-aarch64, so
# for the x86_64 image UTM is not one of two ways to boot it -- it is the only
# way, and until now it was the only boot route with no target behind it.

UTMRUN  := ./utm/utm-vm.sh
# The same name `IMG` derives to at MODEL=vmx86, and deliberately spelled the
# same way: if these two ever disagree, utm-x86 builds one file and every
# other target reads another.
X86IMG  ?= $(BUILDDIR)/copal-vmx86.img

# No rule of its own for $(X86IMG), and that is the point of deriving IMG from
# MODEL. It used to have one, and once IMG became $(BUILDDIR)/copal-$(MODEL).img
# the two spelled the same filename whenever MODEL=vmx86 -- two rules for one
# target, which make resolves by warning and silently keeping one. Recursing
# with MODEL overridden uses the single image rule instead, the same way
# distclean recurses into clean.

utm: image
	@$(UTMRUN) status --target aarch64 >/dev/null 2>&1 \
	    || $(UTMRUN) create --target aarch64 --image $(IMG)
	@$(UTMRUN) start --target aarch64
	@printf '\033[36m==>\033[0m Started. Find its address with: %s ip --target aarch64\n' '$(UTMRUN)'
	@printf '    \033[2m%s\033[0m\n' 'Serial console: the VM window toolbar -> Displays -> Serial 1'

# UTM keeps its own copy of the disk -- `create` converts the raw image into a
# qcow2 inside the bundle -- so an install done in UTM does NOT change
# $(IMG). This pulls it back out, which is what makes `make screens`,
# `make verify` and `make logs` see the system you actually installed rather
# than the pristine one they were built from.
#
# The machine has to be stopped: converting a disk out from under a running
# guest copies a half-written filesystem.
utm-export:
	@$(UTMRUN) stop --target aarch64 >/dev/null 2>&1 || true
	@$(UTMRUN) export --target aarch64 --image $(IMG)

# Boot the image with its console on THIS terminal, and say what to type. The
# install itself is hours and happens inside the guest -- this is only the
# door into it.
#
# QEMU rather than UTM on purpose: copal-vm.sh writes straight to $(IMG), so
# everything installed here is in the file that make screens photographs. In
# UTM it would land in UTM's own qcow2 instead (see utm-export).
install: image
	@printf '\n\033[1mThe install happens inside the guest.\033[0m Once it boots:\n\n'
	@printf '    login:  \033[36mroot\033[0m   (no password yet)\n'
	@printf '    run:    \033[36msh /media/vda1/copal-init.sh\033[0m\n'
	@printf '    pick:   \033[36mf\033[0m      server / medium / full monty\n\n'
	@printf '  Stage 3 reboots the guest by itself; let it come back.\n'
	@printf '  When it has finished, quit QEMU with \033[1mCtrl-A\033[0m then \033[1mX\033[0m,\n'
	@printf '  then run \033[36mmake screens\033[0m to photograph the desktop.\n\n'
	$(VMRUN) $(IMG)

# Arrange the four VM windows -- two serial consoles into the bottom corners,
# the two graphical ones pushed off the bottom edge but still clickable.
#
# Moving another app's windows needs an Accessibility grant that macOS records
# against the SENDING process, and a terminal is a poor sender: the prompt does
# not reliably appear and a denial is remembered. So when this is refused it
# opens the script in Script Editor for you to read and run -- which is the
# right order anyway for a script about to be given control of the desktop.
layout:
	@$(UTMRUN) layout

# The same, plus logging in as root on both serial consoles and starting the
# installer. Separate target rather than a variable, because the difference
# between the two is "tidy the desktop" and "begin an hour of work".
layout-auto:
	@$(UTMRUN) layout --autotype


# --------------------------------------------------------------- release ---
#
# The images on the web page, regenerated from a real install rather than
# refreshed by hand and hoped to still be true. Documentation that drifts from
# the thing it documents is worse than none, and screenshots drift silently --
# nothing fails when they go stale.
#
# WHAT IT ACTUALLY DOES. Builds a clean image, boots it, drives an install
# over the VM's serial console with expect, and records that console with
# asciinema; agg renders the cast to a GIF, and the stills are cut from the
# SAME recording rather than from a second boot. One install, one truth: two
# recordings of two installs disagree about hostname and timing, and a page
# whose images contradict each other reads as mocked up even when every frame
# is real.
#
# No screen recording is involved and nothing has to be watched. The install
# is a text transcript on a serial console, so the characters ARE the artifact
# -- see tools/capture-media.sh for why a video of a terminal is the wrong
# container for it.
#
# LEVEL and MINUTES are the two knobs: which install level to record (s, m or
# f) and how long to record for. A full install is hours; the default records
# the first twelve minutes, which is the part with anything to see.
LEVEL   ?= f
MINUTES ?= 12

# A RECORDING IS PUBLISHED; A BUILD IS NOT. copal-prep.sh offers this Mac's
# git identity as the default the target suggests, and stage 1 prints it --
# so a capture of a normal build puts a real name and a real email address
# into a GIF on a public web page. That is the same leak .gitignore exists to
# prevent, arriving by a route .gitignore cannot see.
#
# So a release build is given a neutral identity instead of this Mac's. It is
# not a redaction after the fact -- the identity never reaches the image, so
# there is nothing in the transcript to scrub and no way to forget.
PURGE ?= 0
CAPTURE_NAME  ?= Copal
CAPTURE_EMAIL ?= copal@example.invalid

capture:
	@tools/capture-media.sh --image $(IMG) --level $(LEVEL) --minutes $(MINUTES)

# The same recording, encoded as video as well as GIF. A GIF belongs on the
# web page -- it plays inline with no player and no controls -- and a video
# belongs everywhere else: a release page, a talk, anything that wants
# scrubbing or a length a GIF would be absurd at. Both come out of one cast,
# so they cannot show different installs.
video:
	@tools/capture-media.sh --image $(IMG) --level $(LEVEL) --minutes $(MINUTES) --video

# Real screenshots of the graphical console, taken by QEMU's own monitor
# rather than by a person with a camera. The serial console is text and a
# compositor does not draw to it, so this is the only automatic route to a
# picture of the desktop -- see tools/capture-screens.sh.
#
# Wants an image with a desktop ALREADY INSTALLED: it boots one and
# photographs what comes up, which is not the same job as installing it.
SHOTS    ?= 6
SHOTWAIT ?= 150
screens:
	@tools/capture-screens.sh --image $(IMG) --out docs/media \
	    --shots $(SHOTS) --wait $(SHOTWAIT)

# Is this image the one this checkout would build, and is this checkout the
# newest there is? Six questions nobody can answer from memory. --boot also
# runs it, which is the difference between "an image exists" and "a system
# was built".
verify:
	@tools/verify-build.sh --image $(IMG)

verify-boot:
	@tools/verify-build.sh --image $(IMG) --boot

# The gallery, generated from whatever docs/media actually holds rather than
# maintained by hand -- so it can never list an image the last capture
# renamed or never produced.
gallery:
	@python3 tools/build-gallery.py

# The guided version of `make release`: runs the automatic parts and stops at
# the two things a script cannot do on this Mac -- approving an Accessibility
# prompt, and photographing a desktop. Both are announced, waited for, and
# checked afterwards, so a skipped screenshot leaves an honest empty slot
# rather than a silent one. See docs/AUTOMATION.md.
# PURGE means the same thing here as everywhere else: 0 keeps the payload
# cache, 1 empties build/ and deletes the UTM machines first. It is a make
# VARIABLE, not a flag -- `make walkthrough --no-purge` cannot work, because
# make takes --no-purge for itself before the recipe ever sees it.
walkthrough:
	@tools/release-walkthrough.sh \
	    $(if $(filter 1,$(PURGE)),,--no-purge) \
	    --minutes $(MINUTES) --level $(LEVEL)

# Gather every log a run produced -- the Mac's build transcripts, the install
# transcript off the image's FAT partition, and the guest's own logs if it is
# reachable -- into build/logs/<timestamp>, with a summary that greps for the
# things worth worrying about. The image is attached and detached in a trap,
# so a collection never leaves a mount behind.
logs:
	@tools/collect-logs.sh --image $(IMG)

# Record the release pipeline ITSELF -- the Mac side, not the guest's install.
#
# The cast is written OUTSIDE build/, and that is not a preference: the first
# attempt recorded into build/ and `make release PURGE=1` deleted the file
# mid-recipe, because purging build/ is one of the steps being recorded. A
# recording of a process that destroys the directory it is being written to
# has to live somewhere that process does not touch.
RELEASE_CAST ?= /tmp/copal-release-pipeline.cast
release-cast:
	@asciinema rec --overwrite \
	    --command "make release PURGE=$(PURGE) MINUTES=$(MINUTES)" \
	    "$(RELEASE_CAST)"
	@agg --speed 6 --font-family "JetBrains Mono,Menlo,monospace" \
	    --theme "181818,d0daed,121212,ff723e,a0675d,fccf8a,666c93,87704f,92bbcc,d0daed,5e5e5e,ff723e,a0675d,fccf8a,666c93,87704f,92bbcc,fce2ab" \
	    "$(RELEASE_CAST)" docs/media/release-pipeline.gif
	@printf '\033[36m==>\033[0m docs/media/release-pipeline.gif\n'
	@python3 tools/build-gallery.py

# ----------------------------------------------------------------- chain ---
#
# WHICH TARGET CALLS WHICH. `make help` lists what each target does; this says
# how they fit together, which is the thing that is genuinely hard to see in a
# Makefile -- the recursive $(MAKE) calls inside recipes are invisible to
# `make -n` until you run it, and invisible to the help text entirely.
#
# Hand-written and therefore capable of drifting. It is checked by `make lint`
# against the targets that actually exist, so a chain naming a target that has
# been renamed fails rather than misleading.
chain:
	@printf '\n\033[1mCopal -- how the targets chain\033[0m\n\n'
	@printf '  \033[36mONE COMMAND, START TO FINISH\033[0m\n'
	@printf '    make release PURGE=1\n'
	@printf '      └─ purge YES=1        empty build/, delete both UTM machines\n'
	@printf '      └─ auto               ./copal build $(MODEL) --auto   (unattended, needs no tty)\n'
	@printf '      └─ verify             stamp vs checkout vs remote\n'
	@printf '      └─ video              record the install, render GIF + mp4 + stills\n'
	@printf '      └─ gallery            regenerate docs/gallery.html from docs/media\n\n'
	@printf '  \033[36mBUILDING\033[0m\n'
	@printf '    make image              build $(IMG) if it is missing\n'
	@printf '    make fresh              delete it first, build again      (asks at each step)\n'
	@printf '    make auto               the same, unattended               (script(1) supplies a tty)\n'
	@printf '    make all                cache + every board + both UTM machines\n\n'
	@printf '  \033[36mINSTALLING (hours, inside the guest)\033[0m\n'
	@printf '    make install            boot it in QEMU and tell you what to type\n'
	@printf '      then                  make screens   photograph the desktop\n'
	@printf '    \033[2mor install in UTM, then:\033[0m\n'
	@printf '    make utm                register + start a UTM machine\n'
	@printf '    make utm-export         pull UTM'"'"'s disk back into $(IMG)   <- do not skip\n\n'
	@printf '  \033[36mRUNNING IT\033[0m\n'
	@printf '    make vm                 QEMU, serial console on THIS terminal   <- scriptable\n'
	@printf '    make graphical          QEMU, a window\n'
	@printf '    make check              QEMU headless; exits non-zero if no login prompt\n'
	@printf '    make layout             arrange the UTM windows\n'
	@printf '    make layout-auto        ...and type the install into them (needs Accessibility)\n\n'
	@printf '  \033[36mCHECKING AND CAPTURING\033[0m\n'
	@printf '    make verify             six questions about image, source and remote\n'
	@printf '    make verify-boot        the same, and boot it\n'
	@printf '    make capture            record an install  (GIF + stills)\n'
	@printf '    make video              the same, plus mp4/webm\n'
	@printf '    make screens            QEMU screendump of an INSTALLED desktop\n'
	@printf '    make gallery            rebuild docs/gallery.html\n\n'
	@printf '  \033[36mCLEARING UP\033[0m\n'
	@printf '    make clean              build artefacts, keep the payload cache\n'
	@printf '    make distclean          those and the cache\n'
	@printf '    make purge              those and the UTM machines        (asks; YES=1 skips)\n\n'
	@printf '  \033[2mbin/*.sh are two-line shortcuts that exec the same targets, so they\n'
	@printf '  cannot disagree with this. bin/vm.sh is make vm, and so on.\033[0m\n\n'
	@printf '  Variables: MODEL=$(MODEL)  LEVEL=$(LEVEL)  MINUTES=$(MINUTES)  PURGE=0\n\n'

# A CLEAN IMAGE, and it has to be clean rather than merely current: the guided
# screen is the first thing the page shows, and it only appears on a machine
# that has never been installed -- no apkovl, root still a tmpfs. Capturing
# over a half-built image records the resume path instead, which is a
# different and much less interesting screen.
#
# `auto`, not `fresh`: both build, but fresh gates each step on a read from
# /dev/tty and there is no terminal in a release run. auto supplies one with
# script(1), which is the whole reason that target exists. The image is
# removed first so auto has nothing to resume from.
# PURGE=1 empties build/ and deletes the UTM machines first. Off by default,
# and that default is deliberate: purge destroys the payload cache (a
# re-download) and any VM disk, and "regenerate the web page's images" should
# not quietly cost somebody an hour and a virtual machine they were using.
# `make release PURGE=1` is the from-nothing version, and it says so.
release: | require-tools $(BUILDDIR)
	@printf '\033[36m==>\033[0m \033[1mRelease capture\033[0m -- a clean image, then a recorded install\n'
	@if [ "$(PURGE)" = 1 ]; then \
	    printf '\033[36m==>\033[0m PURGE=1 -- emptying build/ and removing the UTM machines\n'; \
	    $(MAKE) --no-print-directory purge YES=1; \
	fi
	@rm -f $(IMG)
	@CFG_GIT_NAME='$(CAPTURE_NAME)' CFG_GIT_EMAIL='$(CAPTURE_EMAIL)' \
	    $(MAKE) --no-print-directory auto MODEL=$(MODEL)
	@$(MAKE) --no-print-directory verify
	@$(MAKE) --no-print-directory video
	@$(MAKE) --no-print-directory gallery
	@printf '\033[36m==>\033[0m Media regenerated in docs/media. Review, then commit.\n'

# Collect the answers an unattended install needs -- identity, login name, and
# the root password, which is the one thing setup-alpine has no answer-file
# variable for and so the one thing that has always stopped an unattended
# install dead.
#
# The password is stored as a SHA-512 crypt hash, never in the clear. The
# default is 'hunter2', a joke password kept only so automated testing has one
# it knows. It is not a toy machine: sshd runs from stage 1, the login user
# shares root's password, and a build with no SSH key installed leaves that
# user reachable over the network with it. Root over SSH is always refused,
# and an installed key -- the default, taken from this Mac -- turns password
# authentication off, which is what makes 'hunter2' survivable rather than
# sensible. Set a real one for anything you are not throwing away today.
answers:
	@tools/copal-answers.sh

# What is on file now, with the hash withheld.
answers-show:
	@tools/copal-answers.sh --show


utm-x86:
	@$(MAKE) --no-print-directory image MODEL=vmx86
	@$(UTMRUN) status --target x86_64 >/dev/null 2>&1 \
	    || $(UTMRUN) create --target x86_64 --image $(X86IMG)
	@$(UTMRUN) start --target x86_64
	@printf '\033[36m==>\033[0m Started. Emulated by TCG, so expect it to be slow.\n'
	@printf '    \033[2m%s\033[0m\n' 'Serial console is on ttyS0 here, not ttyAMA0.'

# --------------------------------------------------- everything at once ---
#
# Thin, and deliberately so. `./copal all` is where this lives now -- the
# caching, the nine serial builds, the two UTM machines -- because the same job
# spelled once as a make target and again as a shell verb is two things to keep
# in step. make keeps the name people already type; copal does the work.
#
# .NOTPARALLEL is not decoration. Every board's boot partition carries the same
# label, so two builds cannot mount at once and copal-prep.sh now refuses when
# the mount point is not its own. `make -j all` would not be faster; it would
# stop partway with a confusing error, so parallelism is disabled here rather
# than diagnosed later.
.NOTPARALLEL: all alldebug cache build-all build-all-debug

all:
	@./copal all

# The same thing with the log collection switched on in every image.
#
# DEBUG is a duration, not a boolean, and it defaults to one day rather than
# "for ever". A card built for debugging is usually built to answer one
# question, and logging that has to be remembered to be switched off is
# logging that stays on for the life of the machine. Override it when the
# question needs longer:
#
#     make alldebug DEBUG=7d      a week
#     make alldebug DEBUG=on      no deadline, switch it off by hand
#
# Everything lands in /var/log/copal on the built machine, readable over ssh.
# `doas copal-debug off` turns it off early; `copal-debug bundle` packs it up.
DEBUG ?= 1d

# Set to 1 to skip purge's confirmation prompt.
YES ?=

alldebug:
	@./copal all --debug=$(DEBUG)

build-all-debug:
	@./copal build all --debug=$(DEBUG)

cache:
	@./copal cache all

build-all:
	@./copal build all

# ------------------------------------------------------- cards and boards ---

# A physical card. No --image, so copal-prep.sh picks the disk and asks for
# both typed confirmations -- which is the entire safety model for this path
# and is not bypassed here.
sd-%: | require-tools
	@printf '\033[36m==>\033[0m Card for MODEL=%s. copal-prep.sh will ask which disk.\n' '$(call model_of,$*)'
	MODEL=$(call model_of,$*) $(PREP)

# The same board, written to a file. Named for the board so several can coexist
# -- copal-zero2.img beside copal-pc.img -- rather than all colliding on IMG.
img-%: | require-tools $(BUILDDIR)
	MODEL=$(call model_of,$*) $(PREP) --image $(BUILDDIR)/copal-$(call model_of,$*).img

fresh-img-%: | require-tools $(BUILDDIR)
	MODEL=$(call model_of,$*) $(PREP) --fresh --image copal-$(call model_of,$*).img

# --------------------------------------------------------------- checking ---

# copal-init.sh only exists as a heredoc until a card is written, so a syntax
# error in it survives every check that reads copal-prep.sh alone -- and lands
# on the hardware. Extract it and check it as the file it becomes.
#
# bin/ is checked here too, for the one failure a shortcut can have that is
# all its own: naming a target this file no longer defines. The shortcuts are
# two lines each and carry no logic to get wrong, but they do carry a target
# name, and a name is exactly the kind of thing that goes stale quietly. The
# check reads the target out of each script's `exec make` line and looks for
# it among the targets defined below, so renaming one here fails the lint
# rather than leaving a shortcut that only fails when somebody runs it.
lint: | $(BUILDDIR)
	@sh -n $(PREP) && printf '  ok      copal-prep.sh\n'
	@sh -n $(VMRUN) && printf '  ok      copal-vm.sh\n'
	@sh -n fetch-minivmac.sh && printf '  ok      fetch-minivmac.sh\n'
	@sed -n "/^cat > \"\$$MNT\/copal-init.sh\" <<'COPALINIT'$$/,/^COPALINIT$$/p" $(PREP) \
	    | sed '1d;$$d' > $(BUILDDIR)/.copal-init.lint.sh
	@test -s $(BUILDDIR)/.copal-init.lint.sh \
	    || { printf '\033[31merror:\033[0m could not extract copal-init.sh from $(PREP)\n'; \
	         rm -f $(BUILDDIR)/.copal-init.lint.sh; exit 1; }
	@sh -n $(BUILDDIR)/.copal-init.lint.sh \
	    && printf '  ok      copal-init.sh (generated, %s lines)\n' "$$(wc -l < $(BUILDDIR)/.copal-init.lint.sh | xargs)"
	@rm -f $(BUILDDIR)/.copal-init.lint.sh
	@for _s in bin/*.sh; do sh -n "$$_s" || exit 1; done; \
	    printf '  ok      bin/*.sh (%s shortcuts)\n' "$$(ls bin/*.sh | wc -l | xargs)"
	@_names=$$(grep -E '^[A-Za-z0-9_%.-][A-Za-z0-9_%. -]*:' Makefile \
	           | sed 's/:.*//' | tr ' ' '\n' | sort -u); \
	_bad=''; \
	for _s in bin/*.sh; do \
	    _t=$$(sed -n 's/^exec make "\{0,1\}\([A-Za-z0-9_-]*\).*/\1/p' "$$_s" | head -1); \
	    [ -n "$$_t" ] || continue; \
	    case "$$_t" in *-) _t="$${_t}%" ;; esac; \
	    printf '%s\n' "$$_names" | grep -qx -- "$$_t" \
	        || _bad="$$_bad $$(basename "$$_s")->$$_t"; \
	done; \
	[ -z "$$_bad" ] || { \
	    printf '\033[31merror:\033[0m shortcut names a target this Makefile does not define:%s\n' "$$_bad"; \
	    exit 1; }; \
	printf '  ok      every shortcut names a real target\n'

# ------------------------------------------------------------- redeploying ---
#
# EVERY OTHER TARGET IN THIS FILE RUNS ON THE MAC AND WRITES A CARD. This one
# runs on the machine the card made, from the checkout stage 7 puts at
# ~/code/copal, and it is the loop that was missing: edit a stage, see it, on
# the machine itself, without writing an image or pushing a commit.
#
#     make redeploy               install this checkout's installer, then the menu
#     make redeploy STAGES=16     ...and re-run stage 16, unattended
#     make redeploy STAGES=4,16   several, in that order
#     make redeploy-check         say what would change, change nothing
#     make redeploy PULL=1        pull first, without being asked
#     make redeploy PULL=0        never ask, never pull
#
# WHAT IT ACTUALLY DOES, because none of it is magic:
#
#   0. Looks at the checkout: which branch, whether it is dirty, and whether
#      the tracking branch has commits this tree does not. If it is behind, it
#      ASKS before pulling -- because the reason to run this target is usually
#      an edit you have not committed, and a target that silently pulled on
#      top of that would be reaching into your working tree. PULL=1 answers
#      yes without asking, PULL=0 skips the question, and no tty is PULL=0.
#   1. sh -n on copal-prep.sh, and on the copal-init.sh extracted out of it.
#      A syntax error in the heredoc survives every check that reads the
#      generator alone, and this target's whole job is to install that heredoc.
#   2. `copal -U --from .`, which extracts it again, checks it parses, backs
#      up the installed copy as copal-init.sh.bak and writes the new one onto
#      the boot partition, remounting it read-write if it has to.
#   3. `copal --stage $(STAGES) --auto` if STAGES is set -- every question in
#      those stages answered automatically, which is what you want from a
#      Makefile and not what you want at a terminal.
#
# Nothing here is destructive in a way a rebuild is: the stages are the same
# re-runnable stages the menu offers, and stage 16 moves any config it
# replaces into ~/copal-theme-backups/ rather than deleting it.
#
# THE GUARD IS THE POINT of the first three lines. Running this on the Mac
# would find no boot partition and no copal, and the failure would be some
# confusing thing about /boot rather than "you are on the wrong machine".
STAGES ?=

# Unset means "ask, if there is somebody to ask". 1 pulls, 0 does not.
PULL ?=

# doas rather than sudo: Copal locks root in stage 13 and doas is what it
# installs. Empty when already root, so this works from a root shell too.
DOAS = $(shell [ "$$(id -u)" = 0 ] || command -v doas 2>/dev/null || command -v sudo 2>/dev/null)

define GUEST_GUARD
	@_b=''; for _d in /boot /media/*; do [ -f "$$_d/answers.txt" ] && { _b="$$_d"; break; }; done; \
	if [ -z "$$_b" ]; then \
	    printf '\033[31merror:\033[0m this target runs INSIDE a Copal machine, not on the Mac.\n'; \
	    printf '  No answers.txt under /boot or /media/*, so there is no Copal install here.\n'; \
	    printf '  On the Mac you want: \033[36mmake fresh\033[0m (build an image) or \033[36mmake vm\033[0m (boot one).\n'; \
	    printf '  In the guest: \033[36mcd ~/code/copal && make redeploy\033[0m\n'; \
	    exit 1; \
	fi; \
	printf '  boot partition  %s\n' "$$_b"
endef

# WHERE THIS CHECKOUT STANDS, before anything is installed from it. Reported
# always, because "I redeployed and my change was not in it" is nearly always
# one of these three lines -- wrong branch, uncommitted edit, or a tree that
# was never the tree you thought.
#
# git fetch is given a timeout: a guest with no network yet is the normal case
# on a fresh install, and a redeploy must not hang for two minutes on a DNS
# lookup before doing the local work it could always have done.
# STOPFILE is how one recipe line tells the next one not to bother. Each line
# of a recipe is its own shell, so an `exit 0` after the pull would end that
# line and nothing else -- make would carry on and install anyway. A file is
# the smallest thing that crosses that boundary. Cleared at the start of every
# run so a killed one cannot leave a stale veto behind.
STOPFILE = /tmp/.copal-redeploy-stop

define GIT_STATE
	@rm -f $(STOPFILE)
	@if git -C "$(CURDIR)" rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
	    _br=$$(git -C "$(CURDIR)" rev-parse --abbrev-ref HEAD 2>/dev/null); \
	    _sh=$$(git -C "$(CURDIR)" rev-parse --short HEAD 2>/dev/null); \
	    _dirty=$$(git -C "$(CURDIR)" status --porcelain 2>/dev/null | wc -l | tr -d ' '); \
	    printf '  checkout        %s @ %s' "$$_br" "$$_sh"; \
	    [ "$$_dirty" = 0 ] && printf '\n' || printf ' \033[33m(%s file(s) with local changes)\033[0m\n' "$$_dirty"; \
	else \
	    printf '  checkout        \033[33mnot a git checkout -- nothing to pull\033[0m\n'; \
	fi
endef

# The pull, offered rather than done. Three ways it declines without asking:
# not a git tree, no tracking branch, or nothing to pull.
#
# A DIRTY TREE IS NOT AN ERROR HERE, it is the usual reason to be running this
# at all -- so it is reported and the pull is not offered, rather than the
# other way round. Stash or commit first if you did want both.
#
# AND IT STOPS AFTER PULLING. A pull can change this Makefile, and make has
# already read the old one: the recipe running now is the previous version,
# and carrying on would install a tree that make itself is out of step with.
# So it says what happened and asks for the command again, which costs one
# line of typing and cannot be wrong.
define GIT_PULL
	@if ! git -C "$(CURDIR)" rev-parse --is-inside-work-tree >/dev/null 2>&1; then :; \
	elif [ "$(PULL)" = 0 ]; then :; \
	elif ! git -C "$(CURDIR)" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then \
	    printf '  upstream        \033[2mnone -- this branch tracks nothing, so nothing to pull\033[0m\n'; \
	elif [ -n "$$(git -C "$(CURDIR)" status --porcelain 2>/dev/null)" ]; then \
	    printf '  upstream        \033[2mnot checked: local changes here, which is usually the point\033[0m\n'; \
	else \
	    _to=''; command -v timeout >/dev/null 2>&1 && _to='timeout 20'; \
	    $$_to git -C "$(CURDIR)" fetch --quiet 2>/dev/null || \
	        printf '  upstream        \033[2mcould not fetch (no network?) -- using what is here\033[0m\n'; \
	    _behind=$$(git -C "$(CURDIR)" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0); \
	    if [ "$$_behind" -gt 0 ] 2>/dev/null; then \
	        _u=$$(git -C "$(CURDIR)" rev-parse --abbrev-ref '@{u}'); \
	        printf '  upstream        \033[33m%s is %s commit(s) ahead of this tree\033[0m\n' "$$_u" "$$_behind"; \
	        _do="$(PULL)"; \
	        if [ -z "$$_do" ]; then \
	            if [ -t 0 ]; then \
	                printf '  pull them first? [y/N] '; read _a </dev/tty || _a=n; \
	                case "$$_a" in [Yy]*) _do=1 ;; *) _do=0 ;; esac; \
	            else \
	                _do=0; \
	                printf '  \033[2mnot asking (no terminal) -- make redeploy PULL=1 to pull\033[0m\n'; \
	            fi; \
	        fi; \
	        if [ "$$_do" = 1 ]; then \
	            git -C "$(CURDIR)" pull --ff-only || { \
	                printf '\033[31merror:\033[0m pull failed -- sort the checkout out first\n'; exit 1; }; \
	            : > $(STOPFILE); \
	            printf '\n  Pulled. \033[33mRun the same command again\033[0m -- make read the old\n'; \
	            printf '  Makefile before the pull, so this one stops here rather than\n'; \
	            printf '  installing a tree it is out of step with.\n\n'; \
	            exit 0; \
	        fi; \
	    fi; \
	fi
endef

redeploy-check: lint
	$(GUEST_GUARD)
	$(GIT_STATE)
	@if command -v copal >/dev/null 2>&1; then \
	    $(DOAS) copal --check --from "$(CURDIR)"; \
	else \
	    printf '\033[33mnote:\033[0m no "copal" front door installed -- redeploy would run the\n'; \
	    printf '  extracted copal-init.sh straight from /tmp instead.\n'; \
	fi

redeploy: lint
	$(GUEST_GUARD)
	$(GIT_STATE)
	$(GIT_PULL)
	@if [ -f $(STOPFILE) ]; then rm -f $(STOPFILE); exit 0; fi; \
	if command -v copal >/dev/null 2>&1; then \
	    $(DOAS) copal -U --from "$(CURDIR)" || exit 1; \
	    if [ -n "$(STAGES)" ]; then \
	        printf '\n  Running stage(s) %s, unattended.\n\n' '$(STAGES)'; \
	        exec $(DOAS) copal --stage "$(STAGES)" --auto; \
	    else \
	        printf '\n  Installed. Now: \033[36mcopal\033[0m for the menu, or\n'; \
	        printf '        \033[36mmake redeploy STAGES=16\033[0m to re-run a stage straight away.\n\n'; \
	    fi; \
	else \
	    printf '  no "copal" front door here -- running the extracted installer from /tmp\n'; \
	    sed -n "/^cat > .*copal-init\.sh\" <<.COPALINIT.$$/,/^COPALINIT$$/p" $(PREP) \
	        | sed '1d;$$d' > /tmp/copal-init.redeploy.sh; \
	    test -s /tmp/copal-init.redeploy.sh || { printf '\033[31merror:\033[0m extraction failed\n'; exit 1; }; \
	    if [ -n "$(STAGES)" ]; then \
	        exec $(DOAS) sh /tmp/copal-init.redeploy.sh --stage "$(STAGES)" --auto; \
	    else \
	        exec $(DOAS) sh /tmp/copal-init.redeploy.sh; \
	    fi; \
	fi

# --------------------------------------------------------------- cleaning ---
#
# Three levels, and what separates them is the cost of undoing them:
#
#   make space      removes nothing. Says what is here and which target takes it
#   make clean      build output, logs and generated config. Costs a rebuild
#   make distclean  clean, and the payloads too. Costs a re-download as well
#
# clean deliberately removes more than build output, and this is the reason.
# copal-prep.sh writes a handful of small files that carry the git identity it
# read from THIS Mac's git config, the admin username, and the SSH public key --
# copal.conf, copal-git, answers.txt, usercfg.txt, authorized_keys -- and the
# build transcripts quote all three back verbatim:
#
#     ==> Git identity offered: Real Name <real@address> -- stage 1 asks
#     ==> Authorised key: ssh-ed25519 real@address (from ~/.ssh/id_ed25519.pub)
#
# None of it is a password and nothing authenticates with it. It is still a real
# name and a real address belonging to whoever wrote the card, sitting in a
# working copy of a public repository. .gitignore already refuses to commit
# them; the point of removing them here is that a file nobody deleted is a file
# that gets copied somewhere else eventually -- into a tarball, an issue
# attachment, a `cp -r` of the folder onto a shared disk.
#
# Sizes are `du`, never `ls`. THE IMAGES ARE SPARSE: a 64g image reports 64 GB
# to `ls -lh` and occupies only what has been written to it -- about 550 MB
# fresh, 15-25 GB after a full fifteen-stage run. Reporting the ceiling would
# make every one of these numbers a lie by two orders of magnitude.

# Everything in $(BUILDDIR) that is NOT the cache. Note what this is: an
# exclusion of one name, not a list of things to remove. Anything a future
# target drops into build/ is cleaned by default and nobody has to remember to
# add it here -- which is the property the old glob list never had, and how
# transcripts quoting a real name survived several rounds of cleaning.
#
# find, because a shell glob cannot express "except". -mindepth/-maxdepth 1 so
# it names the entries and not their contents; rm -rf does the recursion.
FIND_BUILT = find $(BUILDDIR) -mindepth 1 -maxdepth 1 ! -name cache 2>/dev/null
# The same output, in the places versions before build/ existed left it -- the
# repository root, and a top-level work/. Kept so an existing working copy gets
# genuinely cleaned rather than half-cleaned.
LEGACY   = copal-*.img copal-*-efivars.fd efivars.fd .copal-init.lint.sh \
           copal-prep-auto*.log copal-vm-check.log run-log-*.txt *.log
# Generated per-machine configuration -- the same list .gitignore carries, and
# deliberately the same list, so the two cannot drift apart.
SECRETS  = copal.conf copal-git copal-repos answers.txt usercfg.txt \
           authorized_keys firstrun.log copal-auto copal-timings
# Finder droppings. Not big, but they are folder clutter and they travel.
CRUFT    = .DS_Store ._* .Spotlight-V100 .Trashes

# Set to 0 by distclean, which is about to remove the cache and should not
# first advise keeping it.
CLEAN_HINT ?= 1

# $(call) splits its arguments on commas, so a literal one has to arrive as a
# variable. Only used by the size_row labels.
comma := ,

# One row of the space report. Argument 2 is a SHELL COMMAND that prints paths,
# one per line -- not a glob -- because "everything except the cache" cannot be
# written as a glob and every row should go through the same code.
#
# du and never ls: the images are sparse, and ls reports the ceiling.
define size_row
	@_f=$$($(2)); \
	if [ -n "$$_f" ]; then \
	    printf '  %-34s %9s   \033[2m%s\033[0m\n' '$(1)' \
	        "$$(du -shc $$_f 2>/dev/null | tail -n1 | cut -f1)" '$(3)'; \
	else \
	    printf '  %-34s %9s   \033[2m%s\033[0m\n' '$(1)' '--' 'nothing here'; \
	fi
endef

space:
	@printf '\n\033[1mWHAT IS IN THIS FOLDER\033[0m\n\n'
	@printf '  \033[2m%s\033[0m\n' 'Measured with du -- what is on disk, not what ls claims. The images'
	@printf '  \033[2m%s\033[0m\n\n' 'are sparse: 64 GB apparent, and only what has been written to them.'
	$(call size_row,$(BUILDDIR)/ -- images$(comma) EFI$(comma) logs,$(FIND_BUILT),make clean)
	$(call size_row,$(CACHEDIR)/ -- Alpine downloads,ls -d $(CACHEDIR) 2>/dev/null,make distclean)
	$(call size_row,Left loose by older builds,ls -d $(LEGACY) work 2>/dev/null,make clean)
	$(call size_row,Generated config -- identity,ls -d $(SECRETS) 2>/dev/null,make clean)
	$(call size_row,macOS metadata,ls -d $(CRUFT) 2>/dev/null,make clean)
	$(call size_row,minivmac/ -- emulator working set,ls -d minivmac 2>/dev/null,nothing -- see below)
	@printf '\n'
	$(call size_row,Everything above,ls -d $(BUILDDIR) $(LEGACY) work $(SECRETS) $(CRUFT) 2>/dev/null,make distclean)
	@printf '\n  \033[2m%s\033[0m\n' 'Registered UTM machines live in UTM'"'"'s own container, not here, and'
	@printf '  \033[2m%s\033[0m\n' 'no make target touches them: utm/utm-vm.sh delete --target aarch64'
	@printf '\n  \033[2m%s\033[0m\n' 'minivmac/ is left alone on purpose. fetch-minivmac.sh --rom copies in a'
	@printf '  \033[2m%s\033[0m\n' 'ROM dumped from a Macintosh Plus, and that is not re-downloadable. Remove'
	@printf '  \033[2m%s\033[0m\n\n' 'it by hand if you mean to.'

# work/ is in the removal list because that is where the cache used to live,
# at the top level. A working copy from before the move keeps it, and leaving
# it behind would mean two caches and a confusing space report.
clean:
	@_f=$$($(FIND_BUILT); ls -d $(LEGACY) work $(SECRETS) $(CRUFT) 2>/dev/null); \
	if [ -z "$$_f" ]; then \
	    printf '\033[36m==>\033[0m Already clean -- nothing to remove.\n'; \
	else \
	    _sz=$$(du -shc $$_f 2>/dev/null | tail -n1 | cut -f1); \
	    rm -rf $$_f; \
	    rmdir logs 2>/dev/null || true; \
	    printf '\033[36m==>\033[0m Purged \033[1m%s/\033[0m -- images, EFI variable stores and\n' '$(BUILDDIR)'; \
	    printf '    transcripts -- along with any generated config that carried the\n'; \
	    printf '    identity. \033[1m%s reclaimed.\033[0m\n' "$$_sz"; \
	fi
	@[ "$(CLEAN_HINT)" = 1 ] || exit 0; \
	if [ -d $(CACHEDIR) ]; then \
	    printf '    \033[2m%s\033[0m\n' '$(CACHEDIR)/ kept -- verified payloads, and a download to replace.'; \
	    printf '    \033[2m%s\033[0m\n' 'make distclean takes it too.'; \
	fi; \
	printf '    \033[2m%s\033[0m\n' 'UTM machines kept -- utm/utm-vm.sh delete --target aarch64'

# Recursive rather than a plain prerequisite, so clean can be told to skip the
# "cache kept" hint -- printing it one line before removing the cache would be
# a small lie, and the hints are the reason anyone reads this output at all.
#
# The case is a de-duplication, not a formality. By default CACHEDIR sits
# INSIDE BUILDDIR, and naming both to `du -shc` counts the cache twice: the
# first run of this reported 50M for a 25M cache. Since clean has already
# emptied everything else, the size of BUILDDIR alone is the size of the cache
# -- and CACHEDIR is only named separately when someone has moved it out.
#
# The patterns are written (build/*) rather than build/*) on purpose: make
# collapses this recipe onto one line, and a bare case pattern's unbalanced ')'
# inside $( ) is a syntax error in bash. The leading paren is POSIX and it
# balances.
# purge -- start from nothing, VMs included.
#
# distclean stops at this checkout: it removes images, payloads and
# transcripts, and leaves the registered UTM machines alone, because a machine
# inside another application's sandbox container is not this repository's to
# delete as a side effect. purge is the target that says delete them anyway --
# named, asked for, and confirmed.
#
# The virtual disks go with them. That is the whole point and it is why this
# asks: a VM here is a thing you rebuild in an hour from an image you also
# rebuild, so nothing in one is precious -- but "nothing in one is precious"
# is a judgement about THIS project, not a property of virtual machines, and
# a target that quietly destroyed them would be wrong on any other.
#
# ONLY THE MACHINES THIS REPOSITORY MAKES, BY EXACT NAME. PURGE_VMS is the
# whole list, and utm-vm.sh resolves each --target to one bundle whose name is
# spelled out here -- so a machine you built by hand, or named anything else,
# or that merely has "Copal" somewhere in its title, is not matched and is not
# touched. Nothing here globs, searches, or deletes by pattern: a target that
# removes virtual machines has no business guessing which ones.
#
# YES=1 skips the prompt, for a script that has already decided.
PURGE_VMS = aarch64:Copal-aarch64 x86_64:Copal-x86_64
purge:
	@printf '\033[1mThis removes, permanently:\033[0m\n'
	@printf '  %s/ -- every image, payload, transcript and harvested log\n' '$(BUILDDIR)'
	@for _p in $(PURGE_VMS); do \
	    _t=$${_p%%:*}; _n=$${_p#*:}; \
	    $(UTMRUN) status --target $$_t >/dev/null 2>&1 \
	        && printf '  UTM machine %s -- and its virtual disk\n' "$$_n"; \
	done; true
	@printf '  \033[2mOnly those exact names. Any other UTM machine is left alone.\033[0m\n' 
	@printf '\n  \033[2mThe images take about an hour to rebuild; the payloads re-download.\033[0m\n'
	@printf '  \033[2mAnything only on a VM disk is gone for good.\033[0m\n\n'
	@if [ "$(YES)" != 1 ]; then \
	    printf '\033[33mType yes to delete all of it: \033[0m'; \
	    read _r < /dev/tty || _r=''; \
	    [ "$$_r" = yes ] || { printf '\033[36m==>\033[0m Aborted -- nothing removed.\n'; exit 1; }; \
	fi; \
	for _p in $(PURGE_VMS); do \
	    _t=$${_p%%:*}; _n=$${_p#*:}; \
	    $(UTMRUN) status --target $$_t >/dev/null 2>&1 || continue; \
	    $(UTMRUN) stop --target $$_t >/dev/null 2>&1 || true; \
	    $(UTMRUN) delete --target $$_t --name "$$_n" --force || \
	        printf '\033[33mwarning:\033[0m could not delete %s\n' "$$_n"; \
	done; \
	$(MAKE) --no-print-directory distclean
	@printf '\033[36m==>\033[0m \033[1mPurged.\033[0m Rebuild with: make alldebug\n'

distclean:
	@$(MAKE) --no-print-directory clean CLEAN_HINT=0
	@_f=$$(ls -d $(BUILDDIR) 2>/dev/null; \
	       case "$(CACHEDIR)/" in ($(BUILDDIR)/*) ;; (*) ls -d $(CACHEDIR) 2>/dev/null ;; esac); \
	if [ -z "$$_f" ]; then \
	    printf '\033[36m==>\033[0m No downloaded payloads to remove.\n'; \
	else \
	    _sz=$$(du -shc $$_f 2>/dev/null | tail -n1 | cut -f1); \
	    rm -rf $$_f; \
	    printf '\033[36m==>\033[0m Removed the verified Alpine payloads and GRUB ISOs.\n'; \
	    printf '    \033[1m%s reclaimed.\033[0m The next build downloads them again.\n' "$$_sz"; \
	fi
