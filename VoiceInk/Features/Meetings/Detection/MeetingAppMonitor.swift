import AppKit
import CoreAudio
import Foundation

/// Finds meeting apps that are currently using the microphone by asking Core Audio which processes
/// have audio input running. Zoom, Teams and browsers keep the mic open for the whole call, even when muted.
enum MeetingAppMonitor {
    struct ActiveMeetingApp: Equatable {
        let bundleID: String
        let name: String
    }

    private static let meetingApps: [(prefix: String, name: String)] = [
        ("us.zoom.", "Zoom"),
        ("com.microsoft.teams", "Microsoft Teams"),
        ("com.cisco.webex", "Webex"),
        ("com.webex.", "Webex"),
        ("com.apple.FaceTime", "FaceTime"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.hnc.Discord", "Discord"),
        ("net.whatsapp.WhatsApp", "WhatsApp"),
        ("desktop.WhatsApp", "WhatsApp"),
        ("com.google.Chrome", "Google Chrome"),
        ("com.apple.Safari", "Safari"),
        ("com.apple.WebKit.GPU", "Safari"),
        ("company.thebrowser.", "Arc"),
        ("org.mozilla.firefox", "Firefox"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("com.brave.Browser", "Brave"),
        ("com.operasoftware.", "Opera"),
    ]

    static func activeMeetingApps() -> [ActiveMeetingApp] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var apps: [ActiveMeetingApp] = []

        for process in processObjects() {
            guard uint32Property(kAudioProcessPropertyIsRunningInput, of: process) == 1,
                let pid = pidProperty(of: process),
                pid != ownPID
            else { continue }

            let bundleID =
                stringProperty(kAudioProcessPropertyBundleID, of: process)
                ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            guard let bundleID,
                let match = meetingApps.first(where: { bundleID.hasPrefix($0.prefix) })
            else { continue }

            let app = ActiveMeetingApp(bundleID: match.prefix, name: match.name)
            if !apps.contains(app) {
                apps.append(app)
            }
        }

        return apps
    }

    // MARK: - Core Audio helpers

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func processObjects() -> [AudioObjectID] {
        var propertyAddress = address(kAudioHardwarePropertyProcessObjectList)
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(systemObject, &propertyAddress, 0, nil, &size) == noErr, size > 0 else {
            return []
        }

        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObject, &propertyAddress, 0, nil, &size, &objects) == noErr else {
            return []
        }
        return objects
    }

    private static func uint32Property(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> UInt32? {
        var propertyAddress = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func pidProperty(of object: AudioObjectID) -> pid_t? {
        var propertyAddress = address(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var propertyAddress = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &value) == noErr,
            let value
        else {
            return nil
        }
        let string = value.takeRetainedValue() as String
        return string.isEmpty ? nil : string
    }
}
