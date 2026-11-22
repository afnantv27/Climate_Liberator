//
//  ClimateLiberatorUITests.swift
//  ClimateLiberatorUITests
//
//  Created by Afnan on 2026-03-27.
//

import XCTest

final class ClimateLiberatorUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testHomeShowsModules() throws {
        let app = configuredApp()
        app.launch()

        let home = app.radioButtons["Home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        XCTAssertEqual((home.value as? NSNumber)?.intValue, 1)
        XCTAssertTrue(app.buttons["Open Climate Simulation"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Open Forecast Intelligence"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Open Disclosure"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Open Clients"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Open Reduce"].firstMatch.exists)
    }

    @MainActor
    func testForecastWindowOpensFromHome() throws {
        let app = configuredApp()
        app.launch()

        let forecastButton = app.buttons["Open Forecast Intelligence"].firstMatch
        XCTAssertTrue(forecastButton.waitForExistence(timeout: 5))
        forecastButton.click()

        XCTAssertTrue(app.staticTexts["Forecast Intelligence"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Location Search"].firstMatch.exists)
    }

    @MainActor
    func testClimateSimulationOpensFromHome() throws {
        let app = configuredApp()
        app.launch()

        let simulationButton = app.buttons["Open Climate Simulation"].firstMatch
        XCTAssertTrue(simulationButton.waitForExistence(timeout: 5))
        for _ in 0..<4 where !simulationButton.isHittable {
            app.scrollViews["home.scroll"].firstMatch.scroll(byDeltaX: 0, deltaY: -250)
        }
        XCTAssertTrue(simulationButton.isHittable)
        simulationButton.click()

        XCTAssertTrue(waitForAnyElement(in: app, identifiers: [
            "Simulation Workspace",
            "Hide Panel",
            "Show Panel"
        ], timeout: 5))
    }

    @MainActor
    func testDisclosureOpensFromHome() throws {
        let app = configuredApp()
        app.launch()

        let disclosureButton = app.buttons["Open Disclosure"].firstMatch
        XCTAssertTrue(disclosureButton.waitForExistence(timeout: 5))
        disclosureButton.click()

        XCTAssertTrue(waitForAnyElement(in: app, identifiers: [
            "BRSR, BRSR Core and IFRS S2 reporting for client companies.",
            "New Client"
        ], timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            configuredApp().launch()
        }
    }

    @MainActor
    private func waitForAnyElement(in app: XCUIApplication,
                                   identifiers: [String],
                                   timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for identifier in identifiers {
                if app.staticTexts[identifier].firstMatch.exists || app.buttons[identifier].firstMatch.exists {
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func configuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        return app
    }
}
