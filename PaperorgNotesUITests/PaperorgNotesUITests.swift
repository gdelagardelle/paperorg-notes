import XCTest

final class PaperorgNotesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSupportedLanguagesReachUsableEntryScreen() {
        let locales = [
            (language: "en", locale: "en_US", privacy: "Your Privacy Matters", record: "Record"),
            (language: "de", locale: "de_DE", privacy: "Ihre Privatsphäre ist wichtig", record: "Aufnahme"),
            (language: "fr", locale: "fr_FR", privacy: "Votre vie privée compte", record: "Enregistrer"),
            (language: "lb", locale: "lb_LU", privacy: "Är Privatsphär ass wichteg", record: "Rekord"),
            (language: "pt", locale: "pt_PT", privacy: "A sua privacidade é importante", record: "Gravar"),
        ]

        for entry in locales {
            let app = XCUIApplication()
            app.launchArguments += [
                "-AppleLanguages", "(\(entry.language))",
                "-AppleLocale", entry.locale,
            ]
            app.launch()

            let recordTab = app.tabBars.buttons[entry.record]
            let privacyTitle = app.staticTexts[entry.privacy]
            let reachedRecordScreen = recordTab.waitForExistence(timeout: 5)

            XCTAssertTrue(
                reachedRecordScreen || privacyTitle.waitForExistence(timeout: 5),
                "Expected a usable \(entry.language) entry screen after launch."
            )

            app.terminate()
        }
    }
}
