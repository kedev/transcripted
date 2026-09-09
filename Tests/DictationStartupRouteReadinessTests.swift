import Foundation

/// Exercises startup decisions with a fake AUHAL binding. This verifies the
/// selected route can pass readiness; it does not claim live AirPods capture.
func testDictationStartupRouteReadiness() {
    let headset = DictationAudioDevice(
        id: 1,
        name: "Bluetooth Headset",
        transport: .bluetooth,
        inputChannelCount: 1
    )
    let builtIn = DictationAudioDevice(
        id: 2,
        name: "MacBook Microphone",
        transport: .builtIn,
        inputChannelCount: 1
    )
    let recoverySelection = DictationInputDeviceSelection(
        defaultInput: headset,
        selectedInput: headset,
        defaultOutput: headset,
        reason: .builtInFallbackSuppressedForRecoveryAttempt
    )

    runSuite("Dictation startup follows the selected headset in normal and recovery starts") {
        for isRecoveryAttempt in [false, true] {
            let selection = DictationInputDeviceSelectionPolicy.selection(
                defaultInput: headset,
                defaultOutput: headset,
                availableInputs: [headset, builtIn],
                allowsBuiltInBluetoothFallback: !isRecoveryAttempt
            )
            assertEqual(selection.selectedInput, headset, "both production start paths must follow the macOS input")
            assertEqual(selection.reason, .defaultIsSafe, "recovery alone must not opt into built-in microphone selection")
            assertFalse(selection.didOverrideDefault, "a visible built-in microphone must not override the user's headset")

            for speechRate in [8_000.0, 16_000.0, 24_000.0] {
                var boundDeviceID = builtIn.id
                var boundDeviceWrites: [UInt32] = []
                do {
                    let didBind = try DictationInputDeviceBindingPolicy.apply(
                        selection: selection,
                        currentDeviceID: { boundDeviceID },
                        setDeviceID: { deviceID in
                            boundDeviceWrites.append(deviceID)
                            boundDeviceID = deviceID
                        }
                    )
                    assertTrue(didBind, "a stale built-in binding must move to the selected headset")
                    try DictationInputDeviceBindingPolicy.verify(
                        selectedDeviceID: selection.selectedInput.id,
                        boundDeviceID: boundDeviceID
                    )
                } catch {
                    assertTrue(false, "production selection should bind the fake headset: \(error)")
                    continue
                }

                let readiness = startupReadiness(
                    selection: selection,
                    inputRate: speechRate,
                    outputRate: speechRate
                )
                assertEqual(boundDeviceWrites, [headset.id], "startup must bind only the headset selected by the production policy")
                assertEqual(readiness, .ready, "normal and recovery starts must accept matched \(Int(speechRate)) Hz headset formats")
                assertEqual(readiness.startFailureReason, nil, "following the headset must not enter route-settling retries")

                var recoveryState = ParakeetRecoveryState()
                let generation = recoveryState.beginConfigChange()
                if ParakeetDeviceRecoveryReadinessPolicy.action(for: readiness) == .finishRecovery {
                    _ = recoveryState.finishRecovery(success: true, generation: generation)
                }
                assertTrue(recoveryState.canStartRecording, "the production-selected headset must release the recording readiness gate")
            }
        }
    }

    runSuite("Dictation startup recovery accepts matched Bluetooth speech formats") {
        for speechRate in [8_000.0, 16_000.0, 24_000.0] {
            var boundDeviceID = builtIn.id
            var boundDeviceWrites: [UInt32] = []
            do {
                let didBind = try DictationInputDeviceBindingPolicy.apply(
                    selection: recoverySelection,
                    currentDeviceID: { boundDeviceID },
                    setDeviceID: { deviceID in
                        boundDeviceWrites.append(deviceID)
                        boundDeviceID = deviceID
                    }
                )
                assertTrue(didBind, "recovery must bind the selected headset after a prior built-in attempt")
                try DictationInputDeviceBindingPolicy.verify(
                    selectedDeviceID: recoverySelection.selectedInput.id,
                    boundDeviceID: boundDeviceID
                )
            } catch {
                assertTrue(false, "fake headset binding should succeed: \(error)")
                continue
            }

            let readiness = startupReadiness(
                selection: recoverySelection,
                inputRate: speechRate,
                outputRate: speechRate
            )
            assertEqual(boundDeviceWrites, [headset.id], "startup must bind only the chosen headset")
            assertEqual(readiness, .ready, "a matched \(Int(speechRate)) Hz headset must get the promised recovery start")
            assertEqual(readiness.startFailureReason, nil, "a valid native speech format must not enter route-settling retries")

            var recoveryState = ParakeetRecoveryState()
            let generation = recoveryState.beginConfigChange()
            if ParakeetDeviceRecoveryReadinessPolicy.action(for: readiness) == .finishRecovery {
                _ = recoveryState.finishRecovery(success: true, generation: generation)
            }
            assertTrue(recoveryState.canStartRecording, "matched headset formats must release the recording readiness gate")
        }
    }

    runSuite("Dictation startup recovery keeps stale and invalid format protection") {
        for speechRate in [8_000.0, 16_000.0, 24_000.0] {
            assertEqual(
                startupReadiness(selection: recoverySelection, inputRate: 48_000, outputRate: speechRate),
                .routeNotSettled,
                "48 kHz hardware paired with a stale speech bus must still settle"
            )
        }
        assertEqual(
            startupReadiness(selection: recoverySelection, inputRate: 0, outputRate: 24_000),
            .invalid,
            "zero-rate hardware must never become ready merely because Bluetooth is selected"
        )
        assertEqual(
            startupReadiness(selection: recoverySelection, inputRate: 24_000, outputRate: 48_000),
            .ready,
            "native headset input with CoreAudio output conversion must remain supported"
        )
    }
}

private func startupReadiness(
    selection: DictationInputDeviceSelection,
    inputRate: Double,
    outputRate: Double
) -> ParakeetAudioFormatReadiness {
    ParakeetAudioFormatReadinessPolicy.readiness(
        outputSampleRate: outputRate,
        outputChannelCount: 1,
        inputSampleRate: inputRate,
        inputChannelCount: 1,
        selectedInputClass: DictationInputDeviceSelectionPolicy.deviceClass(for: selection.selectedInput),
        outputDeviceClass: selection.defaultOutput.map(DictationInputDeviceSelectionPolicy.deviceClass(for:)) ?? "unknown",
        selectionOverrodeDefault: selection.didOverrideDefault,
        selectionReason: selection.reason
    )
}
