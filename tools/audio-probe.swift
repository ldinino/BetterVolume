#!/usr/bin/env swift
//
//  audio-probe.swift
//  Read-only Core Audio HAL probe. Prints every output device with the
//  properties BetterVolume depends on, so we can confirm what is actually
//  supported on a given Mac before writing code against it.
//
//  Usage:  swift tools/audio-probe.swift
//

import CoreAudio
import Foundation

let kVirtualMainVolume: AudioObjectPropertySelector = 0x766D7663 // 'vmvc'

func fourCC(_ v: UInt32) -> String {
    let bytes = [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
    return String(bytes: bytes, encoding: .ascii) ?? "\(v)"
}

func addr(_ selector: AudioObjectPropertySelector,
          _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
          _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

func string(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
    var address = address
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
    }
    return status == noErr ? value as String? : nil
}

func integer(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> UInt32? {
    var address = address
    var size = UInt32(MemoryLayout<UInt32>.size)
    var value: UInt32 = 0
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value
}

func scalar(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Float32? {
    var address = address
    var size = UInt32(MemoryLayout<Float32>.size)
    var value: Float32 = 0
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value
}

func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
    var address = address
    guard AudioObjectHasProperty(object, &address) else { return false }
    var settable = DarwinBoolean(false)
    guard AudioObjectIsPropertySettable(object, &address, &settable) == noErr else { return false }
    return settable.boolValue
}

func outputChannelCount(_ object: AudioObjectID) -> Int {
    var address = addr(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                  alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { buffer.deallocate() }
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer) == noErr else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

let system = AudioObjectID(kAudioObjectSystemObject)

var deviceListAddress = addr(kAudioHardwarePropertyDevices)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(system, &deviceListAddress, 0, nil, &size)
var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
AudioObjectGetPropertyData(system, &deviceListAddress, 0, nil, &size, &devices)

let defaultOutput = integer(system, addr(kAudioHardwarePropertyDefaultOutputDevice)) ?? 0
let defaultSystemOutput = integer(system, addr(kAudioHardwarePropertyDefaultSystemOutputDevice)) ?? 0

print("DefaultOutputDevice settable:       \(isSettable(system, addr(kAudioHardwarePropertyDefaultOutputDevice)))")
print("DefaultSystemOutputDevice settable: \(isSettable(system, addr(kAudioHardwarePropertyDefaultSystemOutputDevice)))")
print("Total audio objects: \(devices.count)\n")

for device in devices where outputChannelCount(device) > 0 {
    let name = string(device, addr(kAudioObjectPropertyName)) ?? "<unnamed>"
    var flags: [String] = []
    if device == defaultOutput { flags.append("DEFAULT OUTPUT") }
    if device == defaultSystemOutput { flags.append("DEFAULT SYSTEM OUTPUT") }

    let volumeAddress = addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput)
    let virtualAddress = addr(kVirtualMainVolume, kAudioObjectPropertyScopeOutput)
    let muteAddress = addr(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)

    print("• \(name)\(flags.isEmpty ? "" : "   [\(flags.joined(separator: ", "))]")")
    print("    id            \(device)")
    print("    transport     \(integer(device, addr(kAudioDevicePropertyTransportType)).map(fourCC) ?? "?")")
    print("    outputs       \(outputChannelCount(device)) ch")
    print("    uid           \(string(device, addr(kAudioDevicePropertyDeviceUID)) ?? "-")")
    print("    modelUID      \(string(device, addr(kAudioDevicePropertyModelUID)) ?? "-")")
    print("    canBeDefault  \(integer(device, addr(kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioObjectPropertyScopeOutput)) == 1)")
    print("    name settable \(isSettable(device, addr(kAudioObjectPropertyName)))")
    print("    volumeScalar  \(scalar(device, volumeAddress).map { String(format: "%.2f", $0) } ?? "unsupported")  settable=\(isSettable(device, volumeAddress))")
    print("    virtualMain   \(scalar(device, virtualAddress).map { String(format: "%.2f", $0) } ?? "unsupported")  settable=\(isSettable(device, virtualAddress))")
    print("    mute          \(integer(device, muteAddress).map { $0 == 1 ? "on" : "off" } ?? "unsupported")  settable=\(isSettable(device, muteAddress))")
    print("")
}
