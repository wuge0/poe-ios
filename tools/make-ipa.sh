#!/bin/sh
#
# make-ipa.sh —— 构建无签名 IPA（TrollStore 可直接安装）
#
# 用法:
#   ./tools/make-ipa.sh
#
# 产物:
#   dist/Poe.ipa
#

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

PROJECT_PATH="$ROOT_DIR/Poe.xcodeproj"
SCHEME="Poe"
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE_PATH="$DIST_DIR/Poe.xcarchive"
APP_NAME="Poe"
OUTPUT_NAME="Poe.ipa"

echo "=== 清理旧产物 ==="
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "=== Xcode 版本 ==="
xcodebuild -version

echo "=== 归档（无签名）==="
xcodebuild archive \
	-project "$PROJECT_PATH" \
	-scheme "$SCHEME" \
	-sdk iphoneos \
	-arch arm64 \
	-configuration Release \
	-archivePath "$ARCHIVE_PATH" \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGN_IDENTITY="" \
	PROVISIONING_PROFILE_SPECIFIER="" \
	CODE_SIGN_ENTITLEMENTS="" \
	| tail -20

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
	echo "错误: 找不到构建产物 $APP_PATH"
	echo "归档目录内容:"
	find "$ARCHIVE_PATH/Products" -maxdepth 3 2>/dev/null || true
	exit 1
fi

echo "=== 校验 Info.plist ==="
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist" || true
/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$APP_PATH/Info.plist" || true

echo "=== 组装 Payload ==="
WORK_DIR="$DIST_DIR/ipa-work"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/Payload"

# 用 ditto 保留符号链接与权限，避免 .app 结构被破坏
ditto "$APP_PATH" "$WORK_DIR/Payload/$APP_NAME.app"

echo "=== 检查可执行文件架构 ==="
lipo -info "$WORK_DIR/Payload/$APP_NAME.app/$APP_NAME" || true

echo "=== 打包 IPA ==="
cd "$WORK_DIR"

# 清理扩展属性，否则部分安装器解压会失败
xattr -cr Payload 2>/dev/null || true

zip -q -r "$DIST_DIR/$OUTPUT_NAME" Payload \
	-x "._*" -x ".DS_Store" -x "__MACOSX" -x "*.dSYM"

cd "$ROOT_DIR"

echo "=== 完成 ==="
ls -lh "$DIST_DIR/$OUTPUT_NAME"
echo "产物路径: $DIST_DIR/$OUTPUT_NAME"
