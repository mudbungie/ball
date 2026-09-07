//! `--version` — what this binary is, and what set it was built with.
//!
//! One crate builds FIVE binaries: `bl` plus the four sibling plugins the §6
//! contract resolves beside it. Their versions are therefore equal by
//! construction, and a box holding a MIXED set is holding a set nobody built —
//! which is the fact this module exists to make answerable. `bl --version`
//! names the crate version and the plugin set it shipped with; each named
//! binary answers `--version` for itself in the same two fields. **No binary
//! states another's version** — the reading is composed by whoever asks
//! (`scripts/deploy/bl-update` does exactly that, every tick), so there is one
//! home for each fact and nothing to drift.
//!
//! It is help OUTPUT, not an op — like [`crate::skill`] and [`crate::help`] it
//! is dispatched before any verb parse in [`crate::run`], so it answers on an
//! unprimed checkout, from any directory, with no substrate at all.

/// The crate version every binary in this build reports. One value, read from
/// cargo at compile time — `Cargo.toml`'s `version` is its only home.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// The sibling plugin binaries this crate builds beside `bl` — `Cargo.toml`'s
/// `[[bin]]` entries plus `src/bin/` autodiscovery, minus `bl` itself. Cargo
/// exposes no runtime reading of that set, so it is restated here; the
/// restatement is not free-floating, because `version_tests` reads `src/bin/`
/// and fails the build if the two ever disagree.
pub const PLUGINS: [&str; 4] = ["bl-chore", "bl-delivery", "bl-speculate", "bl-tracker"];

/// Whether argv opens with a version request. `--version` is canonical (the
/// spelling `README.md` documents); `-V` is the conventional short form.
#[must_use]
pub fn asked(args: &[String]) -> bool {
    matches!(args.first().map(String::as_str), Some("--version" | "-V"))
}

/// `bl`'s version line: the crate version, then the plugin set built with it.
/// One line, two fields then a parenthesised list — the shape a reconciler
/// parses with `awk 'NR==1 {print $2}'` and the reason the plugin names are
/// space-separated inside the parentheses.
#[must_use]
pub fn line() -> String {
    format!("bl {VERSION} (plugins: {})", PLUGINS.join(" "))
}

/// A sibling plugin's version line — `<name> <version>`, the same first two
/// fields `bl`'s line opens with, so one reader parses either.
#[must_use]
pub fn plugin_line(name: &str) -> String {
    format!("{name} {VERSION}")
}

#[cfg(test)]
#[path = "version_tests.rs"]
mod tests;
