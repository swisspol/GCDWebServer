#!/bin/sh -exuo pipefail

# brew install clang-format

SWIFT_FORMAT_VERSION='0.44.5'

CLANG_FORMAT_VERSION=`clang-format -version | awk '{ print $3 }'`
if [[ "$CLANG_FORMAT_VERSION" != "9.0.0" ]]; then
  echo "Unsupported clang-format version"
  exit 1
fi

if [[ ! -f "build/swiftformat" ]]; then
  mkdir -p "build"
  curl -sfL -o "build/SwiftFormat.zip" "https://github.com/nicklockwood/SwiftFormat/archive/$SWIFT_FORMAT_VERSION.zip"
  unzip "build/SwiftFormat.zip" "SwiftFormat-$SWIFT_FORMAT_VERSION/CommandLineTool/swiftformat" -d "build"
  mv "build/SwiftFormat-$SWIFT_FORMAT_VERSION/CommandLineTool/swiftformat" "build/swiftformat"
fi

pushd "GCDWebServer/Core"
clang-format -style=file -i *.h *.m
popd
pushd "GCDWebServer/Requests"
clang-format -style=file -i *.h *.m
popd
pushd "GCDWebServer/Responses"
clang-format -style=file -i *.h *.m
popd
pushd "GCDWebUploader"
clang-format -style=file -i *.h *.m
popd
pushd "GCDWebDAVServer"
clang-format -style=file -i *.h *.m
popd

pushd "Frameworks"
clang-format -style=file -i *.h *.m
popd
pushd "Mac"
clang-format -style=file -i *.m
popd

build/swiftformat --indent 2 "iOS" "tvOS"

echo "OK"
