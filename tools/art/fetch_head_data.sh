#!/bin/bash
# Downloads the MakeHuman data that build_mh_head.py reads, into third_party/. Run from anywhere.
# MPFB's code is GPL and is never imported. Only its CC0 data files are read.
set -e
cd "$(dirname "$0")"
mkdir -p third_party/mh_packs third_party/mh_data
if [ ! -d third_party/mpfb2 ]; then
	git clone --depth 1 --branch v2.0.18 https://github.com/makehumancommunity/mpfb2.git third_party/mpfb2
fi
HOST=https://files.makehumancommunity.org
for pack in asset_packs/makehuman_system_assets/makehuman_system_assets_cc0 asset_packs/skins01/skins01_cc0 \
	asset_packs/skins02/skins02_cc0 asset_packs/eyebrows01/eyebrows01_cc0 asset_packs/eyelashes01/eyelashes01_cc0 \
	asset_packs/hair02/hair02_ccby asset_packs/bodyparts05/bodyparts05_cc0 functional/faceunits01; do
	name=$(basename "$pack")
	curl -L --fail -C - --retry 3 -o "third_party/mh_packs/$name.zip" "$HOST/$pack.zip"
	python -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "third_party/mh_packs/$name.zip" "third_party/mh_data/$name"
done
echo "Done. Now run: blender --background --factory-startup --python build_all.py -- head"
