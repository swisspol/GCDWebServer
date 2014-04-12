#!/bin/sh -ex

TARGET="GCDWebServer (Mac)"
CONFIGURATION="Release"

MRC_BUILD_DIR="/tmp/GCDWebServer-MRC"
MRC_PRODUCT="$MRC_BUILD_DIR/$CONFIGURATION/GCDWebServer"
ARC_BUILD_DIR="/tmp/GCDWebServer-ARC"
ARC_PRODUCT="$ARC_BUILD_DIR/$CONFIGURATION/GCDWebServer"

PAYLOAD_ZIP="Tests/Payload.zip"
PAYLOAD_DIR="/tmp/GCDWebServer"

function runTests {
  rm -rf "$PAYLOAD_DIR"
  ditto -x -k "$PAYLOAD_ZIP" "$PAYLOAD_DIR"
  find "$PAYLOAD_DIR" -type d -exec SetFile -d "1/1/2014" -m "1/1/2014" '{}' \;  # ZIP archives do not preserve directories dates
  logLevel=2 $1 -mode "$2" -root "$PAYLOAD_DIR/Payload" -tests "$3"
}

# Build in manual memory management mode
rm -rf "MRC_BUILD_DIR"
xcodebuild -target "$TARGET" -configuration "$CONFIGURATION" build "SYMROOT=$MRC_BUILD_DIR" "CLANG_ENABLE_OBJC_ARC=NO" > /dev/null

# Build in ARC mode
rm -rf "ARC_BUILD_DIR"
xcodebuild -target "$TARGET" -configuration "$CONFIGURATION" build "SYMROOT=$ARC_BUILD_DIR" "CLANG_ENABLE_OBJC_ARC=YES" > /dev/null

# Run tests
runTests $MRC_PRODUCT "webServer" "Tests/WebServer"
runTests $ARC_PRODUCT "webServer" "Tests/WebServer"
runTests $MRC_PRODUCT "webDAV" "Tests/WebDAV-Transmit"
runTests $ARC_PRODUCT "webDAV" "Tests/WebDAV-Transmit"
runTests $MRC_PRODUCT "webDAV" "Tests/WebDAV-Cyberduck"
runTests $ARC_PRODUCT "webDAV" "Tests/WebDAV-Cyberduck"
runTests $MRC_PRODUCT "webDAV" "Tests/WebDAV-Finder"
runTests $ARC_PRODUCT "webDAV" "Tests/WebDAV-Finder"
runTests $MRC_PRODUCT "webUploader" "Tests/WebUploader"
runTests $ARC_PRODUCT "webUploader" "Tests/WebUploader"

# Done
echo "\nAll tests completed successfully!"
