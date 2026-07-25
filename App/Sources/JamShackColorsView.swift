import SwiftUI
import AppCore
import MusicTheoryKit
import PieceModel

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
    }

    @ViewBuilder
    private var paletteSection: some View {
        Section {
            ForEach(Array(session.colorPalettes.enumerated()), id: \.offset) { index, palette in
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
            }
        } header: {
            Text("Palette de couleur")
        }
    }

    @ViewBuilder
    private var lumiSection: some View {
        Section {
            HStack {
                Text("Couleur racine")
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
                Text("Couleur gamme")
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
                Text("Luminosite : \(session.lumiSettings.brightnessPercentage)%")
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
            Toggle("Mode Run : propagation automatique", isOn: Binding(
                get: { session.lumiSettings.autoPropagateRunMode },
                set: { newValue in
                    do {
                        try session.setLumiAutoPropagateRunMode(newValue)
                    } catch {
                        actionError = "\(error)"
                    }
                }
            ))
            Toggle("Mode Guide : propagation automatique", isOn: Binding(
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
            Text("LUMI Keys")
        } footer: {
            Text("La propagation automatique envoie la carte de couleurs au clavier LUMI des qu'un accord/mode est reconnu, sans commande manuelle.")
        }
    }

    @ViewBuilder
    private var lumiTestSection: some View {
        Section {
            Button("Lister les destinations MIDI visibles") {
                visibleDestinations = ImprovSession.visibleMIDIDestinationNames()
            }
            if let visibleDestinations {
                if visibleDestinations.isEmpty {
                    Text("Aucune destination MIDI visible.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(visibleDestinations, id: \.self) { name in
                        Text(name).font(.caption).foregroundStyle(name.localizedCaseInsensitiveContains("lumi") ? .green : .secondary)
                    }
                }
            }
            HStack {
                Text("ID appareil (hex)")
                Spacer()
                TextField("34", text: $deviceIDHex)
                    #if os(iOS)
                    .keyboardType(.asciiCapable)
                    #endif
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
            }
            Button("Tester : mode piano") {
                do {
                    try session.testLumiPianoMode(deviceID: resolvedDeviceID)
                    lumiTestResult = "Commande envoyee (mode piano)."
                } catch {
                    lumiTestResult = "Echec : \(error)"
                }
            }
            Button("Tester : carte du guide (Do majeur)") {
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
            Text("Testeur LUMI")
        } footer: {
            Text("Envoie une vraie commande directement au clavier LUMI, sans passer par la propagation automatique Run/Guide — pour verifier que le clavier recoit bien quelque chose (ex: le mode piano doit s'afficher immediatement dessus). Si aucune destination ne contient \"lumi\" ci-dessus, c'est un probleme de detection, pas de commande. Si la detection est bonne mais que rien ne s'affiche (ou que ca marchait puis a arrete), l'ID appareil (0x34 par defaut) est peut-etre en cause — essaie d'autres valeurs hexadecimales ici.")
        }
    }
}

#Preview {
    JamShackColorsView(session: ImprovSession())
}
