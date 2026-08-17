# Tool Requirements: Desktop Applications

Inherits everything in [general.md](general.md).

## 1. Purpose

Seventeen graphical applications.

## 2. Classification

**System package** (GEN-D-8), regardless of which mechanism supplies a given
application. They are machine-global, not version-pinned by this repository,
and not installed into the application directory - the supplying package
manager owns their location. GEN-R-1a governs artifacts this repository
installs, not artifacts a system package manager owns.

**APPS-R-1** Version pinning is explicitly out of scope, contrary to GEN-R-6.
These track upstream releases, which is the intended behaviour for end-user
desktop software.

**APPS-A-1** This is also forced, not merely chosen: the orchestrator's Flatpak
manager rejects version pins outright and accepts only "latest". `VERIFIED` -
orchestrator Flatpak documentation and the change that added the manager. This
no longer describes the mechanism in use - applications are installed by
calling flatpak directly. APPS-R-1 is unaffected: flatpak exposes no
historical-version install either.

## 3. Acquisition preference order

Applications may come from more than one source. The order of preference is:

1. **Flatpak** - preferred.
2. **Distribution package** (`dnf`) - when no suitable Flatpak exists.
3. **Manual acquisition** - download, and build if necessary - only where an
   application justifies the effort.

**APPS-R-2** The preference order SHALL be applied **when an application is
added**, and the resulting choice SHALL be recorded per application in section
4. It SHALL NOT be implemented as a runtime fallback chain.

The reason is decisiveness, not purity. A runtime chain means the same
repository produces a different machine depending on what happened to be
reachable, and you cannot tell afterwards which tier supplied any given
application. Recording the choice keeps setup reproducible and keeps the
verification in section 8 meaningful. The preference order still does its job -
it is the rule you apply when deciding, and it is recorded as such in
[adding-a-new-tool.md](../adding-a-new-tool.md).

**APPS-A-2** A runtime chain would also not fail the way it appears to. When
the Flatpak CLI is absent the orchestrator lists those entries as *skipped*
rather than erroring, so a "if Flatpak is unavailable, fall through" rule would
silently install nothing rather than advancing to the next tier. `VERIFIED` -
orchestrator package documentation: entries for an unavailable manager are not
acted on. This failure mode no longer exists here: preflight blocks on an
absent flatpak before the step runs. APPS-R-2 stands on its remaining grounds.

**APPS-R-3** Tier 3 SHALL be authored per application and SHALL NOT be assumed
available for all. Several of the seventeen have no buildable source at all -
GitKraken is proprietary - and others are large C++ desktop applications whose
source builds are substantial projects in their own right. Where tier 3 is
genuinely needed, that application gets its own requirements document under
GEN-R-13 and is no longer covered by this one.

**APPS-R-4** Where an application moves between tiers, the change SHALL be
recorded in section 4 and the previous installation SHALL be removed, so that
two copies from different sources never coexist.

## 4. The inventory

All seventeen are currently tier 1 (Flatpak).

| Domain | Applications | Tier |
|---|---|---|
| Electronics and CAD | KiCad, FreeCAD, PrusaSlicer, Arduino IDE2 | 1 |
| Documents and writing | TeXstudio, OnlyOffice, Obsidian, Anki | 1 |
| Graphics and diagrams | Krita, drawio | 1 |
| Geo | JOSM | 1 |
| Development | GitKraken | 1 |
| System | Flatseal, GNOME Extensions, Extension Manager | 1 |
| Other | Bottles, Tellico | 1 |

**WITHDRAWN.** **APPS-R-5** The list SHALL live in the single declarative
location alongside the distribution packages, not in a separate imperative
step with its own wrapper. In practice that is the same `[bootstrap.packages]`
table as the distribution packages, because a duplicate table header is not
permitted (GEN-A-8a); the two are separated when applied, by naming the
manager, not by being declared apart. Withdrawn because the applications are
installed by calling flatpak directly rather than through the declarative
table; replaced by APPS-R-11.

## 5. Installation scope

**WITHDRAWN.** **APPS-R-6** Applications SHALL be installed **system-wide**,
not per-user. Withdrawn in favour of APPS-R-10: system scope is what required
elevation.

**APPS-A-3** The orchestrator exposes these as two distinct managers - one for
system scope, one for user scope - so the choice is expressed by which manager
the declaration names, and cannot be left implicit. `VERIFIED` - orchestrator
manager list.

**APPS-A-4** System scope matches current behaviour. The existing setup step
installs without a user-scope flag, which is system scope by default.
`VERIFIED` - read from the current setup step. Choosing system scope therefore
changes nothing about the resulting machine and avoids a silent migration of
seventeen applications between scopes. Superseded, not incorrect: removing
elevation from the default path now outranks matching the pre-migration scope.

## 6. The remote

**APPS-A-5** The orchestrator does **not** configure Flatpak remotes. Its
documentation states plainly that it neither installs Flatpak nor configures
remotes implicitly, and requires the CLI and the remote to be in place before
the configuration is applied. `VERIFIED` - orchestrator Flatpak documentation.
*This resolves the one previously unverified assumption in this document set.*

**APPS-A-6** Flatpak ships with Fedora Workstation, but the Flathub remote does
not. It is opt-in through the Third-Party Repositories feature. `VERIFIED` -
Flathub's own Fedora setup page.

**APPS-A-7** When enabled through Third-Party Repositories the remote may be a
*filtered* view exposing only a Fedora-approved subset. Adding the remote
manually removes the filter. A filtered remote can therefore make some of the
seventeen unavailable while others install normally - a partial, confusing
failure rather than a clean one. `VERIFIED` - Fedora's Flathub remote package
description and the associated Fedora change proposal.

**APPS-R-7** Setup SHALL ensure the Flatpak CLI is present and an unfiltered
Flathub remote exists **before** any application installation is attempted.
This is an explicit preceding step, required by APPS-A-5; it cannot be
delegated to the orchestrator.

**APPS-R-8** Adding the remote SHALL be conditional on its absence, so the step
is idempotent (GEN-R-4).

**APPS-A-8** The current implementation makes none of these arrangements: it
calls the installer with an application identifier and no remote, having never
added one. On a fresh machine without Third-Party Repositories enabled, all
seventeen fail. `VERIFIED` - read from the current setup step.

**APPS-R-9** The applications SHALL be applied in a step of their own that
follows the remote step, by calling flatpak directly for each identifier. The
distribution packages are applied separately, in the privileged phase. Two
steps are required by the ordering constraint in APPS-R-7.

**APPS-R-10** Applications SHALL be installed in user scope, so that installing
them requires no elevation (GEN-R-19).

**APPS-R-11** The application identifiers SHALL live in `mise.toml` and nowhere
else, so that GEN-R-7 continues to hold now that they are not declared in
`[bootstrap.packages]`.

## 6a. What is not verified

**APPS-A-9** The application install path is never exercised end to end. The
verification harness proves that the remote exists, that it is unfiltered, and
that every one of the seventeen identifiers resolves against it - not that the
applications install. A resolvable identifier can still fail to install for
reasons no check covers: disk space, architecture mismatch, or a runtime
conflict. A genuine user-scope Flatpak install needs a working system bus
that the sandboxed container does not have, so nothing cheap closes this gap.
`VERIFIED` - both halves were observed: the harness never runs the application
target, and the sandboxed container provides no system bus. The first real
signal therefore comes from the user's own machine, and this is an
accepted risk rather than a covered case. The same apply mechanism is proven
against the distribution-package manager, and every identifier is proven to
resolve, which is what bounds the risk.

## 7. Declared inputs

| Input | Source |
|---|---|
| Flatpak CLI | system package, declared as a prerequisite of this tool |
| Flathub remote | established by this tool, per APPS-R-7 |

This tool exports nothing and no other tool depends on it, so it has no
predecessors beyond its own prerequisites and may run in parallel with
everything else (GEN-R-5).

## 8. Verification

| Requirement | Check |
|---|---|
| APPS-R-2 | Every application in section 4 has a recorded tier |
| APPS-R-7 | On a machine with Third-Party Repositories disabled and no remote configured, setup still installs all seventeen |
| APPS-R-8 | Setup runs twice in succession without error |
| APPS-R-4 | No application is installed from two sources simultaneously |
| APPS-R-9 | The application step declares the remote step as its predecessor |
| APPS-R-10 | Installed scope is user for all seventeen, and no system remote is added |
| APPS-R-11 | The seventeen identifiers appear in mise.toml and in no other tracked file |
| APPS-A-9 | Open by construction in the container: closed only by the first run on the real machine, where all seventeen are confirmed installed and user-scoped |
