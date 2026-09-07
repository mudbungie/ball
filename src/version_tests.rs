//! Tests for [`crate::version`] — including the one that keeps [`PLUGINS`] from
//! becoming a second home for a fact `src/bin/` already owns.

use super::*;

#[test]
fn the_plugin_set_is_exactly_the_sibling_binaries_this_crate_builds() {
    // The REAL home of the shipped plugin set is `src/bin/` (cargo
    // autodiscovers it; `Cargo.toml` does not even name `bl-tracker`). The
    // const is a restatement forced by cargo exposing no runtime reading of
    // it, so this test is what makes it a restatement rather than a second
    // source: add a binary and forget the const, and the build goes red here.
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src").join("bin");
    let mut built: Vec<String> = std::fs::read_dir(&dir)
        .unwrap()
        .map(|e| e.unwrap().path().file_stem().unwrap().to_string_lossy().into_owned())
        .collect();
    built.sort();
    assert_eq!(built, PLUGINS.to_vec(), "src/bin/ and version::PLUGINS disagree");
}

#[test]
fn bl_names_its_version_then_the_plugin_set() {
    let line = line();
    assert_eq!(line.split_whitespace().next(), Some("bl"));
    assert_eq!(line.split_whitespace().nth(1), Some(VERSION), "field 2 is the version");
    for p in PLUGINS {
        assert!(line.contains(p), "{p} missing from the version line");
    }
}

#[test]
fn a_plugin_names_itself_and_the_same_version() {
    // Same first two fields as `bl`'s line: one reader parses either, and the
    // versions are equal by construction (one crate, five binaries).
    assert_eq!(plugin_line("bl-delivery"), format!("bl-delivery {VERSION}"));
}

#[test]
fn both_spellings_ask_and_nothing_else_does() {
    let argv = |a: &[&str]| a.iter().map(|s| (*s).to_string()).collect::<Vec<_>>();
    assert!(asked(&argv(&["--version"])));
    assert!(asked(&argv(&["-V"])));
    assert!(!asked(&argv(&["list"])), "a verb is not a version request");
    assert!(!asked(&argv(&["close", "--version"])), "only the FIRST word asks");
    assert!(!asked(&[]), "a bare invocation is not a version request");
}
