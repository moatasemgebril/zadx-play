#!/usr/bin/env python3
"""Strip Zad X Play's religious assets from the working tree before a Zad X Kids build.

Flutter bundles every file of the asset folders listed in pubspec.yaml, whatever the Dart code
uses, and pubspec has no per-dart-define assets. So the Kids build removes them from the
checkout first (docs/decisions/ZADX-KIDS-VARIANT.md):

    python3 tools/kids_variant_prepare.py            # dry run: lists what would change
    python3 tools/kids_variant_prepare.py --apply    # CI only (CI=true)
    python3 tools/kids_variant_prepare.py --apply --yes   # a throw-away clone with a clean git tree
    python3 android/scripts/integrate_native.py --variant kids
    flutter build apk --dart-define=ZADX_VARIANT=kids

DESTRUCTIVE: --apply refuses to run unless CI=true is set, or the git tree is clean and --yes is
given (so uncommitted work can never be lost). Restore a working copy with
    git checkout -- assets android/app/src/main/res
"""
import argparse
import os
import subprocess
from pathlib import Path

# Files that exist only for Zad X Play (adhan audio and its credits, the Zad X Play logo images).
# The Kids code never references them (BrandLogo draws the Kids wordmark instead).
REMOVE_GLOBS = [
    "assets/audio/adhan_*.mp3",
    "assets/audio/ADHAN-CREDITS.txt",
    "assets/images/zadx_*",
]

# Asset folders stay declared in pubspec.yaml, so each keeps one neutral file.
NEUTRAL_READMES = {
    "assets/audio/README.txt": "Zad X Kids bundles no audio files here.\n",
    "assets/images/README.txt": "Zad X Kids draws its logo in code (lib/shared/widgets/brand_logo.dart).\n",
}


def git_tree_clean(root: Path) -> bool:
    """True only when `git status --porcelain` runs and reports nothing (no git = not clean)."""
    try:
        out = subprocess.run(
            ["git", "status", "--porcelain"], cwd=root, capture_output=True, text=True, check=True, timeout=60,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return out.strip() == ""


def apply_allowed(env: dict, yes: bool, tree_clean: bool) -> bool:
    """--apply is allowed in CI (CI=true) or with --yes on a clean git tree."""
    if str(env.get("CI", "")).strip().lower() == "true":
        return True
    return yes and tree_clean


def main(argv=None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true", help="really delete / rewrite the files")
    parser.add_argument("--yes", action="store_true", help="outside CI: confirm --apply (needs a clean git tree)")
    args = parser.parse_args(argv)
    root = Path.cwd()
    if not (root / "pubspec.yaml").exists():
        raise SystemExit("run from the project root")
    if args.apply and not apply_allowed(os.environ, args.yes, git_tree_clean(root)):
        raise SystemExit(
            "refusing --apply: it deletes files. Run it in CI (CI=true), or in a throw-away clone with a "
            "clean git tree and --yes."
        )

    for pattern in REMOVE_GLOBS:
        for path in sorted(root.glob(pattern)):
            print(("removing " if args.apply else "would remove ") + str(path.relative_to(root)))
            if args.apply:
                path.unlink()
    for rel, text in NEUTRAL_READMES.items():
        print(("writing " if args.apply else "would write ") + rel)
        if args.apply:
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            (root / rel).write_text(text, encoding="utf-8")
    if not args.apply:
        print("dry run: nothing changed (use --apply in CI or a clean clone)")


if __name__ == "__main__":
    main()
