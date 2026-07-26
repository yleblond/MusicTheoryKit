import SwiftUI
import AppCore
import MusicTheoryKit
import PieceModel
import Localization

/// "Couleurs" sub-tab of the "JamShack" tab: the active color palette (mirrors the CLI's
/// "Choisir palette de couleur..." menu item), the LUMI Keys settings (root/scale color,
/// brightness, run/guide auto-propagation) — same 7 entries as the CLI's own LUMI menu block
/// — and (below LUMI) a manual tester that sends real LUMI commands directly, bypassing the
/// Run/Guide auto-propagation entirely, for diagnosing "the LUMI still doesn't light up".
struct JamShackColorsView: View {
    let session: ImprovSession

    @State private var actionError: String?
    @State private var visibleDestinations: [String]?
    @State private var lumiTestResult: String?
    /// Hex text for the SysEx envelope's device-ID byte, editable — see
    /// `LumiSysex.envelope`'s doc comment: this may be a topology-assigned ID that changes
    /// after an unplug/replug, not a fixed constant, which is the leading suspect for "LUMI
    /// worked once, then stopped" reports. Defaults to the built-in "34" (hex for 0x34).
    @State private var deviceIDHex = "34"
    @State private var paletteEditorTarget: PaletteEditorTarget?

    private enum PaletteEditorTarget: Identifiable {
        case new
        case existing(Int)
        var id: String {
            switch self {
            case .new: return "new"
            case .existing(let index): return "existing-\(index)"
            }
        }
        var index: Int? {
            if case .existing(let index) = self { return index }
            return nil
        }
    }

    private var resolvedDeviceID: UInt8 {
        UInt8(deviceIDHex, radix: 16) ?? 0x34
    }

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            paletteSection
            lumiSection
            lumiTestSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .sheet(item: $paletteEditorTarget) { target in
            PaletteEditorView(session: session, existingIndex: target.index)
        }
    }

    @ViewBuilder
    private var paletteSection: some View {
        Section {
            ForEach(Array(session.colorPalettes.enumerated()), id: \.offset) { index, palette in
                HStack {
                    Button {
                        do {
                            try session.selectColorPalette(atIndex: index)
                        } catch {
                            actionError = "\(error)"
                        }
                    } label: {
                        HStack {
                            Text(palette.name).foregroundStyle(.primary)
                            Spacer()
                            HStack(spacing: 2) {
                                ForEach(palette.colors, id: \.self) { hex in
                                    Circle().fill(Color(hex: hex)).frame(width: 10, height: 10)
                                }
                            }
                            if index == session.activeColorPaletteIndex {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Button {
                        paletteEditorTarget = .existing(index)
                    } label: {
                        Image(systemName: "pencil.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button(L10n.string(.appButtonNouvellePalette, session.currentLanguage)) { paletteEditorTarget = .new }
        } header: {
            Text(L10n.string(.fieldPaletteDeCouleur, session.currentLanguage))
        }
    }

    @ViewBuilder
    private var lumiSection: some View {
        Section {
            HStack {
                Text(L10n.string(.appHeadingCouleurRacine, session.currentLanguage))
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { Color(hex: session.lumiSettings.rootColorHex) },
                    set: { newColor in
                        do {
                            try session.setLumiRootColor(hex: newColor.hexString)
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                ))
                .labelsHidden()
            }
            HStack {
                Text(L10n.string(.appHeadingCouleurGamme, session.currentLanguage))
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { Color(hex: session.lumiSettings.scaleColorHex) },
                    set: { newColor in
                        do {
                            try session.setLumiScaleColor(hex: newColor.hexString)
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                ))
                .labelsHidden()
            }
            VStack(alignment: .leading) {
                Text(L10n.string(.appFormatLuminositePourcent, session.currentLanguage, session.lumiSettings.brightnessPercentage))
                Slider(
                    value: Binding(
                        get: { Double(session.lumiSettings.brightnessPercentage) },
                        set: { newValue in
                            do {
                                try session.setLumiBrightness(Int(newValue))
                            } catch {
                                actionError = "\(error)"
                            }
                        }
                    ),
                    in: 0...100,
                    step: 1
                )
            }
            Toggle(L10n.string(.appToggleModeRunPropagation, session.currentLanguage), isOn: Binding(
                get: { session.lumiSettings.autoPropagateRunMode },
                set: { newValue in
                    do {
                        try session.setLumiAutoPropagateRunMode(newValue)
                    } catch {
                        actionError = "\(error)"
                    }
                }
            ))
            Toggle(L10n.string(.appToggleModeGuidePropagation, session.currentLanguage), isOn: Binding(
                get: { session.lumiSettings.autoPropagateGuideMode },
                set: { newValue in
                    do {
                        try session.setLumiAutoPropagateGuideMode(newValue)
                    } catch {
                        actionError = "\(error)"
                    }
                }
            ))
        } header: {
            Text(L10n.string(.appHeadingLumiKeys, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintPropagationAutoLumi, session.currentLanguage))
        }
    }

    @ViewBuilder
    private var lumiTestSection: some View {
        Section {
            Button(L10n.string(.appButtonListerDestinationsMidi, session.currentLanguage)) {
                visibleDestinations = ImprovSession.visibleMIDIDestinationNames()
            }
            if let visibleDestinations {
                if visibleDestinations.isEmpty {
                    Text(L10n.string(.appPlaceholderAucuneDestinationMidi, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(visibleDestinations, id: \.self) { name in
                        Text(name).font(.caption).foregroundStyle(name.localizedCaseInsensitiveContains("lumi") ? .green : .secondary)
                    }
                }
            }
            HStack {
                Text(L10n.string(.appFieldIDAppareilHex, session.currentLanguage))
                Spacer()
                TextField(L10n.string(.appPlaceholder34, session.currentLanguage), text: $deviceIDHex)
                    #if os(iOS)
                    .keyboardType(.asciiCapable)
                    #endif
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
            }
            Button(L10n.string(.appButtonTesterModePiano, session.currentLanguage)) {
                do {
                    try session.testLumiPianoMode(deviceID: resolvedDeviceID)
                    lumiTestResult = "Commande envoyee (mode piano)."
                } catch {
                    lumiTestResult = "Echec : \(error)"
                }
            }
            Button(L10n.string(.appButtonTesterCarteGuide, session.currentLanguage)) {
                guard let rootColor = LumiColorHex.rgb(session.lumiSettings.rootColorHex),
                      let scaleColor = LumiColorHex.rgb(session.lumiSettings.scaleColorHex) else {
                    lumiTestResult = "Couleurs LUMI invalides."
                    return
                }
                do {
                    try session.pushLumiGuideMap(
                        mode: ModeReference(tonic: 0, scaleID: ScaleLibrary.all[0].id),
                        rootColor: rootColor, scaleColor: scaleColor,
                        brightnessPercentage: session.lumiSettings.brightnessPercentage
                    )
                    lumiTestResult = "Carte guide envoyee (Do majeur)."
                } catch {
                    lumiTestResult = "Echec : \(error)"
                }
            }
            if let lumiTestResult {
                Text(lumiTestResult).font(.caption).foregroundStyle(lumiTestResult.hasPrefix("Echec") ? .red : .green)
            }
        } header: {
            Text(L10n.string(.appHeadingTesteurLumi, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintTesteurLumiDetail, session.currentLanguage))
        }
    }
}

#Preview {
    JamShackColorsView(session: ImprovSession())
}
