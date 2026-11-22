#!/usr/bin/env python3
"""Wire Zad X's native Android code into the shell made by `flutter create`.

Run from the project root after `flutter create`:
    python3 android/scripts/integrate_native.py                   # Zad X Play (com.zadx.app)
    python3 android/scripts/integrate_native.py --variant kids    # Zad X Kids (com.zadx.kids)

Build Zad X Kids with `flutter build apk --dart-define=ZADX_VARIANT=kids` after the second form
(docs/decisions/ZADX-KIDS-VARIANT.md). Switching back needs the first form again.

It is safe to run more than once. It:
  1. sets namespace to com.zadx.app (the Kotlin package of both apps), applicationId to the
     variant's store id, and minSdk 26
  2. enables core library desugaring (needed by flutter_local_notifications)
  3. removes the template MainActivity generated under another package
  4. merges AndroidManifest.additions.xml into AndroidManifest.xml (and adds components that
     were introduced after a first merge, e.g. the Device Admin receiver)
  5. adds JUnit for the pure-Kotlin rule tests in android/app/src/test (LockRulesTest)
  6. sets the launcher label of the variant; for Zad X Kids also replaces the Accessibility /
     Device Admin descriptions with neutral text and removes the adhan notification sound
"""
import argparse
import re
import shutil
import sys
from pathlib import Path

APP = Path("android/app")
PKG = "com.zadx.app"  # namespace + Kotlin package (both variants)

# applicationId (store id) and launcher label per variant. Keep in sync with lib/core/app_config.dart.
VARIANTS = {
    "islamic": {"application_id": "com.zadx.app", "label": "Zad X Play"},
    "kids": {"application_id": "com.zadx.kids", "label": "Zad X Kids"},
}

# Zad X Kids: Google Play prominent-disclosure texts without any prayer wording.
KIDS_STRINGS = {
    "values": (
        "Zad X uses this permission only to see which app is open (its name, never what is on the screen), "
        "so it can lock games and apps chosen by the parent until tasks are done and during study time, "
        "reading time and bedtime, keep the Settings app for the parent only, and stop apps from being "
        "deleted without the parent when the parent turns that on. Phone and emergency calls are never "
        "locked. Nothing about the apps used leaves this phone."
    ),
    "values-ar": (
        "‏Zad X بيستخدم الصلاحية دي بس عشان يعرف أنهي تطبيق مفتوح (اسمه بس، عمره ما بيقرا اللي على الشاشة)، "
        "عشان يقفل الألعاب والتطبيقات اللي ولي الأمر اختارها لحد ما المهام تخلص وفي وقت المذاكرة والقراية والنوم، "
        "ويخلي تطبيق الإعدادات لولي الأمر بس، ويمنع مسح التطبيقات من غير ولي الأمر لو هو شغّل الخاصية دي. "
        "التليفون ومكالمات الطوارئ عمرهم ما بيتقفلوا. ومفيش أي معلومة عن التطبيقات بتخرج من التليفون ده."
    ),
}

def patch_gradle(application_id: str = PKG) -> None:
    kts = APP / "build.gradle.kts"
    groovy = APP / "build.gradle"
    path = kts if kts.exists() else groovy
    if not path.exists():
        sys.exit("android/app/build.gradle(.kts) not found: run flutter create first")
    s = path.read_text()
    is_kts = path.suffix == ".kts"
    q = '"'
    s = re.sub(r'namespace\s*=?\s*["\'][^"\']+["\']', f'namespace = {q}{PKG}{q}' if is_kts else f'namespace "{PKG}"', s)
    s = re.sub(r'applicationId\s*=?\s*["\'][^"\']+["\']', f'applicationId = {q}{application_id}{q}' if is_kts else f'applicationId "{application_id}"', s)
    s = re.sub(r'minSdk(Version)?\s*=?\s*[\w.]+', 'minSdk = 26' if is_kts else 'minSdkVersion 26', s)
    if "CoreLibraryDesugaringEnabled" not in s:
        flag = "isCoreLibraryDesugaringEnabled = true" if is_kts else "coreLibraryDesugaringEnabled true"
        s = re.sub(r'compileOptions\s*\{', "compileOptions {\n        " + flag, s, count=1)
    if "junit:junit" not in s:
        dep = 'testImplementation("junit:junit:4.13.2")' if is_kts else "testImplementation 'junit:junit:4.13.2'"
        if re.search(r'^dependencies\s*\{', s, re.M):
            s = re.sub(r'^dependencies\s*\{', "dependencies {\n    " + dep, s, count=1, flags=re.M)
        else:
            s += "\ndependencies {\n    " + dep + "\n}\n"
    if "desugar_jdk_libs" not in s:
        dep = ('coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")' if is_kts
               else "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'")
        if re.search(r'^dependencies\s*\{', s, re.M):
            s = re.sub(r'^dependencies\s*\{', "dependencies {\n    " + dep, s, count=1, flags=re.M)
        else:
            s += "\ndependencies {\n    " + dep + "\n}\n"
    path.write_text(s)
    print(f"patched {path}")

def remove_template_activity() -> None:
    kotlin = APP / "src/main/kotlin"
    ours = kotlin / PKG.replace(".", "/")
    for main in kotlin.rglob("MainActivity.kt"):
        if main.parent != ours:
            print(f"removing template {main}")
            shutil.rmtree(main.parent)

def merge_manifest() -> None:
    manifest = APP / "src/main/AndroidManifest.xml"
    additions = APP / "src/main/AndroidManifest.additions.xml"
    m = manifest.read_text()
    a = re.sub(r"<!--.*?-->", "", additions.read_text(), flags=re.S)
    if "AppBlockerService" in m:
        # Already merged by an older version of this script: add receivers introduced later.
        for name in ("ZadXDeviceAdminReceiver", "ClockChangeReceiver"):
            if name not in m:
                block = re.search(r"\s*<receiver\s+android:name=\"\.%s\".*?</receiver>" % name, a, re.S)
                if block:
                    m = m.replace("</application>", block.group(0).rstrip() + "\n    </application>", 1)
                    print(f"added {name} to manifest")
        manifest.write_text(m)
        print("manifest already merged")
        return
    top = re.search(r"<manifest[^>]*>(.*?)<application", a, re.S).group(1)
    inner = re.search(r"<application[^>]*>(.*)</application>", a, re.S).group(1)
    m = re.sub(r"(<application)", top.strip() + "\n    \\1", m, count=1)
    m = re.sub(r'android:label="[^"]*"', 'android:label="Zad X Play"', m, count=1)
    # No adb/cloud backup of the lock state, PIN hash or family id (restoring old prefs could
    # unlock games or reset the PIN throttle).
    m = re.sub(r"<application(?![^>]*allowBackup)", '<application android:allowBackup="false"', m, count=1)
    m = m.replace("</application>", inner.rstrip() + "\n    </application>", 1)
    manifest.write_text(m)
    print("merged AndroidManifest.additions.xml")

def set_label(label: str) -> None:
    """Launcher / store label of the variant (first android:label = the <application> tag)."""
    manifest = APP / "src/main/AndroidManifest.xml"
    m = manifest.read_text()
    m = re.sub(r'(<application[^>]*?android:label=")[^"]*(")', lambda g: g.group(1) + label + g.group(2), m, count=1)
    manifest.write_text(m)
    print(f"label: {label}")


def neutralise_for_kids() -> None:
    """Zad X Kids: no prayer wording in native strings, no adhan sound in the APK."""
    for folder, text in KIDS_STRINGS.items():
        path = APP / "src/main/res" / folder / "zadx_strings.xml"
        s = path.read_text()
        escaped = text.replace("'", "\\'")
        s = re.sub(r'(<string name="zadx_accessibility_description">)(.*?)(</string>)',
                   lambda g: g.group(1) + escaped + g.group(3), s, flags=re.S)
        path.write_text(s)
        print(f"kids text: {path}")
    adhan = APP / "src/main/res/raw/adhan_short.mp3"
    if adhan.exists():
        adhan.unlink()
        print(f"removed {adhan}")
        if not any(adhan.parent.iterdir()):
            adhan.parent.rmdir()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--variant", choices=sorted(VARIANTS), default="islamic")
    args = parser.parse_args()
    variant = VARIANTS[args.variant]
    patch_gradle(variant["application_id"])
    remove_template_activity()
    merge_manifest()
    set_label(variant["label"])
    if args.variant == "kids":
        neutralise_for_kids()
