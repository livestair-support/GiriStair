import XCTest

/// Exercise real SwiftUI tab and segmented-control transitions without taking
/// screenshots. A main-thread hang/crash prevents the next control from being
/// hittable and fails this regression instead of passing a compile-only check.
final class TabNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSharingPreviewSettingsAndReturnToListRemainResponsive() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-tab-navigation"]
        app.launch()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))
        for mode in [("Giri Summary", "sharing.summary.preview"), ("Giri List", "sharing.list.preview")] {
            tabBar.buttons["設定"].tap()
            let link = app.buttons[mode.0]
            XCTAssertTrue(link.waitForExistence(timeout: 5))
            link.tap()
            let preview = app.descendants(matching: .any).matching(identifier: mode.1).firstMatch
            XCTAssertTrue(preview.waitForExistence(timeout: 15))
            let palette = app.buttons["sharing.settings"]
            XCTAssertTrue(palette.waitForExistence(timeout: 5))
            palette.tap()
            XCTAssertEqual(app.state, .runningForeground)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            tabBar.buttons["一覧"].tap()
            XCTAssertTrue(app.segmentedControls["format-tabs"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual(app.state, .runningForeground)
        }
    }

    func testTopFormatSwitchesWithOnlyOneLiveRecordAndOneSite() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-tab-navigation", "--uitest-minimal-navigation"]
        app.launch()
        let list = app.tabBars.buttons["一覧"]
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        list.tap()
        let formats = app.segmentedControls["format-tabs"].firstMatch
        XCTAssertTrue(formats.waitForExistence(timeout: 5))
        // Switching into empty categories removes all event rows. This differs
        // from the populated-format test and matches the user's stored data.
        for _ in 0..<3 {
            for labels in [("ネット大喜利（長考）", "長考"), ("ネット大喜利（短考）", "短考"), ("スプシ系", "スプシ系"), ("生大喜利", "生")] {
                let button = formats.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", labels.0, labels.1)).firstMatch
                XCTAssertTrue(button.waitForExistence(timeout: 5))
                XCTAssertTrue(button.isHittable)
                button.tap()
                XCTAssertTrue(button.isSelected)
                XCTAssertEqual(app.state, .runningForeground)
            }
        }
    }

    func testListCanSwitchFormatsAndVisitEveryTabRepeatedly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-tab-navigation"]
        app.launch()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))
        let list = tabBar.buttons["一覧"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            list.tap()
            let formats = app.segmentedControls["format-tabs"].firstMatch
            XCTAssertTrue(formats.waitForExistence(timeout: 5))
            for labels in [("生大喜利", "生"), ("ネット大喜利（長考）", "長考"), ("ネット大喜利（短考）", "短考"), ("スプシ系", "スプシ系")] {
                let button = formats.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", labels.0, labels.1)).firstMatch
                XCTAssertTrue(button.waitForExistence(timeout: 5))
                XCTAssertTrue(button.isHittable)
                button.tap()
                XCTAssertTrue(button.isSelected)
                XCTAssertEqual(app.state, .runningForeground)
            }
            for title in ["登録", "戦績", "お題/回答", "設定"] {
                list.tap()
                let destination = tabBar.buttons[title]
                XCTAssertTrue(destination.waitForExistence(timeout: 5))
                XCTAssertTrue(destination.isHittable)
                destination.tap()
                XCTAssertEqual(app.state, .runningForeground)
                XCTAssertTrue(list.isHittable)
            }
        }
    }
}
