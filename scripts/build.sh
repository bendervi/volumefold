#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep code signing outside Documents/iCloud, which can attach Finder metadata
# to an unsigned bundle while Xcode is still assembling it.
derived_data="${VOLUMEFOLD_DERIVED_DATA:-$HOME/Library/Caches/VolumeFold/DerivedData}"
xcodebuild -project VolumeFold.xcodeproj -scheme VolumeFold \
  -configuration Release -derivedDataPath "$derived_data" build CODE_SIGN_IDENTITY=- "$@"
mkdir -p build
# An iCloud folder re-adds FinderInfo even after copying with --noextattr.
# Link the signed bundle here instead of putting its files under File Provider.
if [[ -e build/VolumeFold.app && ! -L build/VolumeFold.app ]]; then
  rm -rf build/VolumeFold.app
fi
ln -sfn "$derived_data/Build/Products/Release/VolumeFold.app" build/VolumeFold.app
codesign --verify --strict "$derived_data/Build/Products/Release/VolumeFold.app"
echo "Built $(pwd)/build/VolumeFold.app"
