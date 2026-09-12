import Foundation

func testMeetingMicrophonePreferences() {
    runSuite("Meeting microphone selection preserves existing defaults and explicit choice") {
        let suiteName = "MeetingMicrophonePreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        assertFalse(MeetingMicrophonePreferences.usesSystemInput(userDefaults: defaults), "existing installs must retain automatic Bluetooth isolation")
        MeetingMicrophonePreferences.setUsesSystemInput(true, userDefaults: defaults)
        assertTrue(MeetingMicrophonePreferences.usesSystemInput(userDefaults: UserDefaults(suiteName: suiteName)!), "the explicit system-mic choice must survive reopening settings")
        MeetingMicrophonePreferences.setUsesSystemInput(false, userDefaults: defaults)
        assertFalse(MeetingMicrophonePreferences.usesSystemInput(userDefaults: defaults), "the user can return to automatic selection")
    }
}
