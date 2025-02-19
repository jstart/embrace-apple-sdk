//
//  Copyright © 2023 Embrace Mobile, Inc. All rights reserved.
//

import XCTest
import TestSupport
@testable import EmbraceUploadInternal

extension EmbraceUploadCacheTests {
    func test_clearStaleDataIfNeeded_basedOn_size() throws {
        let testOptions = EmbraceUpload.CacheOptions(cacheBaseUrl: URL(fileURLWithPath: NSTemporaryDirectory()))!
        // setting the maximum db size of 1000 bytes
        testOptions.cacheDaysLimit = 0
        testOptions.cacheSizeLimit = 1000
        let cache = try EmbraceUploadCache(options: testOptions)

        // given some upload cache
        let now = Date()
        let record1 = UploadDataRecord(
            id: "id1",
            type: 0,
            data: Data(repeating: 3, count: 300),
            attemptCount: 0,
            date: Date(timeInterval: -1000, since: now)
        )
        let record2 = UploadDataRecord(
            id: "id2",
            type: 0,
            data: Data(repeating: 3, count: 400),
            attemptCount: 0,
            date: Date(timeInterval: -1100, since: now)
        )
        let record3 = UploadDataRecord(
            id: "id3",
            type: 0,
            data: Data(repeating: 3, count: 500),
            attemptCount: 0,
            date: Date(timeInterval: -1200, since: now)
        )
        let record4 = UploadDataRecord(
            id: "id4",
            type: 0,
            data: Data(repeating: 3, count: 600),
            attemptCount: 0,
            date: Date(timeInterval: -1300, since: now)
        )

        // adding the data "out of order" to make sure the correct ones are selected by date, deleting the older ones first
        try cache.dbQueue.write { db in
            try record2.insert(db)
            try record4.insert(db)
            try record3.insert(db)
            try record1.insert(db)
        }

        // when attempting to remove data over the specified amount
        let removedRecords = try cache.clearStaleDataIfNeeded()

        let records = try cache.fetchAllUploadData()

        // the expected data should've been removed.
        XCTAssertEqual(removedRecords, 2)
        XCTAssert(records.contains(record1))
        XCTAssert(records.contains(record2))
        XCTAssert(!records.contains(record3))
        XCTAssert(!records.contains(record4))
    }

    func test_clearStaleDataIfNeeded_basedOn_size_noLimit() throws {
        let testOptions = EmbraceUpload.CacheOptions(cacheBaseUrl: URL(fileURLWithPath: NSTemporaryDirectory()))!
        // disabling cache size limit
        testOptions.cacheSizeLimit = 0
        testOptions.cacheDaysLimit = 0
        let cache = try EmbraceUploadCache(options: testOptions)

        // given some upload cache
        let now = Date()
        let record1 = UploadDataRecord(
            id: "id1",
            type: 0,
            data: Data(repeating: 3, count: 300),
            attemptCount: 0,
            date: Date(timeInterval: -1000, since: now)
        )
        let record2 = UploadDataRecord(
            id: "id2",
            type: 0,
            data: Data(repeating: 3, count: 400),
            attemptCount: 0,
            date: Date(timeInterval: -1100, since: now)
        )
        let record3 = UploadDataRecord(
            id: "id3",
            type: 0,
            data: Data(repeating: 3, count: 500),
            attemptCount: 0,
            date: Date(timeInterval: -1200, since: now)
        )
        let record4 = UploadDataRecord(
            id: "id4",
            type: 0,
            data: Data(repeating: 3, count: 600),
            attemptCount: 0,
            date: Date(timeInterval: -1300, since: now)
        )

        try cache.dbQueue.write { db in
            try record2.insert(db)
            try record4.insert(db)
            try record3.insert(db)
            try record1.insert(db)
        }

        // when attempting to remove data
        let removedRecords = try cache.clearStaleDataIfNeeded()

        let records = try cache.fetchAllUploadData()

        // no records should've been removed.
        XCTAssertEqual(removedRecords, 0)
        XCTAssert(records.contains(record1))
        XCTAssert(records.contains(record2))
        XCTAssert(records.contains(record3))
        XCTAssert(records.contains(record4))
    }

    func test_clearStaleDataIfNeeded_basedOn_size_noRecords() throws {
        let testOptions = EmbraceUpload.CacheOptions(cacheBaseUrl: URL(fileURLWithPath: NSTemporaryDirectory()))!
        // setting the maximum db size of 1 byte
        testOptions.cacheSizeLimit = 1
        testOptions.cacheDaysLimit = 0
        let cache = try EmbraceUploadCache(options: testOptions)

        // when attempting to remove data from an empty cache
        let removedRecords = try cache.clearStaleDataIfNeeded()

        // no data should've attempt to be removed.
        XCTAssertEqual(removedRecords, 0)
    }

    func test_clearStaleDataIfNeeded_basedOn_size_didNotHitLimit() throws {
        let testOptions = EmbraceUpload.CacheOptions(cacheBaseUrl: URL(fileURLWithPath: NSTemporaryDirectory()))!
        // setting enough cache limit
        testOptions.cacheSizeLimit = 1801
        testOptions.cacheDaysLimit = 0
        let cache = try EmbraceUploadCache(options: testOptions)

        // given some upload cache
        let now = Date()
        let record1 = UploadDataRecord(
            id: "id1",
            type: 0,
            data: Data(repeating: 3, count: 300),
            attemptCount: 0,
            date: Date(timeInterval: -1000, since: now)
        )
        let record2 = UploadDataRecord(
            id: "id2",
            type: 0,
            data: Data(repeating: 3, count: 400),
            attemptCount: 0,
            date: Date(timeInterval: -1100, since: now)
        )
        let record3 = UploadDataRecord(
            id: "id3",
            type: 0,
            data: Data(repeating: 3, count: 500),
            attemptCount: 0,
            date: Date(timeInterval: -1200, since: now)
        )
        let record4 = UploadDataRecord(
            id: "id4",
            type: 0,
            data: Data(repeating: 3, count: 600),
            attemptCount: 0,
            date: Date(timeInterval: -1300, since: now)
        )

        try cache.dbQueue.write { db in
            try record2.insert(db)
            try record4.insert(db)
            try record3.insert(db)
            try record1.insert(db)
        }

        // when attempting to remove data
        let removedRecords = try cache.clearStaleDataIfNeeded()

        let records = try cache.fetchAllUploadData()

        // no records should've been removed.
        XCTAssertEqual(removedRecords, 0)
        XCTAssert(records.contains(record1))
        XCTAssert(records.contains(record2))
        XCTAssert(records.contains(record3))
        XCTAssert(records.contains(record4))
    }
}
