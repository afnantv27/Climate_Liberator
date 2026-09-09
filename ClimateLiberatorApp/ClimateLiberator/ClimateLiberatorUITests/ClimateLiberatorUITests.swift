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
    func testDashboardShowsPrimaryWorkflows() throws {
        let app = configuredApp()
        app.launch()

        let dashboard = app.radioButtons["Dashboard"].firstMatch
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
        XCTAssertEqual((dashboard.value as? NSNumber)?.intValue, 1)
        XCTAssertTrue(app.buttons["Open Climate Simulation"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Open Forecast Intelligence"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Open Disclosure Review"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Enterprise Readiness"].exists)
    }

    @MainActor
    func testForecastWindowOpensFromDashboard() throws {
        let app = configuredApp()
        app.launch()

        let forecastButton = app.buttons["Open Forecast Intelligence"].firstMatch
        XCTAssertTrue(forecastButton.waitForExistence(timeout: 5))
        forecastButton.click()

        XCTAssertTrue(app.staticTexts["Forecast Intelligence"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Location Search"].firstMatch.exists)
    }

    @MainActor
    func testClimateSimulationOpensFromDashboard() throws {
        let app = configuredApp()
        app.launch()

        let simulationButton = app.buttons["Open Climate Simulation"].firstMatch
        XCTAssertTrue(simulationButton.waitForExistence(timeout: 5))
        for _ in 0..<4 where !simulationButton.isHittable {
            app.scrollViews["dashboard.scroll"].firstMatch.scroll(byDeltaX: 0, deltaY: -250)
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
    func testTCFDDashboardOpensFromDashboard() throws {
        let app = configuredApp()
        app.launch()

        let tcfdButton = app.buttons["Open Disclosure Review"].firstMatch
        XCTAssertTrue(tcfdButton.waitForExistence(timeout: 5))
        tcfdButton.click()

        XCTAssertTrue(waitForAnyElement(in: app, identifiers: [
            "TCFD Dashboard",
            "Board Disclosure Workspace",
            "TCFD Wildfire Dashboard"
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
