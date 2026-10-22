# Attributions

Show Mode is built on other people's work. This file lists what that work is, who did
it, and what it is doing here.

It is generated — the master lists live in the `stoatworks-backend` repo and are
pushed out by `scripts/sync-attributions.py`. Edit it there, not here.

## Work we checked ourselves against

No code was taken from these — but they were how we knew we had it right, and that is worth saying out loud.

### Stats — Serhiy Mytrovtsiy

<https://github.com/exelban/stats>  
Licence: MIT

The fan guard's System Management Controller keys on Apple silicon follow Stats, and so does the unlock that makes macOS let go of the fans: each fan's mode key, and the test flag Ftst where a chip up to the M4 refuses that. Handing the fans back afterwards is done as Stats does it too: mode 0, target 0, then the test flag cleared. Show Mode's Swift is its own and no code was taken, but the procedure came from reading how Stats does it.

## Getting this wrong

If your work is here and the description is inaccurate, the licence is wrong, or you would rather not be listed — open an issue and it will be fixed.
