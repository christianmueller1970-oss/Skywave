import Testing

@testable import Skywave

/// Einzeilige Felder im Verfassen-Fenster: eingefügter Text darf keinen
/// Zeilenumbruch behalten (das Feld zeigte sonst eine leere erste Zeile).
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

    @Test func onlyLineBreaksBecomeEmpty() {
        #expect(SingleLineInput.clean("\n\n") == "")
    }
}
