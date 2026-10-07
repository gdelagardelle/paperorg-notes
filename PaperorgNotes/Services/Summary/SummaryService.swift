import Foundation

@MainActor
final class SummaryService {
    private let settings: SettingsService
    private let proBackend: ProBackendClient

    init(settings: SettingsService, keychain _: KeychainService, proBackend: ProBackendClient) {
        self.settings = settings
        self.proBackend = proBackend
    }

    func generate(
        transcript: String,
        outputType: OutputType,
        language: AppLanguage,
        languageName: String? = nil,
        length: SummaryLength? = nil,
        translating: Bool = false
    ) async throws -> SummaryGeneration {
        if outputType == .rawTranscript {
            return .notRequested
        }

        guard settings.usesBackendProcessing else {
            throw ProBackendError.subscriptionRequired
        }
        return try await generateViaProBackend(
            transcript: transcript,
            outputType: outputType,
            language: language,
            languageName: languageName,
            length: length ?? settings.summaryLength,
            translating: translating
        )
    }

    private func generateViaProBackend(
        transcript: String,
        outputType: OutputType,
        language: AppLanguage,
        languageName: String?,
        length: SummaryLength,
        translating: Bool
    ) async throws -> SummaryGeneration {
        let data = try await proBackend.summarize(
            transcript: transcript,
            outputType: outputType,
            language: language,
            languageName: languageName,
            summaryLength: length
        )
        var output = try SummaryJSONParser.decode(data).normalized()
        output = sanitize(output, transcript: transcript, translating: translating)
        return .generated(makeStructuredOutput(from: output, outputType: outputType))
    }

    private func makeStructuredOutput(from output: StructuredOutputDTO, outputType: OutputType) -> StructuredOutput {
        StructuredOutput(
            outputType: outputType,
            title: output.title,
            shortSummary: output.shortSummary,
            detailedSummary: output.detailedSummary,
            keyIdeas: output.keyIdeas,
            decisions: output.decisions,
            actionItems: output.actionItems.map { ActionItem(text: $0.text, assignee: $0.assignee, dueDate: $0.dueDate) },
            openQuestions: output.openQuestions,
            risks: output.risks,
            nextSteps: output.nextSteps,
            peopleMentioned: output.peopleMentioned,
            datesMentioned: output.datesMentioned,
            importantNumbers: output.importantNumbers,
            followUpEmailDraft: output.followUpEmailDraft,
            generatedAt: .now
        )
    }

    private var systemPrompt: String {
        """
        You are a precise meeting and voice note analyst. Extract structured information ONLY from the provided transcript.
        RULES:
        - Never invent facts, names, dates, or numbers not present in the transcript.
        - Use "[not mentioned]" for missing fields when required.
        - Preserve the language of the transcript in your output.
        - Mark uncertain extractions with "(uncertain)".
        - Return valid JSON matching the requested schema.
        - Use camelCase keys exactly as requested.
        """
    }

    private func buildPrompt(transcript: String, outputType: OutputType, language: AppLanguage) -> String {
        let lengthInstruction = settings.summaryLength == .short
            ? "Keep summaries concise (2-3 sentences for short summary)."
            : "Provide a thorough detailed summary."
        let outputLanguageInstruction = languageOutputInstruction(for: language)
        let knownNames = settings.teammates.map(\.trimmedName).filter { !$0.isEmpty }
        let nameInstruction = knownNames.isEmpty
            ? ""
            : "Known people — when one of these is responsible, set assignee to the exact spelling: \(knownNames.joined(separator: ", "))."
        let clientInstruction = outputType == .clientCall
            ? "For this client call, shortSummary must say who called, what they asked, what was promised, and who will do it."
            : ""

        return """
        Output type: \(outputType.displayName)
        Required output language: \(language.displayName)
        \(outputLanguageInstruction)
        \(lengthInstruction)
        \(nameInstruction)
        \(clientInstruction)

        Transcript:
        \(transcript)

        Return JSON with keys:
        title, shortSummary, detailedSummary, keyIdeas (array), decisions (array),
        actionItems (array of {text, assignee, dueDate}), openQuestions (array),
        risks (array), nextSteps (array), peopleMentioned (array),
        datesMentioned (array), importantNumbers (array), followUpEmailDraft (string or null)
        """
    }

    private func languageOutputInstruction(for language: AppLanguage) -> String {
        switch language {
        case .autoDetect:
            return """
            MANDATORY: Write every generated natural-language value in the same language as the transcript.
            Preserve proper names and direct quotations unchanged.
            """
        case .luxembourgish:
            return """
            MANDATORY: Write every generated natural-language value exclusively in Lëtzebuergesch:
            title, shortSummary, detailedSummary, keyIdeas, decisions, actionItems, openQuestions,
            risks, nextSteps, and followUpEmailDraft. Do not write any explanatory content in English,
            French, German, or Portuguese. Preserve proper names and direct quotations unchanged.
            """
        default:
            return """
            MANDATORY: Write every generated natural-language value exclusively in \(language.displayName).
            Preserve proper names and direct quotations unchanged.
            """
        }
    }

    nonisolated static func keepsTranslatedFact(_ value: String, transcript: String, translating: Bool) -> Bool {
        translating || transcript.contains(value)
    }

    private func sanitize(_ output: StructuredOutputDTO, transcript: String, translating: Bool) -> StructuredOutputDTO {
        var sanitized = output
        let transcriptLower = transcript.lowercased()

        sanitized.peopleMentioned = output.peopleMentioned.filter {
            transcriptLower.contains($0.lowercased())
        }

        sanitized.datesMentioned = output.datesMentioned.filter {
            Self.keepsTranslatedFact($0, transcript: transcript, translating: translating)
        }

        sanitized.importantNumbers = output.importantNumbers.filter {
            Self.keepsTranslatedFact($0, transcript: transcript, translating: translating)
        }

        return sanitized
    }
}
