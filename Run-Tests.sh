#!/bin/sh -ex

TARGET="GCDWebServer (Mac)"
CONFIGURATION="Release"
PAYLOAD_ZIP="Tests/Payload.zip"
PAYLOAD_DIR="/tmp/payload"

MRC_BUILD_DIR="/tmp/GCDWebServer-MRC"
MRC_PRODUCT="$MRC_BUILD_DIR/$CONFIGURATION/GCDWebServer"
ARC_BUILD_DIR="/tmp/GCDWebServer-ARC"
ARC_PRODUCT="$ARC_BUILD_DIR/$CONFIGURATION/GCDWebServer"

function runTests {
  rm -rf "$PAYLOAD_DIR"
  ditto -x -k "$PAYLOAD_ZIP" "$PAYLOAD_DIR"
  logLevel=2 $1 -root "$PAYLOAD_DIR" -tests "$2"
}

# Build in manual memory management mode
rm -rf "MRC_BUILD_DIR"
xcodebuild -target "$TARGET" -configuration "$CONFIGURATION" build "SYMROOT=$MRC_BUILD_DIR" "CLANG_ENABLE_OBJC_ARC=NO" > /dev/null

# Build in ARC mode
rm -rf "ARC_BUILD_DIR"
xcodebuild -target "$TARGET" -configuration "$CONFIGURATION" build "SYMROOT=$ARC_BUILD_DIR" "CLANG_ENABLE_OBJC_ARC=YES" > /dev/null

# Run tests
runTests $MRC_PRODUCT "WebServer"
runTests $ARC_PRODUCT "WebServer"

# Done
echo "\nAll tests completed successfully!"
