#!/bin/zsh
# Удаляет приложение и общий выход «Обе гарнитуры».
# curl -fsSL https://raw.githubusercontent.com/Elintirs/headphones-mixer/main/uninstall.sh | zsh
set -euo pipefail
NAME="Громкость наушников"
pkill -x HeadphonesMixer 2>/dev/null || true
rm -rf "$HOME/Applications/$NAME.app" "/Applications/$NAME.app"
defaults delete io.github.elintirs.headphones-mixer 2>/dev/null || true
cat > "${TMPDIR:-/tmp}/hm-uninstall.swift" <<'SWIFT'
import CoreAudio
let uids = ["io.github.elintirs.headphones-mixer.both", "claude.multiout.both-headphones"]
var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
for u in uids {
    var uid = u as CFString
    var id: AudioObjectID = 0
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, UInt32(MemoryLayout<CFString>.size), &uid, &size, &id) == noErr, id != 0 {
        AudioHardwareDestroyAggregateDevice(id)
    }
}
SWIFT
swift "${TMPDIR:-/tmp}/hm-uninstall.swift" 2>/dev/null || echo "Общий выход удалите вручную в «Настройке Audio-MIDI»"
rm -f "${TMPDIR:-/tmp}/hm-uninstall.swift"
echo "Удалено"
