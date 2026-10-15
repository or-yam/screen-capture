import Carbon.HIToolbox
import Foundation

final class GlobalShortcutManager {
    private let handler: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        guard hotKeyRef == nil else { return }

        guard installEventHandlerIfNeeded() else { return }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharacterCode("SCAP"), id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            AppLogging.lifecycle.error("Global shortcut registration failed status=\(status)")
            stop()
            return
        }

        self.hotKeyRef = hotKeyRef
        AppLogging.lifecycle.notice("Global shortcut registered: Cmd+Shift+S")
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installEventHandlerIfNeeded() -> Bool {
        guard eventHandlerRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard
                    let event,
                    let userData
                else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr, hotKeyID.signature == fourCharacterCode("SCAP"), hotKeyID.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.handler()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        if status != noErr {
            AppLogging.lifecycle.error("Global shortcut event handler installation failed status=\(status)")
            return false
        }

        return true
    }
}

private func fourCharacterCode(_ string: String) -> OSType {
    var result: OSType = 0

    for byte in string.utf8 {
        result = (result << 8) + OSType(byte)
    }

    return result
}
