#!/usr/bin/env python3
"""Wire Zad X's native Android code into the shell made by `flutter create`.

Run from the project root after `flutter create`:
    python3 android/scripts/integrate_native.py

It is safe to run more than once. It:
  1. sets namespace/applicationId to com.zadx.app and minSdk 26
  2. enables core library desugaring (needed by flutter_local_notifications)
  3. removes the template MainActivity generated under another package
  4. merges AndroidManifest.additions.xml into AndroidManifest.xml
"""
import re
import shutil
import sys
from pathlib import Path

APP = Path("android/app")
PKG = "com.zadx.app"

def patch_gradle() -> None:
    kts = APP / "build.gradle.kts"
    groovy = APP / "build.gradle"
    path = kts if kts.exists() else groovy
    if not path.exists():
        sys.exit("android/app/build.gradle(.kts) not found: run flutter create first")
    s = path.read_text()
    is_kts = path.suffix == ".kts"
    q = '"'
    s = re.sub(r'namespace\s*=?\s*["\'][^"\']+["\']', f'namespace = {q}{PKG}{q}' if is_kts else f'namespace "{PKG}"', s)
    s = re.sub(r'applicationId\s*=?\s*["\'][^"\']+["\']', f'applicationId = {q}{PKG}{q}' if is_kts else f'applicationId "{PKG}"', s)
    s = re.sub(r'minSdk(Version)?\s*=?\s*[\w.]+', 'minSdk = 26' if is_kts else 'minSdkVersion 26', s)
    if "CoreLibraryDesugaringEnabled" not in s:
        flag = "isCoreLibraryDesugaringEnabled = true" if is_kts else "coreLibraryDesugaringEnabled true"
        s = re.sub(r'compileOptions\s*\{', "compileOptions {\n        " + flag, s, count=1)
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
    if "AppBlockerService" in m:
        print("manifest already merged")
        return
    a = re.sub(r"<!--.*?-->", "", additions.read_text(), flags=re.S)
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

if __name__ == "__main__":
    patch_gradle()
    remove_template_activity()
    merge_manifest()
