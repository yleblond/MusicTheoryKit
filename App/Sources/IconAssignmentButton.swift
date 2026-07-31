import SwiftUI
import AppCore
import Localization

/// One reusable icon-assignment control, shared by all 4 icon-assignable object kinds (scenes,
/// roles, favorite instruments, MIDI keyboards) instead of duplicating the same menu 4 times: a
/// `Menu` whose label shows the current icon (or `defaultIcon` if none assigned yet), offering
/// "Suggerer par IA" (only when a connection is configured) plus every icon in `IconVocabulary`
/// as a manual fallback — usable with no LLM connection at all, per explicit user request.
struct IconAssignmentButton: View {
    let currentIcon: String?
    let defaultIcon: String
    let canUseAI: Bool
    let language: AppLanguage
    /// Does the real work (session `suggestIcon` + the object-specific `set...Icon` persist) —
    /// plain throwing, not `async`: real network I/O, so this view wraps it in the same
    /// `Task { await Task.detached { ... } }` bridge used everywhere else in the app for a
    /// session call that shouldn't block the main thread.
    let onSuggestAI: @Sendable () throws -> Void
    let onPickManual: (String) -> Void
    let onError: (String) -> Void

    @State private var isSuggesting = false

    var body: some View {
        Menu {
            if canUseAI {
                Button {
                    suggest()
                } label: {
                    Label(L10n.string(.appButtonSuggererParIA, language), systemImage: "sparkles")
                }
                .disabled(isSuggesting)
                Divider()
            }
            ForEach(IconVocabulary.allowedSymbolNames, id: \.self) { name in
                Button {
                    onPickManual(name)
                } label: {
                    Label(name, systemImage: name)
                }
            }
        } label: {
            if isSuggesting {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: currentIcon ?? defaultIcon)
            }
        }
        .disabled(isSuggesting)
    }

    private func suggest() {
        isSuggesting = true
        let onSuggestAI = onSuggestAI
        Task {
            let outcome = await Task.detached {
                Result { try onSuggestAI() }
            }.value
            isSuggesting = false
            if case .failure(let error) = outcome { onError("\(error)") }
        }
    }
}
