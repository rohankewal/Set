import SwiftData
import SwiftUI

/// A plain sheet for a block of text — session notes, exercise notes. No
/// formatting, no attachments: it's a notepad, and it closes when you're done.
struct NoteEditor: View {
    let title: String
    @Binding var text: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Screen {
                VStack(alignment: .leading, spacing: 0) {
                    TextEditor(text: $text)
                        .focused($focused)
                        .font(.system(size: 16))
                        .foregroundStyle(Ink.primary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Ink.surface, in: .rect(cornerRadius: Metric.cardRadius, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Cues, niggles, what to change next time…")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Ink.tertiary)
                                    .padding(.horizontal, 19)
                                    .padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(height: 220)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 12)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        context.saveChanges()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}
