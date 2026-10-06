import XCTest
@testable import SqueezeBar

final class DisplayNameTests: XCTestCase {
    func testEveryEnumCaseHasADisplayName() {
        XCTAssertTrue(UIScaleOption.allCases.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(AccentColorTheme.allCases.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(SoundEffectTheme.allCases.allSatisfy { !$0.displayName.isEmpty && !$0.shortName.isEmpty })
        XCTAssertTrue(PDFDPIOption.allCases.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(ImageFormatPolicy.allCases.allSatisfy { !$0.displayName.isEmpty && !$0.shortName.isEmpty && !$0.selectedName.isEmpty })
        XCTAssertTrue(AudioBitratePreference.allCases.allSatisfy { !$0.displayName.isEmpty && !$0.shortName.isEmpty })
        XCTAssertTrue(VideoCodecPreference.allCases.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(VideoFramerateOption.allCases.allSatisfy { !$0.displayName.isEmpty && !$0.shortName.isEmpty })
        XCTAssertTrue(GIFFramerateOption.allCases.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(QualityPreset.allCases.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(TargetSizeMode.allCases.allSatisfy { !$0.displayName.isEmpty })
    }

    /// Raw values are stored in UserDefaults, so translating the UI must never change them.
    func testPersistedRawValuesAreUnchanged() {
        XCTAssertEqual(TargetSizeMode.off.rawValue, "Manual Mode")
        XCTAssertEqual(QualityPreset.visuallyLossless.rawValue, "Visually Lossless")
        XCTAssertEqual(AudioBitratePreference.k128.rawValue, "128 kbps (Standard)")
        XCTAssertEqual(ImageFormatPolicy.preserveOriginal.rawValue, "Preserve Original")
    }
}
