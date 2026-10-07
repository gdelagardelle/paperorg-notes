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
}
