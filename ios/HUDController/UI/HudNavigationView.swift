import SwiftUI
import PhotosUI

struct HudNavigationView: View {
    @Bindable var state: AppState
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoStatus = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ConnectionCard(state: state)

                    HudCard {
                        VStack(spacing: 14) {
                            Image(systemName: state.navigation.current.maneuver.symbol)
                                .font(.system(size: 64, weight: .semibold))
                            Text(state.navigation.current.primaryText).font(.title2.bold())
                            Text(state.navigation.current.streetName).font(.headline).foregroundStyle(.secondary)
                            Text(distanceText(state.navigation.current.distanceMeters))
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(HudTheme.accent)
                        }.frame(maxWidth: .infinity)
                    }

                    if #available(iOS 27.0, *),
                       let capture = state.externalCapture27 as? ExternalNavigationCapture {
                        HudCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Automatic External Maps Capture").font(.headline)
                                Text(capture.status).font(.caption).foregroundStyle(.secondary)

                                Toggle("Automatically send parsed maneuver to HUD", isOn: Binding(
                                    get: { capture.autoSendToHUD },
                                    set: { capture.autoSendToHUD = $0 }
                                ))

                                Toggle("Auto-enable HUD navigation after valid OCR", isOn: Binding(
                                    get: { capture.autoEnableNavigationMode },
                                    set: { capture.autoEnableNavigationMode = $0 }
                                ))

                                Toggle("Keep screen awake during capture", isOn: Binding(
                                    get: { capture.keepScreenAwake },
                                    set: { capture.keepScreenAwake = $0 }
                                ))

                                Toggle("Try automatic capture recovery", isOn: Binding(
                                    get: { capture.autoRecoverAfterInterruption },
                                    set: { capture.autoRecoverAfterInterruption = $0 }
                                ))

                                HStack {
                                    Button("Start Full-Display Capture") {
                                        capture.presentFullDisplayPicker()
                                    }.buttonStyle(.borderedProminent)
                                    Button("Stop") { capture.stop() }.buttonStyle(.bordered)
                                }

                                Divider()
                                Text("Saved screenshot test").font(.subheadline.bold())
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    Label("Choose Maps Screenshot", systemImage: "photo")
                                }
                                .buttonStyle(.bordered)
                                .onChange(of: selectedPhoto) { _, item in
                                    guard let item else { return }
                                    Task {
                                        do {
                                            if let data = try await item.loadTransferable(type: Data.self),
                                               let image = UIImage(data: data) {
                                                await capture.analyzePhoto(image)
                                                state.navigation.current = capture.latestInstruction
                                                photoStatus = "Parsed and copied into maneuver fields"
                                            } else {
                                                photoStatus = "Could not load selected image"
                                            }
                                        } catch {
                                            photoStatus = error.localizedDescription
                                        }
                                    }
                                }
                                if !photoStatus.isEmpty {
                                    Text(photoStatus).font(.caption).foregroundStyle(.secondary)
                                }

                                LabeledContent("Detected source", value: capture.detectedSource.rawValue)
                                LabeledContent("Screen state", value: capture.detectedScreenState.rawValue)
                                LabeledContent("Parsed maneuver", value: capture.latestInstruction.maneuver.label)
                                LabeledContent("Distance", value: distanceText(capture.latestInstruction.distanceMeters))
                                LabeledContent("Street", value: capture.latestInstruction.streetName.isEmpty ? "—" : capture.latestInstruction.streetName)
                                LabeledContent("Frames OCR'd", value: "\(capture.frameCount)")
                                LabeledContent("Valid navigation frames", value: "\(capture.validNavigationFrames)")
                                LabeledContent("Rejected frames", value: "\(capture.rejectedFrames)")
                                LabeledContent("HUD navigation armed", value: capture.navigationModeArmed ? "Yes" : "No")

                                DisclosureGroup("Latest OCR text") {
                                    Text(capture.latestRawText.isEmpty ? "No OCR yet" : capture.latestRawText)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                }

                                Text("""
                                Google Maps and Apple Maps are detected automatically from OCR/layout evidence; there is no source selector. Valid route lists automatically enter Navigation mode. Apple Maps “Proceed to the route” is treated as active navigation, reroutes can replace the entire current maneuver immediately when the new layout is structurally valid, and normal Maps home/map screens return the HUD to Freeride after confirmation.

                                Screen capture has a stale-frame watchdog plus exponential automatic restart. iOS may still revoke full-display capture under system conditions such as physical lock; the app retries every recoverable interruption and reports the recovery state here.
                                """)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HudCard {
                            Text("ScreenCaptureKit full-display navigation capture requires iOS 27 or later.")
                                .font(.caption)
                        }
                    }

                    HudCard {
                        Picker("Maneuver", selection: Binding(
                            get: { state.navigation.current.maneuver },
                            set: { state.navigation.current.maneuver = $0 }
                        )) {
                            ForEach(HudManeuver.allCases) { m in Text(m.label).tag(m) }
                        }
                        TextField("Distance (m)", value: Binding(
                            get: { state.navigation.current.distanceMeters },
                            set: { state.navigation.current.distanceMeters = $0 }
                        ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                        TextField("Instruction", text: Binding(
                            get: { state.navigation.current.primaryText },
                            set: { state.navigation.current.primaryText = $0 }
                        )).textFieldStyle(.roundedBorder)
                        TextField("Street", text: Binding(
                            get: { state.navigation.current.streetName },
                            set: { state.navigation.current.streetName = $0 }
                        )).textFieldStyle(.roundedBorder)

                        HStack {
                            Button("Navigation ON") { state.navigation.navigationOn() }.buttonStyle(.borderedProminent)
                            Button("Send Maneuver") { state.navigation.sendCurrent() }.buttonStyle(.bordered)
                        }
                        Button("Navigation OFF", role: .destructive) { state.navigation.navigationOff() }
                    }
                }.padding()
            }
            .background(HudTheme.background.ignoresSafeArea())
            .navigationTitle("Navigation")
        }
    }

    private func distanceText(_ meters: Int) -> String {
        guard meters > 0 else { return "—" }
        let feet = Int(Double(meters) * 3.28084)
        if feet >= 5280 { return String(format: "%.1f mi", Double(feet) / 5280.0) }
        return "\(feet) ft"
    }
}
