#!/usr/bin/env bash
# Generate the android/ and ios/ platform scaffolding for the Flutter app
# and apply the Android overlay (widget providers, layouts, icons, manifest
# patch). The platform folders are build-generated and not committed; this
# script (and the Build APK GitHub Actions workflow, which runs the same
# steps) assembles them from the committed sources:
#   lib/               the app
#   android_overlay/   widget Kotlin code, resources, icons, patch script
#
# Usage:  flutter/tool/setup_platforms.sh
# Requires: flutter (3.47.8) on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

SCAFFOLD="$(mktemp -d)/scaffold"
flutter create --project-name alrashidwidget --org com.c12n --platforms=android,ios "$SCAFFOLD"

rm -rf android ios
cp -r "$SCAFFOLD/android" "$SCAFFOLD/ios" .
cp "$SCAFFOLD/.metadata" . 2>/dev/null || true

MAIN_KOTLIN=android/app/src/main/kotlin/com/c12n/alrashidwidget
mkdir -p "$MAIN_KOTLIN"
cp -r android_overlay/kotlin/. "$MAIN_KOTLIN/"
cp -r android_overlay/res/. android/app/src/main/res/
python3 android_overlay/patch_android.py android

# Launcher icons: resize the iOS app icon (already in this repo) into the
# Android mipmap densities with ImageMagick.
ICON_SRC=../AlRashidWidget/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png
for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density="${spec%%:*}"; px="${spec##*:}"
  magick "$ICON_SRC" -resize "${px}x${px}" "android/app/src/main/res/mipmap-$density/ic_launcher.png"
done

flutter pub get
echo "Platforms assembled. Build with: flutter build apk --release"
