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
        language: AppLanguage
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
            language: language
        )
    }

    private func generateViaProBackend(
        transcript: String,
        outputType: OutputType,
        language: AppLanguage
    ) async throws -> SummaryGeneration {
        let data = try await proBackend.summarize(
            transcript: transcript,
            outputType: outputType,
            language: language,
            summaryLength: settings.summaryLength
        )
        var output = try SummaryJSONParser.decode(data).normalized()
        output = sanitize(output, transcript: transcript)
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

        return """
        Output type: \(outputType.displayName)
        Required output language: \(language.displayName)
        \(outputLanguageInstruction)
        \(lengthInstruction)

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

    private func sanitize(_ output: StructuredOutputDTO, transcript: String) -> StructuredOutputDTO {
        var sanitized = output
        let transcriptLower = transcript.lowercased()

        sanitized.peopleMentioned = output.peopleMentioned.filter {
            transcriptLower.contains($0.lowercased())
        }

        sanitized.datesMentioned = output.datesMentioned.filter {
            transcript.contains($0)
        }

        sanitized.importantNumbers = output.importantNumbers.filter {
            transcript.contains($0)
        }

        return sanitized
    }

    private func fallbackSummary(transcript: String, outputType: OutputType) -> StructuredOutput {
        let sentences = transcript.components(separatedBy: ". ").prefix(3)
        let short = sentences.joined(separator: ". ")

        return StructuredOutput(
            outputType: outputType,
            title: String(transcript.prefix(60)),
            shortSummary: short,
            detailedSummary: transcript,
            keyIdeas: [],
            decisions: [],
            actionItems: [],
            openQuestions: [],
            risks: [],
            nextSteps: [],
            peopleMentioned: [],
            datesMentioned: [],
            importantNumbers: [],
            followUpEmailDraft: nil,
            generatedAt: .now
        )
    }
}
