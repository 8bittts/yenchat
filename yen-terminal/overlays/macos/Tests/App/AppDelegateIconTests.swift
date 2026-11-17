import AppKit
import Testing
@testable import YEN

@MainActor
struct AppDelegateIconTests {
    @Test func bundledAppIconLoadsKnownBuiltInAsset() {
        #expect(
            AppDelegate.bundledAppIcon(named: YEN.MacOSIcon.blueprint.assetName) != nil
        )
    }

    @Test func bundledAppIconReturnsNilForMissingAsset() {
        #expect(AppDelegate.bundledAppIcon(named: "__missing_yen_icon_asset__") == nil)
    }

    @Test func dictationIdleStatusImageIsATemplateSymbol() {
        let image = DictationController.makeIdleStatusImage()
        #expect(image != nil)
        #expect(image?.isTemplate == true)
    }
}
