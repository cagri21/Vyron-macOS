#!/bin/zsh
set -euo pipefail

desktop_root="${0:A:h:h}"
configuration="${1:-release}"
app_dir="${2:-$desktop_root/.build/app/Vyron.app}"
if (( $# > 1 )); then
    if [[ "$app_dir" != "${app_dir:a}" || "$app_dir" != "$desktop_root/.build/"* \
        || "${app_dir:t}" != "Vyron.app" \
        || -e "$app_dir" || -L "$app_dir" ]]; then
        print -u2 -r -- "Choose a new Vyron.app output folder inside this project's .build directory."
        exit 1
    fi
    app_parent="${app_dir:h}"
    while [[ "$app_parent" != "$desktop_root" && "$app_parent" != "/" ]]; do
        if [[ -L "$app_parent" ]]; then
            print -u2 -r -- "The app output folder must not contain symbolic links."
            exit 1
        fi
        app_parent="${app_parent:h}"
    done
fi
cd "$desktop_root"
python3 Apps/Vyron/Resources/generate_resources.py --check
build_arguments=(-c "$configuration" --disable-sandbox)
if [[ -n "${VYRON_SWIFTPM_BUILD_SYSTEM:-}" ]]; then
    build_arguments+=(--build-system "$VYRON_SWIFTPM_BUILD_SYSTEM")
fi
swift build "${build_arguments[@]}"
binary_dir="$(swift build "${build_arguments[@]}" --show-bin-path)"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Vyron" "$app_dir/Contents/MacOS/Vyron"
cp "$binary_dir/VyronChromeHost" "$app_dir/Contents/MacOS/VyronChromeHost"
cp "$desktop_root/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp -R "$binary_dir/Vyron_Vyron.bundle" "$app_dir/Contents/Resources/"
cp -R "$binary_dir/Vyron_VyronCore.bundle" "$app_dir/Contents/Resources/"
cp -R "$binary_dir/Vyron_VyronLocalization.bundle" "$app_dir/Contents/Resources/"
resource_bundle="$app_dir/Contents/Resources/Vyron_Vyron.bundle"
if [[ -f "$resource_bundle/Contents/Info.plist" ]]; then
    resource_directory="$resource_bundle/Contents/Resources"
else
    resource_directory="$resource_bundle"
fi
mkdir -p "$resource_directory/Theme.xcassets"
cp -R "$desktop_root/Apps/Vyron/Resources/Theme.xcassets/." "$resource_directory/Theme.xcassets/"
for language in en tr uk; do
    mkdir -p "$app_dir/Contents/Resources/$language.lproj"
    cp "$desktop_root/Apps/Vyron/Resources/$language.lproj/InfoPlist.strings" \
        "$app_dir/Contents/Resources/$language.lproj/InfoPlist.strings"
done
if [[ -f "$desktop_root/Resources/AppIcon.icns" ]]; then
    cp "$desktop_root/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$app_dir/Contents/MacOS/VyronChromeHost"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
print -r -- "$app_dir"
