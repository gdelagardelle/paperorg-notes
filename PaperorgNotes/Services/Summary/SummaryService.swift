import Foundation

@MainActor
final class SummaryService {
    private let settings: SettingsService
    private let keychain: KeychainService
    
    init(settings: SettingsService, keychain: KeychainService) {
        self.settings = settings
        self.keychain = keychain
    }
    
    func generate(
        transcript: String,
        outputType: OutputType,
        language: AppLanguage
    ) async throws -> StructuredOutput {
        if outputType == .rawTranscript {
            return StructuredOutput.empty(for: outputType)
        }
        
        guard let apiKey = settings.openAIAPIKey, !apiKey.isEmpty else {
            return fallbackSummary(transcript: transcript, outputType: outputType)
        }
        
        let prompt = buildPrompt(transcript: transcript, outputType: outputType, language: language)
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2
        ]
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return fallbackSummary(transcript: transcript, outputType: outputType)
        }
        
        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            return fallbackSummary(transcript: transcript, outputType: outputType)
        }
        
        var output = try JSONDecoder().decode(StructuredOutputDTO.self, from: jsonData)
        output = sanitize(output, transcript: transcript)
        
        return StructuredOutput(
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
        """
    }
    
    private func buildPrompt(transcript: String, outputType: OutputType, language: AppLanguage) -> String {
        let lengthInstruction = settings.summaryLength == .short
            ? "Keep summaries concise (2-3 sentences for short summary)."
            : "Provide a thorough detailed summary."
        
        return """
        Output type: \(outputType.displayName)
        Language: \(language.displayName)
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

private struct OpenAIChatResponse: Decodable {
    let choices: [OpenAIChoice]
}

private struct OpenAIChoice: Decodable {
    let message: OpenAIMessage
}

private struct OpenAIMessage: Decodable {
    let content: String
}

private struct StructuredOutputDTO: Decodable {
    var title: String?
    var shortSummary: String
    var detailedSummary: String
    var keyIdeas: [String]
    var decisions: [String]
    var actionItems: [ActionItemDTO]
    var openQuestions: [String]
    var risks: [String]
    var nextSteps: [String]
    var peopleMentioned: [String]
    var datesMentioned: [String]
    var importantNumbers: [String]
    var followUpEmailDraft: String?
}

private struct ActionItemDTO: Decodable {
    let text: String
    let assignee: String?
    let dueDate: String?
}
