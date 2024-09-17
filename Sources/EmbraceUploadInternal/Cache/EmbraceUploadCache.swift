//
//  Copyright © 2024 Embrace Mobile, Inc. All rights reserved.
//

import Foundation
import EmbraceOTelInternal
import EmbraceCommonInternal
import GRDB

/// Class that handles all the cached upload data generated by the Embrace SDK.
class EmbraceUploadCache {

    private(set) var options: EmbraceUpload.CacheOptions
    private(set) var dbQueue: DatabaseQueue
    let logger: InternalLogger

    init(options: EmbraceUpload.CacheOptions, logger: InternalLogger) throws {
        self.options = options
        self.logger = logger

        // create sqlite file
        dbQueue = try Self.createDBQueue(options: options, logger: logger)

        // define tables
        try dbQueue.write { db in
            try UploadDataRecord.defineTable(db: db)
        }

        try clearStaleDataIfNeeded()
    }

    /// Fetches the cached upload data for the given identifier.
    /// - Parameters:
    ///   - id: Identifier of the data
    ///   - type: Type of the data
    /// - Returns: The cached `UploadDataRecord`, if any
    public func fetchUploadData(id: String, type: EmbraceUploadType) throws -> UploadDataRecord? {
        try dbQueue.read { db in
            return try UploadDataRecord.fetchOne(db, key: ["id": id, "type": type.rawValue])
        }
    }

    /// Fetches all the cached upload data.
    /// - Returns: An array containing all the cached `UploadDataRecords`
    public func fetchAllUploadData() throws -> [UploadDataRecord] {
        try dbQueue.read { db in
            return try UploadDataRecord
                .order(Column("date").asc)
                .fetchAll(db)
        }
    }

    /// Removes stale data based on size or date, if they're limited in options.
    @discardableResult public func clearStaleDataIfNeeded() throws -> UInt {
        let limitDays = options.cacheDaysLimit
        let limitSize = options.cacheSizeLimit
        let recordsBasedOnDate = limitDays > 0 ? try fetchRecordsToDeleteBasedOnDate(maxDays: limitDays) : []
        let recordsBasedOnSize = limitSize > 0 ? try fetchRecordsToDeleteBasedOnSize(maxSize: limitSize) : []

        let recordsToDelete = Array(Set(recordsBasedOnDate + recordsBasedOnSize))

        let deleteCount = recordsToDelete.count

        if deleteCount > 0 {
            let span = EmbraceOTel().buildSpan(
                name: "emb-upload-cache-vacuum",
                type: .performance,
                attributes: ["removed": "\(deleteCount)"])
                .markAsPrivate()
            span.setStartTime(time: Date())
            let startedSpan = span.startSpan()
            try deleteRecords(recordIDs: recordsToDelete)
            try dbQueue.vacuum()
            startedSpan.end()

            return UInt(deleteCount)
        }

        return 0
    }

    /// Saves the given upload data to the cache.
    /// - Parameters:
    ///   - id: Identifier of the data
    ///   - type: Type of the data
    ///   - data: Data to cache
    /// - Returns: The newly cached `UploadDataRecord`
    @discardableResult func saveUploadData(id: String, type: EmbraceUploadType, data: Data) throws -> UploadDataRecord {
        let record = UploadDataRecord(id: id, type: type.rawValue, data: data, attemptCount: 0, date: Date())
        try saveUploadData(record)

        return record
    }

    /// Saves the given `UploadDataRecord` to the cache.
    /// - Parameter record: `UploadDataRecord` instance to save
    func saveUploadData(_ record: UploadDataRecord) throws {
        try dbQueue.write { [weak self] db in

            // update if its already stored
            if try record.exists(db) {
                try record.update(db)
                return
            }

            // check limit and delete if necessary
            if let limit = self?.options.cacheLimit, limit > 0 {
                let count = try UploadDataRecord.fetchCount(db)

                if count >= limit {
                    let recordsToDelete = try UploadDataRecord
                        .order(Column("date").asc)
                        .limit(Int(limit))
                        .fetchAll(db)

                    for recordToDelete in recordsToDelete {
                        try recordToDelete.delete(db)
                    }
                }
            }

            try record.insert(db)
        }
    }

    /// Deletes the cached data for the given identifier.
    /// - Parameters:
    ///   - id: Identifier of the data
    ///   - type: Type of the data
    /// - Returns: Boolean indicating if the data was successfully deleted
    @discardableResult func deleteUploadData(id: String, type: EmbraceUploadType) throws -> Bool {
        guard let uploadData = try fetchUploadData(id: id, type: type) else {
            return false
        }

        return try deleteUploadData(uploadData)
    }

    /// Deletes the cached `UploadDataRecord`.
    /// - Parameter uploadData: `UploadDataRecord` to delete
    /// - Returns: Boolean indicating if the data was successfully deleted
    func deleteUploadData(_ uploadData: UploadDataRecord) throws -> Bool {
        try dbQueue.write { db in
            return try uploadData.delete(db)
        }
    }

    /// Updates the attempt count of the upload data for the given identifier.
    /// - Parameters:
    ///   - id: Identifier of the data
    ///   - type: Type of the data
    ///   - attemptCount: New attempt count
    /// - Returns: Returns the updated `UploadDataRecord`, if any
    func updateAttemptCount(
        id: String,
        type: EmbraceUploadType,
        attemptCount: Int
    ) throws {
        try dbQueue.write { db in
            let filter = UploadDataRecord.Schema.id == id && UploadDataRecord.Schema.type == type
            try UploadDataRecord.filter(filter)
                .updateAll(db, UploadDataRecord.Schema.attemptCount.set(to: attemptCount))
        }
    }

    /// Sorts Upload Cache by descending order and goes through it adding the space taken by each record.
    /// Once the __maxSize__ has been reached, all the following record IDs will be returned indicating those need to be deleted.
    /// - Parameter maxSize: The maximum allowed size in bytes for the Database.
    /// - Returns: An array of IDs of the oldest records which are making the DB go above the target maximum size.
    func fetchRecordsToDeleteBasedOnSize(maxSize: UInt) throws -> [String] {
        let sqlQuery = """
        WITH t AS (SELECT id, date, SUM(LENGTH(data)) OVER (ORDER BY date DESC,id) total_size FROM uploads)
        SELECT id FROM t WHERE total_size>=\(maxSize) ORDER BY date DESC;
        """

        var result: [String] = []

        try dbQueue.read { db in
            result = try String.fetchAll(db, sql: sqlQuery)
        }

        return result
    }

    /// Fetches all records that should be deleted based on them being older than __maxDays__ days
    /// - Parameter db: The database where to pull the data from, assumes the records to be UploadDataRecord.
    /// - Parameter maxDays: The maximum allowed days old a record is allowed to be cached.
    /// - Returns: An array of IDs from records that should be deleted.
    func fetchRecordsToDeleteBasedOnDate(maxDays: UInt) throws -> [String] {
        let sqlQuery = """
        SELECT id, date FROM uploads WHERE date <= DATE(DATE(), '-\(maxDays) day')
        """

        var result: [String] = []

        try dbQueue.read { db in
            result = try String.fetchAll(db, sql: sqlQuery)
        }

        return result
    }

    /// Deletes requested records from the database based on their IDs
    /// Assumes the records to be of type __UploadDataRecord__
    /// - Parameter recordIDs: The IDs array to delete
    func deleteRecords(recordIDs: [String]) throws {
        let questionMarks = "\(databaseQuestionMarks(count: recordIDs.count))"
        let sqlQuery = "DELETE FROM uploads WHERE id IN (\(questionMarks))"
        try dbQueue.write { db in
            try db.execute(sql: sqlQuery, arguments: .init(recordIDs))
        }
    }
}

extension EmbraceUploadCache {

    private static func createDBQueue(
        options: EmbraceUpload.CacheOptions,
        logger: InternalLogger
    ) throws -> DatabaseQueue {
        if case let .inMemory(name) = options.storageMechanism {
            return try DatabaseQueue(named: name)
        } else if case let .onDisk(baseURL, _) = options.storageMechanism, let fileURL = options.fileURL {
            // create base directory if necessary
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            return try EmbraceUploadCache.getDBQueueIfPossible(at: fileURL, logger: logger)
        } else {
            fatalError("Unsupported storage mechansim added")
        }
    }

    /// Will attempt to create or open the DB File. If first attempt fails due to GRDB error, it'll assume the existing DB is corruped and try again after deleting the existing DB file.
    private static func getDBQueueIfPossible(at fileURL: URL, logger: InternalLogger) throws -> DatabaseQueue {
        do {
            return try DatabaseQueue(path: fileURL.path)
        } catch {
            if let dbError = error as? DatabaseError {
                logger.error(
                    """
                    GRDB Failed to initialize EmbraceUploadCache.
                    Will attempt to remove existing file and create a new DB.
                    Message: \(dbError.message ?? "[empty message]"),
                    Result Code: \(dbError.resultCode),
                    SQLite Extended Code: \(dbError.extendedResultCode)
                    """
                )
            } else {
                logger.error(
                    """
                    Unknown error while trying to initialize EmbraceUploadCache: \(error)
                    Will attempt to recover by deleting existing DB.
                    """
                )
            }
        }

        try EmbraceUploadCache.deleteDBFile(at: fileURL, logger: logger)

        return try DatabaseQueue(path: fileURL.path)
    }

    /// Will attempt to delete the provided file.
    private static func deleteDBFile(at fileURL: URL, logger: InternalLogger) throws {
        do {
            let fileURL = URL(fileURLWithPath: fileURL.path)
            try FileManager.default.removeItem(at: fileURL)
        } catch let error {
            logger.error(
                """
                EmbraceUploadCache failed to remove DB file.
                Error: \(error.localizedDescription)
                Filepath: \(fileURL)
                """
            )
        }
    }
}
