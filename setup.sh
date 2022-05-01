#!/bin/sh
podFile="./Podfile"

initPodfile() {
cat << EOT >> "$podFile"
platform :ios, '13.0'

workspace './GCDWebServer.xcodeproj'

target 'GCDWebServer (iOS)' do
  pod "GCDWebServer", "~> 3.0"
  pod "GCDWebServer/WebUploader", "~> 3.0"
  pod "GCDWebServer/WebDAV", "~> 3.0"
end
EOT

}

if [ ! -f "$podFile" ]; then
    echo '\033[33mDefaut using iOS!\033[0m'
    echo '* Creating Podfile...'
    touch "$podFile"
    initPodfile
    echo '\033[32m  Done\033[0m'
else 
    echo '\033[33mPodfile is exist!\033[0m'
fi

echo '* pod install...'
pod install
