import Quick
import Nimble
import Foundation
@testable import Clipy

class MenuSettingsSpec: QuickSpec {
    override class func spec() {
        describe("MenuSettings") {

            // MenuSettings reads from AppEnvironment.current.defaults at init.
            // Set the keys directly there, then construct, then assert.
            let defaults = AppEnvironment.current.defaults

            // Snapshot keys the spec touches so an after-each can restore.
            let touchedKeys: [String] = [
                Constants.UserDefaults.menuItemsAreMarkedWithNumbers,
                Constants.UserDefaults.showToolTipOnMenuItem,
                Constants.UserDefaults.showImageInTheMenu,
                Constants.UserDefaults.showColorPreviewInTheMenu,
                Constants.UserDefaults.addNumericKeyEquivalents,
                Constants.UserDefaults.menuItemsTitleStartWithZero,
                Constants.UserDefaults.showIconInTheMenu,
                Constants.UserDefaults.maxLengthOfToolTip,
                Constants.UserDefaults.maxMenuItemTitleLength,
                Constants.UserDefaults.numberOfItemsPlaceInline,
                Constants.UserDefaults.numberOfItemsPlaceInsideFolder,
                Constants.UserDefaults.maxHistorySize,
                Constants.UserDefaults.reorderClipsAfterPasting,
                Constants.UserDefaults.addClearHistoryMenuItem,
                Constants.UserDefaults.thumbnailWidth,
                Constants.UserDefaults.thumbnailHeight
            ]

            var savedValues: [String: Any?] = [:]

            beforeEach {
                savedValues = Dictionary(uniqueKeysWithValues:
                    touchedKeys.map { ($0, defaults.object(forKey: $0)) })
            }

            afterEach {
                for (key, value) in savedValues {
                    if let value = value {
                        defaults.set(value, forKey: key)
                    } else {
                        defaults.removeObject(forKey: key)
                    }
                }
            }

            it("reflects each toggled defaults key in the corresponding field") {
                defaults.set(true,  forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
                defaults.set(false, forKey: Constants.UserDefaults.showToolTipOnMenuItem)
                defaults.set(true,  forKey: Constants.UserDefaults.showImageInTheMenu)
                defaults.set(false, forKey: Constants.UserDefaults.showColorPreviewInTheMenu)
                defaults.set(true,  forKey: Constants.UserDefaults.addNumericKeyEquivalents)
                defaults.set(true,  forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
                defaults.set(false, forKey: Constants.UserDefaults.showIconInTheMenu)
                defaults.set(true,  forKey: Constants.UserDefaults.reorderClipsAfterPasting)
                defaults.set(false, forKey: Constants.UserDefaults.addClearHistoryMenuItem)

                let settings = MenuSettings()
                expect(settings.isMarkWithNumber) == true
                expect(settings.isShowToolTip) == false
                expect(settings.isShowImage) == true
                expect(settings.isShowColorCode) == false
                expect(settings.addNumericKeyEquivalents) == true
                expect(settings.isStartFromZero) == true
                expect(settings.isShowIcon) == false
                expect(settings.reorderClipsAfterPasting) == true
                expect(settings.addClearHistoryMenuItem) == false
            }

            it("reads integer settings (lengths / counts / thumbnail size)") {
                defaults.set(42,  forKey: Constants.UserDefaults.maxLengthOfToolTip)
                defaults.set(60,  forKey: Constants.UserDefaults.maxMenuItemTitleLength)
                defaults.set(15,  forKey: Constants.UserDefaults.numberOfItemsPlaceInline)
                defaults.set(8,   forKey: Constants.UserDefaults.numberOfItemsPlaceInsideFolder)
                defaults.set(99,  forKey: Constants.UserDefaults.maxHistorySize)
                defaults.set(300, forKey: Constants.UserDefaults.thumbnailWidth)
                defaults.set(200, forKey: Constants.UserDefaults.thumbnailHeight)

                let settings = MenuSettings()
                expect(settings.maxLengthOfToolTip) == 42
                expect(settings.maxMenuItemTitleLength) == 60
                expect(settings.placeInLine) == 15
                expect(settings.placeInsideFolder) == 8
                expect(settings.maxHistory) == 99
                expect(settings.thumbnailWidth) == 300
                expect(settings.thumbnailHeight) == 200
            }

            // No "unset → 0/false" coverage: the host registers defaults via
            // CPYUtilities.registerUserDefaultKeys, so removeObject falls back
            // to a registered value (e.g. thumbnailWidth=576, isShowImage=true)
            // rather than zero. That registration is what we want in the app
            // anyway; testing it here would just couple to those constants.
        }
    }
}
