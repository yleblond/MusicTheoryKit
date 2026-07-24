import SwiftUI
import AppCore

/// MIDI settings sub-tab of the "JamShack" tab: fusion mode (one merged track vs. one track
/// per visible port), a manual refresh of the visible-source list (this app doesn't watch
/// for CoreMIDI hot-plug notifications — see `ImprovSession.refreshTracks`'s doc comment),
/// and the list itself — mirrors the CLI's `midi-mode`/`refresh-midi` commands, both part of
/// its own `catJamShack` menu category.
struct JamShackMIDIView: View {
    let session: ImprovSession

    var body: some View {
        Form {
            Section {
                Picker("Mode MIDI", selection: Binding(
                    get: { session.midiFusionMode },
                    set: { session.setMIDIFusionMode($0) }
                )) {
                    Text("Fusionne").tag(MIDIFusionMode.merged)
                    Text("Individuel").tag(MIDIFusionMode.individual)
                }
                #if os(iOS)
                .pickerStyle(.segmented)
                #endif
            } header: {
                Text("Mode MIDI")
            } footer: {
                Text("Fusionne : toutes les entrees MIDI comptent comme une seule piste. Individuel : une piste par port MIDI visible.")
            }
            Section {
                Button("Rafraichir la liste MIDI") { session.refreshTracks() }
                let sources = session.availableMIDISources()
                if sources.isEmpty {
                    Text("Aucune source MIDI visible.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(sources, id: \.self) { name in
                        Text(name)
                    }
                }
            } header: {
                Text("Sources MIDI visibles")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }
}

#Preview {
    JamShackMIDIView(session: ImprovSession())
}
