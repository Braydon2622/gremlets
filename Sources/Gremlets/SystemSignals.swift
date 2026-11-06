import AppKit
import Carbon.HIToolbox
import CoreAudio
import CoreMediaIO
import GremletsCore

/// Cheap facts about what you're doing, read without any permission prompts:
/// - camera / microphone "in use by some app" flags (never the audio or video itself),
/// - seconds since your last keyboard/mouse input,
/// - Low Power Mode.
enum SystemSignals {

    // MARK: Camera

    /// True if any app is using any camera (CoreMediaIO's DeviceIsRunningSomewhere).
    static func cameraInUse() -> Bool {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &devices) == 0 else { return false }
        for device in devices {
            var running: UInt32 = 0
            var a = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            if CMIOObjectGetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running) == 0, running != 0 {
                return true
            }
        }
        return false
    }

    // MARK: Microphone

    private static func audioProperty<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ value: inout T) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr
    }

    private static func audioArray(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                   scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// True if some other app is recording from a microphone.
    static func microphoneInUse() -> Bool {
        let system = AudioObjectID(kAudioObjectSystemObject)
        if #available(macOS 14.2, *) {
            // Precise: per-process "is running input" (playing music through AirPods doesn't count).
            let me = getpid()
            for process in audioArray(system, kAudioHardwarePropertyProcessObjectList) {
                var pid: pid_t = 0, input: UInt32 = 0
                guard audioProperty(process, kAudioProcessPropertyPID, &pid), pid != me else { continue }
                guard audioProperty(process, kAudioProcessPropertyIsRunningInput, &input), input != 0 else { continue }
                // "Hey Siri" / dictation (corespeechd) listen all the time; that's not a call.
                if CallDetection.isBackgroundListener(path: executablePath(pid)) { continue }
                return true
            }
            return false
        }
        // Older macOS: the default input device is running, but only trust input-only devices (a headset that also
        // plays audio "runs" whenever music plays).
        var device = AudioObjectID(0), running: UInt32 = 0
        guard audioProperty(system, kAudioHardwarePropertyDefaultInputDevice, &device), device != 0 else { return false }
        guard audioArray(device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput).isEmpty else { return false }
        return audioProperty(device, kAudioDevicePropertyDeviceIsRunningSomewhere, &running) && running != 0
    }

    /// Full path of a process's executable ("" if it can't be read).
    private static func executablePath(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : ""
    }

    // MARK: Idle & power

    /// Seconds since the last keyboard, mouse or trackpad event, from any app.
    static func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    static var lowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
}

/// A system-wide shortcut via Carbon's RegisterEventHotKey (works without Accessibility permission).
final class HotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false
    private var ref: EventHotKeyRef?
    private let id: UInt32

    /// `keyCode` is a kVK_* virtual key, `modifiers` Carbon flags (controlKey, optionKey, cmdKey, shiftKey).
    init?(keyCode: Int, modifiers: Int, id: UInt32, action: @escaping () -> Void) {
        self.id = id
        if !HotKey.handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hk)
                DispatchQueue.main.async { HotKey.actions[hk.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
            guard status == noErr else { return nil }
            HotKey.handlerInstalled = true
        }
        let hkID = EventHotKeyID(signature: OSType(0x47524D4C) /* 'GRML' */, id: id)
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref) == noErr else { return nil }
        HotKey.actions[id] = action
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.actions[id] = nil
    }
}
