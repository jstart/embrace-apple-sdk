//
//  Copyright © 2023 Embrace Mobile, Inc. All rights reserved.
//

import XCTest

import EmbraceOTel
import EmbraceStorage
import GRDB

import TestSupport

final class SpanStorageIntegrationTests: XCTestCase {

    var storage: EmbraceStorage!

    override func setUpWithError() throws {
        let storageOptions = EmbraceStorage.Options(named: String(describing: self))
        storage = try EmbraceStorage(options: storageOptions)

        EmbraceOTel.setup(storage: storage)
    }

    override func tearDownWithError() throws {
        _ = try storage.dbQueue.inDatabase { db in
            try SpanRecord.deleteAll(db)
        }
    }

    func test_addSpan_storesSpan() throws {
        let exp = expectation(description: "Observe Insert")
        let observation = ValueObservation.tracking(SpanRecord.fetchAll)
        let cancellable = observation.start(in: storage.dbQueue) { error in
            fatalError("Error: \(error)")
        } onChange: { records in
            if records.count > 0 {
                exp.fulfill()
            }
        }

        let otel = EmbraceOTel()
        _ = otel.addSpan(name: "example", type: .session) {  5 * 5 }
        wait(for: [exp], timeout: 1.0)

        let records: [SpanRecord] = try storage.fetchAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.type, .session)
        cancellable.cancel()
    }

    func test_buildSpan_storesOpenSpan() throws {
        let exp = expectation(description: "Observe Insert")
        let observation = ValueObservation.tracking(SpanRecord.fetchAll)
        let cancellable = observation.start(in: storage.dbQueue) { error in
            fatalError("Error: \(error)")
        } onChange: { records in
            if records.count > 0 {
                exp.fulfill()
            }
        }

        let otel = EmbraceOTel()
        _ = otel.buildSpan(name: "example", type: .performance)
            .setAttribute(key: "foo", value: "bar")
            .startSpan()
        wait(for: [exp], timeout: 1.0)

        let records: [SpanRecord] = try storage.fetchAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.type, .performance)
        if let openSpan = records.first {
            XCTAssertNil(openSpan.endTime)
        }

        cancellable.cancel()
    }

    func test_buildSpan_storesSpanThatEnded() throws {
        let exp = expectation(description: "Observe Insert")
        let observation = ValueObservation.tracking { db in
            try SpanRecord
                .filter(Column("end_time") != nil)
                .fetchAll(db)
        }
        let cancellable = observation.start(in: storage.dbQueue) { error in
            fatalError("Error: \(error)")
        } onChange: { records in
            if records.count > 0 {
                exp.fulfill()
            }
        }

        let otel = EmbraceOTel()
        let span = otel.buildSpan(name: "example", type: .performance)
            .setAttribute(key: "foo", value: "bar")
            .startSpan()

        span.end()
        wait(for: [exp], timeout: 1.0)

        let records: [SpanRecord] = try storage.fetchAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.type, .performance)
        if let openSpan = records.first {
            XCTAssertNotNil(openSpan.endTime)
        }

        cancellable.cancel()
    }
}
