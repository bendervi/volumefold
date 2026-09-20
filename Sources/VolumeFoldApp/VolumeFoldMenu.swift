import SwiftUI
import ServiceManagement

struct VolumeFoldMenu: View {
    @ObservedObject var controller: VolumeController
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("VolumeFold").font(.headline)
                    Text("A quieter close.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Toggle("Enable VolumeFold", isOn: Binding(
                get: { controller.enabled },
                set: { settings.enabled = $0; controller.setEnabled($0) }
            ))
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Start fading below").font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(Int(controller.deadpoint))°")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                }
                Slider(value: Binding(
                    get: { controller.deadpoint },
                    set: { controller.setDeadpoint($0); settings.deadpoint = controller.deadpoint }
                ), in: 10...120, step: 1)
                .accessibilityLabel("Start fading below")
                .accessibilityValue("\(Int(controller.deadpoint)) degrees")
                HStack {
                    Text("10°")
                    Spacer()
                    Text("120°")
                }
                .font(.caption2).foregroundStyle(.tertiary)
                Text("0° is closed. 90° is upright.\nYour volume stays normal above this angle.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if controller.enabled {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 0) {
                        metric("LID ANGLE", value: controller.angle.map { "\(Int($0.rounded()))°" } ?? "—")
                        Spacer()
                        Rectangle().fill(.quaternary).frame(width: 1, height: 30)
                        Spacer()
                        metric("VOLUME", value: controller.output?.isMuted == true ? "Muted" : controller.output?.volume.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    }
                    if let retainedVolume {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: retainedVolume == 0 ? "speaker.slash.fill" : retainedVolume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
                                    .foregroundStyle(.tint)
                                    .frame(width: 18)
                                    .accessibilityHidden(true)
                                Text("Volume retained").foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int((retainedVolume * 100).rounded()))%")
                                    .monospacedDigit().fontWeight(.semibold)
                            }
                            .font(.caption)
                            GeometryReader { geometry in
                                Capsule().fill(Color.primary.opacity(0.1))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Color.accentColor)
                                            .frame(width: geometry.size.width * retainedVolume)
                                    }
                            }
                            .frame(height: 7)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Volume retained from your normal level")
                            .accessibilityValue("\(Int((retainedVolume * 100).rounded())) percent")
                            Text(retainedVolume < 0.995
                                 ? "Lid lowered volume by \(Int(((1 - retainedVolume) * 100).rounded()))%"
                                 : "Your normal volume · fold to lower")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }

            Label(controller.status, systemImage: controller.enabled ? "waveform" : "pause.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("volumefold.status")

            Divider()

            Toggle("Show percentage in menu bar", isOn: $settings.showMenuBarPercentage)
                .toggleStyle(.checkbox)
                .font(.subheadline)

            Toggle("Launch at login", isOn: Binding(
                get: { settings.loginEnabled }, set: { settings.setLoginEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.subheadline)

            if settings.loginNeedsApproval {
                Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    .font(.caption)
            }
            if let error = settings.loginError {
                Text(error).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Built-in speakers only").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit VolumeFold") { NSApp.terminate(nil) }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .keyboardShortcut("q")
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var retainedVolume: Double? {
        guard controller.angle != nil, let output = controller.output, output.canControl,
              !output.isMuted, let volume = output.volume,
              let normal = controller.normalVolume, normal > 0.001 else { return nil }
        return min(1, max(0, volume / normal))
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
            Text(value).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
        }
        .frame(minWidth: 98, alignment: .leading)
    }
}
