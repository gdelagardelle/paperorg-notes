import XCTest
@testable import PaperorgNotes

final class OfficeSpokenFieldsTests: XCTestCase {
    func testSinistreAndWaitingOnTheClient() {
        let result = OfficeSpokenFields.classify("Sinistre auto. En attente du client pour les photos.")
        XCTAssertEqual(result.departement, "Sinistre")
        XCTAssertEqual(result.statut, "attente_client")
        XCTAssertNil(result.fileLabel)
    }

    func testRabaisBecomesCommercialAndKeepsTheWord() {
        let result = OfficeSpokenFields.classify("Demander un rabais sur le contrat auto.")
        XCTAssertEqual(result.departement, "Commercial")
        XCTAssertEqual(result.fileLabel, "Rabais")
        XCTAssertEqual(result.statut, "a_faire")
    }

    func testResiliationAndWaitingOnTheCompany() {
        let result = OfficeSpokenFields.classify("Résiliation. Waarde op de Siège fir d'confirmation.")
        XCTAssertEqual(result.departement, "Contrat")
        XCTAssertEqual(result.statut, "attente_siege")
        XCTAssertEqual(result.fileLabel, "Résiliation")
    }

    func testClientWordAloneDoesNotMeanWaiting() {
        let result = OfficeSpokenFields.classify("Appeler le client Schmit pour le contrat.")
        XCTAssertEqual(result.departement, "Contrat")
        XCTAssertEqual(result.statut, "a_faire")
    }

    func testSpokenSentenceBecomesATaskForThatPerson() {
        let tasks = OfficeWorkflow.tasksSpoken(
            in: "Dany war um Call. Demander à Dany de relancer le siège demain.",
            roster: Teammate.starterOffice
        )
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.assignee, "Dany")
        XCTAssertEqual(tasks.first?.text, "Demander à Dany de relancer le siège demain")
    }

    func testANameWithoutARequestIsNotATask() {
        let tasks = OfficeWorkflow.tasksSpoken(
            in: "Dany war um Call.",
            roster: Teammate.starterOffice
        )
        XCTAssertTrue(tasks.isEmpty)
    }

    func testClientNameStaysTheSpokenProject() {
        XCTAssertEqual(
            OfficeSpokenFields.clientName(project: "Schmit", people: ["Dany"], assignee: "Dany"),
            "Schmit"
        )
        XCTAssertEqual(
            OfficeSpokenFields.clientName(project: nil, people: ["Dany", "Schmit"], assignee: "Dany"),
            "Schmit"
        )
    }

    func testWriteLanguageAsksForATranslationWhenItDiffers() {
        let french = SummaryWriteLanguage.requestLanguageName(output: .french, spoken: .luxembourgish)
        XCTAssertTrue(french.contains("Français"))
        XCTAssertTrue(french.contains("Lëtzebuergesch"))
        XCTAssertTrue(french.contains("Translate"))

        let same = SummaryWriteLanguage.requestLanguageName(output: .german, spoken: .german)
        XCTAssertEqual(same, "Deutsch")
    }

    func testTranslatedDatesAndNumbersStayWhenTheNoteChangesLanguage() {
        let transcript = "De Client rufft de 15. Oktober un. De Montant ass 1200 Euro."
        XCTAssertTrue(SummaryService.keepsTranslatedFact("15 octobre", transcript: transcript, translating: true))
        XCTAssertTrue(SummaryService.keepsTranslatedFact("1 200 €", transcript: transcript, translating: true))
        XCTAssertFalse(SummaryService.keepsTranslatedFact("15 octobre", transcript: transcript, translating: false))
        XCTAssertTrue(SummaryService.keepsTranslatedFact("1200", transcript: transcript, translating: false))
    }
}
