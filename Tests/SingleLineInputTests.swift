import Testing

@testable import Skywave

/// Einzeilige Felder im Verfassen-Fenster: eingefügter Text darf weder
/// Zeilenumbrüche noch angehängten Leerraum behalten.
struct SingleLineInputTests {
    @Test func plainTextIsUntouched() {
        #expect(SingleLineInput.clean("Skywave 0.8.0 zum Testen") == "Skywave 0.8.0 zum Testen")
        #expect(SingleLineInput.clean("") == "")
    }

    @Test func leadingLineBreakIsRemoved() {
        #expect(SingleLineInput.clean("\nSkywave 0.8.0 zum Testen") == "Skywave 0.8.0 zum Testen")
        #expect(SingleLineInput.clean("\r\n  Betreff") == "Betreff")
    }

    @Test func trailingLineBreakIsRemoved() {
        #expect(SingleLineInput.clean("Betreff\n") == "Betreff")
    }

    @Test func innerLineBreaksBecomeOneSpace() {
        #expect(SingleLineInput.clean("Zeile eins\n\n  Zeile zwei") == "Zeile eins Zeile zwei")
    }

    /// Beim Tippen muss sich nach einem Wort ein Leerzeichen setzen lassen.
    @Test func typedTrailingSpaceSurvives() {
        #expect(SingleLineInput.clean("Hallo ") == "Hallo ")
        #expect(SingleLineInput.clean("HB9XYZ, ") == "HB9XYZ, ")
    }

    /// Der beobachtete Fall: eine Zeile aus dem Terminal, mit Leerzeichen
    /// bis zum Fensterrand aufgefüllt. Das Feld sah danach leer aus.
    @Test func paddingFromTheTerminalShrinksToOneSpace() {
        let padded = "Skywave 0.8.0 zum Testen" + String(repeating: " ", count: 400)
        #expect(SingleLineInput.clean(padded) == "Skywave 0.8.0 zum Testen ")
        #expect(SingleLineInput.clean("Betreff\t\t") == "Betreff ")
    }

    @Test func onlyWhitespaceBecomesEmpty() {
        #expect(SingleLineInput.clean("     ") == "")
    }

    @Test func innerSpacesAreKept() {
        #expect(SingleLineInput.clean("zwei  Leerzeichen") == "zwei  Leerzeichen")
    }

    @Test func onlyLineBreaksBecomeEmpty() {
        #expect(SingleLineInput.clean("\n\n") == "")
    }
}
