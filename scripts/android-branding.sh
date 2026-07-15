#!/usr/bin/env bash
# ============================================================
#  大帅拼音 Android 品牌化补丁（应用于 osfans/trime 源码树）
#  用法: bash android-branding.sh <trime源码目录> <数据暂存目录> <图标目录>
#    数据暂存目录 = make-android-pack.ps1 的 stage（含 wanxiang 全套 + gram + 皮肤）
#    图标目录     = make-android-icons.py 的输出（mipmap-*/drawable-*）
#  改动：应用名/图标/applicationId/默认方案/内置数据/仅 arm64
# ============================================================
set -euo pipefail
TRIME="$1"; DATA="$2"; ICONS="$3"
cd "$TRIME"

echo '==> 1. 应用名：大帅拼音'
for f in app/src/main/res/values*/strings.xml; do
    sed -i \
      -e 's|<string name="app_name_release">[^<]*</string>|<string name="app_name_release">大帅拼音</string>|' \
      -e 's|<string name="app_name_debug">[^<]*</string>|<string name="app_name_debug">大帅拼音（调试）</string>|' \
      "$f"
done

echo '==> 2. applicationId'
sed -i 's|applicationId = "com.osfans.trime"|applicationId = "com.dashuai.pinyin"|' app/build.gradle.kts
# 架构裁剪不改源码：构建时用 Trime 官方环境变量 BUILD_ABI=arm64-v8a
# （直接加 ndk.abiFilters 会与 Trime 的 splits 配置冲突导致配置期报错）
# 另需环境变量：BUILD_VERSION_NAME=<版本>（浅克隆无 tag，git describe 会炸）、
#              CI_NAME=<名字>（构建机未配 git user.name 时 runCmd 会炸）

echo '==> 3. 默认方案：万象'
python3 - <<'PYEOF'
import io
p = 'app/src/main/java/com/osfans/trime/data/base/DataManager.kt'
s = io.open(p, encoding='utf-8').read()
old = """        schema_list:
          - schema: luna_pinyin
          - schema: luna_pinyin_simp"""
new = """        schema_list:
          - schema: wanxiang"""
assert old in s, 'luna schema_list not found'
io.open(p, 'w', encoding='utf-8').write(s.replace(old, new))
print('DataManager.kt patched')
PYEOF

echo '==> 4. 图标：帅'
sed -i 's|#FFFFFF|#2B5BD7|' app/src/main/res/values/ic_app_icon_background.xml
rm -f app/src/main/res/drawable/ic_app_icon_foreground.xml
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
    cp "$ICONS/mipmap-$d/ic_app_icon.png"       "app/src/main/res/mipmap-$d/ic_app_icon.png"
    cp "$ICONS/mipmap-$d/ic_app_icon_round.png" "app/src/main/res/mipmap-$d/ic_app_icon_round.png"
    mkdir -p "app/src/main/res/drawable-$d"
    cp "$ICONS/drawable-$d/ic_app_icon_foreground.png" "app/src/main/res/drawable-$d/ic_app_icon_foreground.png"
done

echo '==> 5. 内置数据：万象 + 语言模型 + 大帅定制 + 简纯+皮肤'
AS=app/src/main/assets/shared
rm -f "$AS"/luna_*.yaml "$AS"/stroke.dict.yaml "$AS"/stroke.schema.yaml \
      "$AS"/essay.txt "$AS"/pinyin.yaml "$AS"/default.yaml "$AS"/luna_quanpin.schema.yaml
cp "$DATA"/*.yaml "$DATA"/custom_phrase.txt "$AS"/
cp -r "$DATA"/dicts "$DATA"/lua "$AS"/
cp "$DATA"/wanxiang-lts-zh-hans.gram "$AS"/
cp "$DATA"/'简纯+.trime.yaml' "$AS"/
cp -r "$DATA"/backgrounds "$DATA"/fonts "$AS"/

echo '==> 完成。核验：'
grep -m1 'app_name_release' app/src/main/res/values-zh-rCN/strings.xml
grep -m1 'applicationId =' app/build.gradle.kts
grep -m1 'abiFilters' app/build.gradle.kts
grep -m1 -A1 'schema_list' app/src/main/java/com/osfans/trime/data/base/DataManager.kt | tail -1
du -sh "$AS"
