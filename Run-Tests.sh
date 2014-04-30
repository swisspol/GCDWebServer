#!/bin/bash -ex

OSX_SDK="macosx"
if [ -z "$TRAVIS" ]; then
  IOS_SDK="iphoneos"
else
  IOS_SDK="iphonesimulator"
fi

OSX_TARGET="GCDWebServer (Mac)"
IOS_TARGET="GCDWebServer (iOS)"
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
  TZ=GMT find "$PAYLOAD_DIR" -type d -exec SetFile -d "1/1/2014 00:00:00" -m "1/1/2014 00:00:00" '{}' \;  # ZIP archives do not preserve directories dates
  if [ "$4" != "" ]; then
    cp -f "$4" "$PAYLOAD_DIR/Payload"
    pushd "$PAYLOAD_DIR/Payload"
    SetFile -d "1/1/2014 00:00:00" -m "1/1/2014 00:00:00" `basename "$4"`
    popd
  fi
  logLevel=2 $1 -mode "$2" -root "$PAYLOAD_DIR/Payload" -tests "$3"
}

# Build for iOS in manual memory management mode (TODO: run tests on iOS)
rm -rf "$MRC_BUILD_DIR"
xcodebuild -sdk "$IOS_SDK" -target "$IOS_TARGET" -configuration "$CONFIGURATION" build "SYMROOT=$MRC_BUILD_DIR" "CLANG_ENABLE_OBJC_ARC=NO" > /dev/null

# Build for iOS in ARC mode (TODO: run tests on iOS)
rm -rf "$ARC_BUILD_DIR"
xcodebuild -sdk "$IOS_SDK" -target "$IOS_TARGET" -configuration "$CONFIGURATION" build "SYMROOT=$ARC_BUILD_DIR" "CLANG_ENABLE_OBJC_ARC=YES" > /dev/null

# Build for OS X in manual memory management mode
rm -rf "$MRC_BUILD_DIR"
xcodebuild -sdk "$OSX_SDK" -target "$OSX_TARGET" -configuration "$CONFIGURATION" build "SYMROOT=$MRC_BUILD_DIR" "CLANG_ENABLE_OBJC_ARC=NO" > /dev/null

# Build for OS X in ARC mode
rm -rf "$ARC_BUILD_DIR"
xcodebuild -sdk "$OSX_SDK" -target "$OSX_TARGET" -configuration "$CONFIGURATION" build "SYMROOT=$ARC_BUILD_DIR" "CLANG_ENABLE_OBJC_ARC=YES" > /dev/null

# Run tests
runTests $MRC_PRODUCT "htmlForm" "Tests/HTMLForm"
runTests $ARC_PRODUCT "htmlForm" "Tests/HTMLForm"
runTests $MRC_PRODUCT "htmlFileUpload" "Tests/HTMLFileUpload"
runTests $ARC_PRODUCT "htmlFileUpload" "Tests/HTMLFileUpload"
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
runTests $MRC_PRODUCT "webServer" "Tests/WebServer-Sample-Movie" "Tests/Sample-Movie.mp4"
runTests $ARC_PRODUCT "webServer" "Tests/WebServer-Sample-Movie" "Tests/Sample-Movie.mp4"

# Done
echo "\nAll tests completed successfully!"
