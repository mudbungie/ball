# bl-3616 — store tiers: publication is a verb, boundaries are plugins, pointers are tags

**PROPOSED (2026-09-04, Inflate).** Filed from the maintainer's reframe of how
balls meets a team: *balls should lifecycle at high velocity locally and under
the user's name; shared stores exist but get deliberately mirrored work; the
next tier up is the corporate tracker (jira / GitHub issues — tasks for humans,
aligned to a roadmap goal); a ball's counterpart one tier up is sometimes a
direct mirror, sometimes the whole of which it is a component.* Wanted: (a)
bidirectional pointers to balls in other stores / repos and to external
trackers, (b) a sync-policy ladder — mandatory replication (today), warnings at
various obnoxiousness levels, explicit opt-in sync. This document states the
maximally-subtracted design first and asks the maintainer to argue it up. §6 is
the part that is NOT settled.

## 1. What exists, exactly (verified against `main` 93a0ab7f)

- **One store per checkout**, a branch (`tasks_branch`, default `balls/tasks`).
  The remote resolves per op by the §12 ladder (`--remote` > stealth sentinel >
  `task-remote` binding > `origin`).
- **Publication is a side effect of every mutation.** The `[hooks]` seed wires
  `bl-tracker` on `create.post`, `update.post`, `claim.post`, `unclaim.post`,
  `close.post` (plus `sync.pre` / `prime.pre` / `install.pre` for the fetch).
  `remote_ops::push` runs `git push <remote> <tasks_branch>`; a rejection on an
  established store is **E5** — *"the mutation did not land; the op aborts"*
  (§12). Currency is optimistic: the push IS the contention check.
- **"Unsynced" is not a thing the store knows.** There is no field, no marker.
  It is nevertheless fully computable: `git rev-list --count
  <remote>/<branch>..<branch>` (ahead) and the reverse (behind).
- **No pointer field.** §3 (bl-3067) REJECTS pure-metadata link types and names
  `tags` as the home of relatedness: *"relatedness is an equivalence CLASS, not
  a pairwise edge, and `tags` names the class: `list --tag` returns the whole
  cluster in one query."* `Task::extra` (free TOML keys, set by `key=value` on
  create/update) is the other opt-in seam, but `list` cannot filter on it.
- **`parent`** is a single scalar, *"containment only: builds the display tree,
  gates nothing"*, with no liveness check on the id it names.
- **A tier-2 plugin already exists and already made the fail-open call.**
  balls-github-plugin's `github-issues` mirrors create/update/close to GitHub
  Issues, pulls external closes down on `sync`, and since bl-a95c *"fails OPEN on
  transport errors instead of aborting the local op."*
- **Centers** (§12) are the existing shared-store shape: `bl prime --center
  <hub>` binds a checkout's store to a hub; `list --everywhere` reads the whole
  fleet. A center is ONE store with many writers — which is exactly where E5
  bites.

## 2. The reframe that dissolves the request

The complaint is "fail-closed sync." The cause is not the fail-closed policy;
it is **one store branch with many writers, published as a side effect of every
op.** Split those two and the ladder falls out:

1. **The personal store is single-writer.** Your `balls/tasks` on your own
   remote (fork, or `origin` when you are the only writer, or stealth) is
   written by you alone. E5 contention cannot occur there. The only remaining
   push failure is transport, and transport failure on a backup is not a reason
   to abort a local op — the work is not lost, it is *ahead*.
2. **A shared store is a different store, reached across a boundary.** Work
   arrives there by a deliberate act (check-in), per ball, not by branch push.
3. **Every tier boundary has the same shape**: a counterpart one tier up, a
   plugin that knows how to read and write it, four hooks (`create/update/close
   .post` to push, `sync` to pull, `show`/`list` to render the drift). The
   github-issues plugin IS this shape today. A "shared bl store" boundary is the
   same plugin contract with git as the transport.

Under that reading, nothing new is stored and nothing new is a mode. Each item
the maintainer asked for maps to an existing explicit signal:

| Ask | Home | Mechanism |
|---|---|---|
| mandatory replication (today) | schedule | plugin wired on `*.post` |
| explicit opt-in sync | schedule | plugin wired on `sync.pre` only (delete the `*.post` lines) |
| warn every action | render | drift line on `bl list` header (every session reads it) |
| warn only when you cause the desync | render | the same plugin's `*.post` prints the ahead count to stderr instead of pushing |
| does the mismatch live on the ball or the remote? | neither | it is the diff of two refs (tier 0→1) or two `updated` stamps (tier 1→2), computed at read |
| closed balls: re-queried? | plugin policy | `close.post` acts on the counterpart (mirror: close it; component: annotate it); `sync` pulls the counterpart's fate down |
| pointer to a ball in another store / repo | tag | `up:<store>#<id>` |
| canonical pointer to an external tracker | tag | `jira:PROJ-123`, `gh:owner/repo#42` — the plugin owns its namespace |

The severability test holds: turning "mandatory" into "opt-in" deletes two
schedule lines; turning it back re-adds them. No code edit, no config value.

## 3. Publication is a verb: `bl sync` grows a push

Today `bl sync` is fetch + fast-forward only. Under §2 it becomes the ONE place
the personal store publishes when the tracker is not wired on `*.post`:
fetch-ff, then push. This is not a new verb — `prime.post` already does exactly
*"settle store content (fetch-ff + push)"* through the tracker. `sync` and
`prime` are the same act at two moments.

The only bl-tracker code change this design needs: **transport failure fails
open** (warn on stderr, leave the store ahead), while **non-ff on an established
remote stays E5**. On a single-writer branch a non-ff means someone else wrote
your branch — a misconfiguration worth aborting on. That is the same line
github-issues drew in bl-a95c, moved into the tracker.

**Drift render.** bl-tracker gains a read-op hook (`list`, `show` — the bl-0af4
single-phase dispatch bl-delivery already uses for the `worktree` line) that
folds one line into the human render: `store: 3 ahead, 0 behind
origin/balls/tasks`. Derived from `git rev-list`, never in `--json`, absent in
stealth. This is the whole "obnoxiousness" surface for tier 0→1.

## 4. Pointers are tags, stored once, pointing UP

The maintainer's own framing: *"it's up to a jira plugin to know how to find the
local tasks."* That is the single-source-of-truth answer. The pointer lives on
the LOWER ball only, as a tag in the plugin's namespace. The upper side never
stores a back-pointer; it queries: `bl list --tag jira:PROJ-123 --all` returns
every local ball — live or dead — that is a component of PROJ-123. Bidirectional
means navigable both ways, not stored in both places.

Why a tag and not `parent` or an extra:

- `parent` is one scalar. A ball that is a subtask of a local epic AND checked
  into a shared store has two "ups" at once. Chains fit `parent`; a ball that
  faces two tiers does not.
- extras are not queryable by `list`, so the upper tier could not find its
  components without reading every file. Tags are the class query §3 already
  argued for.
- A tag renders in the `list` row. The maintainer asked for sync state to be
  visible; the pointer being visible on every row is the cheapest form of that.

**Mirror vs component collapses.** A mirror is a component whose upper
counterpart has exactly one component; the only behavioral difference is who
closes the upper. That is plugin policy at `close.post` (github-issues closes the
issue; a jira plugin may instead comment "component bl-3616 closed"), not a
kind of pointer. One tag shape, no `kind=` attribute.

**Cross-store pointer spelling.** `up:<store>#<id>`, where `<store>` is a git
URL or a branch of the current repo (`up:balls/team#bl-12ab`,
`up:git@host:hub.git#bl-12ab`). Ids are 4-hex and collide across repos, so the
store qualifier is load-bearing; within one store the id alone is the pointer.
Implementation check: tag validation charset must admit `:`, `/`, `@`, `#`.

## 5. The shared bl store as a plugin (`bl-upstream`, not built)

The one genuinely new thing is a plugin that treats another bl store the way
github-issues treats GitHub. Sketch, same four hooks:

- `create/update/close .post` — for a ball carrying an `up:` tag, write the
  counterpart: `git show <store>:tasks/<id>.md`, apply this ball's frontmatter
  + body, commit on the upstream branch, push. No `bl` shelling (bl-1266's rule).
- `sync` — for every live ball with an `up:` tag, read the counterpart; if its
  `updated` is newer than the local one, fold it in (or refuse with the diff,
  the way close refuses an unseen task file — same seen-token discipline).
- `show`/`list` — render `up: balls/team#bl-12ab (behind 2h)` from the two
  `updated` stamps. Derived; nothing stored.
- **Check-out** (pulling a shared ball down to work on it) is already
  `bl -C <shared-checkout> show <id> --json | bl import` plus the tag; the
  plugin's `sync` is the same import, addressed by tag instead of by hand.

Wired on `*.post` it is mandatory replication; wired on `sync.pre` alone it is
check-in on demand. The ladder is the schedule, again.

## 6. Not settled — the maintainer's attack wanted here

1. **Is the personal tier really single-writer?** The reframe in §2 rests on it.
   If two of the maintainer's own agents on two boxes share one personal
   remote, E5 contention is back at tier 0 and "fail-open on transport" does
   not cover it. Position: two boxes are two checkouts with two bindings; a
   shared personal remote is a shared store and belongs at tier 1.
2. **Does deferred publication need a merge, not an ff?** If the tracker leaves
   `*.post` and a second writer does exist, `bl sync` meets divergence as the
   NORMAL case and ff-only refuses forever. Position: keep ff-only and let the
   answer to (1) make divergence a misconfiguration; if (1) falls, sync becomes
   fetch + rebase-local-seals + push, refusing on same-ball conflict and naming
   the ball.
3. **Addressing a second store of the same project.** A store is keyed on the
   invocation directory; a shared `balls/team` branch of the SAME repo has no
   directory to be `-C`'d from. `bl sync [BRANCH]` already takes a branch name
   — is that precedent enough for the plugin to speak git to a branch directly,
   or does the shared tier want its own clone directory (the center model)?
   Position: git-direct; a store is a branch, the plugin needs no checkout.
4. **Tag namespace as protocol.** `up:`, `jira:`, `gh:` are conventions with
   no registry. Position: that is correct — a plugin's tag prefix is its name,
   the same way its `[hooks]` name is; a collision is two plugins claiming one
   name, already refused at install.
5. **Does the drift line belong on `list` or on `conf`?** Drift is a property
   of the checkout, not a ball. `bl conf` already shows the resolved remote and
   branch. Position: `list` header, because `list` is the read every session
   starts with and `conf` is consulted only when something is wrong.

## 7. What this does NOT solve, stated

- Two writers editing one ball on a shared store still conflict; the plugin
  refuses with the diff. No CRDT, no field-wise merge.
- A ball checked in under a tag and then hand-deleted upstream is an `up:` tag
  pointing at a dead counterpart; `sync` reports it, nothing repairs it.
- Nothing here changes tier-2 plugins: github-issues already has the shape.
  A jira plugin is a port, not a design.

## 8. Implementation balls (mint on convergence, not before)

- bl-tracker: transport failure fails open; drift line on `list`/`show`.
- `bl sync`: push after fetch-ff (tracker `sync.post`).
- Tag charset: admit `:` `/` `@` `#`.
- `bl-upstream` plugin (sibling repo, like balls-github-plugin).
- Seed comment in `[hooks]` documenting the opt-in wiring.
