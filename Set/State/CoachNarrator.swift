import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns the computed digest into a sentence using Apple Intelligence's
/// on-device model.
///
/// The division of labour matters: `Insights` does every calculation in Swift
/// and hands over finished facts; the model only chooses words. It is never
/// asked to compute, compare or estimate anything, so it cannot invent a number
/// — and when it isn't available the deterministic `plainSummary` ships instead,
/// which is why nothing in the UI depends on Apple Intelligence being there.
///
/// It also stays inside the app's privacy promise: `SystemLanguageModel` runs on
/// the device, so the training log still never leaves it.
@Observable
final class CoachNarrator {
    enum State: Equatable {
        case idle
        case unsupported(String)
        case thinking
        case ready(headline: String, detail: String)
        case failed
    }

    private(set) var state: State = .idle
    /// True when the text on screen came from the model rather than the fallback.
    private(set) var isGenerated = false
    /// The computed read is already on screen and the model is improving on it.
    private(set) var isRefining = false
    /// First generation can take a while as the model loads; after that it's
    /// quick. Either way the user never waits on it.
    private static let generationTimeout: Duration = .seconds(25)

    #if canImport(FoundationModels)
    @ObservationIgnored private var session: LanguageModelSession?
    #endif

    /// Whether this device can generate — checked before anything is offered in
    /// the UI, so a device without Apple Intelligence simply never sees it.
    var availabilityMessage: String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return "Requires iOS 26 or later." }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to have this written for you."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading its model."
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
        #else
        return "Apple Intelligence isn't available on this platform."
        #endif
    }

    var isAvailable: Bool { availabilityMessage == nil }

    /// Shows the computed read immediately, then quietly replaces it if the
    /// model produces something better. There is no spinner and no waiting: the
    /// deterministic summary is a complete answer on its own.
    func narrate(_ digest: TrainingDigest, unit: WeightUnit) async {
        guard !digest.isEmpty else {
            state = .idle
            return
        }

        let computed = digest.read(unit: unit)
        isGenerated = false
        state = .ready(headline: computed.headline, detail: computed.detail)

        guard isAvailable else { return }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            isRefining = true
            defer { isRefining = false }

            do {
                let detail = try await generate(from: Self.prompt(for: computed))
                guard !Task.isCancelled else { return }
                // Last line of defence: a rewrite may not introduce a number
                // that isn't in the supporting facts. If it does, it's dropped.
                guard Self.isGrounded(detail, in: computed) else {
                    isGenerated = false
                    return
                }
                isGenerated = true
                // The headline stays as computed — it's four words of fact, and
                // there's nothing for a rewrite to improve.
                state = .ready(headline: computed.headline, detail: detail)
            } catch {
                // Guardrails, context overflow, a timeout, no model — all end the
                // same way: the computed read stays, which was never a downgrade.
                isGenerated = false
            }
        }
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generate(from prompt: String) async throws -> String {
        let session = session ?? LanguageModelSession(instructions: Self.instructions)
        self.session = session

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let response = try await session.respond(to: prompt, generating: CoachNote.self)
                return response.content.detail
            }
            group.addTask {
                try await Task.sleep(for: Self.generationTimeout)
                throw CancellationError()
            }
            guard let first = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return first
        }
    }
    #endif

    func reset() {
        #if canImport(FoundationModels)
        session = nil
        #endif
        state = .idle
        isGenerated = false
        isRefining = false
    }

    // MARK: Prompting

    private static let instructions = """
    You rewrite one short observation about someone's strength training for a \
    minimal workout app. The observation has already been decided; your only job \
    is to say it better.

    Rules, in order of importance:
    1. Make exactly the claim you are given. Do not add a second claim, a cause, \
       an implication, or a judgement of whether it is good or bad.
    2. Use only numbers that appear in the supporting facts, exactly as written. \
       Never compute, round, convert or invent a number.
    3. Never mention a muscle, exercise or body part that is not in the facts.

    Tone: a knowledgeable training partner. Plain, direct, no hype, no emoji, no \
    exclamation marks, no greetings, no questions. At most one suggested \
    adjustment, and only if the claim you were given contains one. Never give \
    medical or injury advice.

    Write one or two sentences, at most forty words. A headline is written for \
    you elsewhere; do not write one.
    """

    private static func prompt(for read: TrainingRead) -> String {
        """
        Claim to make:
        \(read.detail)

        Supporting facts (the only numbers you may use):
        \(read.support.map { "- \($0)" }.joined(separator: "\n"))

        Rewrite the claim. Keep its meaning exactly.
        """
    }

    /// Every number in the generated text must appear in the facts it was given.
    /// Cheap, strict, and the reason a rewrite can't quietly invent a statistic.
    static func isGrounded(_ detail: String, in read: TrainingRead) -> Bool {
        let allowed = Set(numbers(in: (read.support + [read.detail]).joined(separator: " ")))
        return numbers(in: detail).allSatisfy(allowed.contains)
    }

    private static func numbers(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isNumber && $0 != "." })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
    }
}

#if canImport(FoundationModels)
/// Structured output keeps the model inside a shape the layout expects, rather
/// than parsing a paragraph and hoping.
@available(iOS 26.0, *)
@Generable
struct CoachNote {
    @Guide(description: "One or two sentences, at most forty words, restating the given claim.")
    var detail: String
}
#endif
