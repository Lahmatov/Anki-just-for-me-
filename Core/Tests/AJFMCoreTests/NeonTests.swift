import XCTest
@testable import AJFMCore

final class NeonConnectionTests: XCTestCase {

    private let sample = "postgresql://alex:npg_Secret123@ep-cool-darkness-a1b2c3d4.eu-central-1"
        + ".aws.neon.tech/neondb?sslmode=require&channel_binding=require"

    func testParsesAConsoleConnectionString() throws {
        let connection = try NeonConnection(connectionString: sample)
        XCTAssertEqual(connection.host, "ep-cool-darkness-a1b2c3d4.eu-central-1.aws.neon.tech")
        XCTAssertEqual(connection.user, "alex")
        XCTAssertEqual(connection.database, "neondb")
    }

    func testEndpointReplacesTheFirstHostLabelWithApi() throws {
        // Так адрес строит официальный драйвер @neondatabase/serverless.
        let connection = try NeonConnection(connectionString: sample)
        XCTAssertEqual(connection.endpoint.absoluteString,
                       "https://api.eu-central-1.aws.neon.tech/sql")
    }

    func testPoolerHostGivesTheSameEndpoint() throws {
        let pooled = sample.replacingOccurrences(of: "a1b2c3d4.", with: "a1b2c3d4-pooler.")
        XCTAssertEqual(try NeonConnection(connectionString: pooled).endpoint,
                       try NeonConnection(connectionString: sample).endpoint)
    }

    func testPsqlCommandFromTheConsoleIsAccepted() throws {
        let command = "psql '\(sample)'"
        XCTAssertEqual(try NeonConnection(connectionString: command).connectionString, sample)
    }

    func testSurroundingWhitespaceIsIgnored() throws {
        XCTAssertEqual(try NeonConnection(connectionString: "  \(sample)\n").connectionString,
                       sample)
    }

    func testRedactedFormHidesThePassword() throws {
        let redacted = try NeonConnection(connectionString: sample).redacted
        XCTAssertFalse(redacted.contains("npg_Secret123"))
        XCTAssertTrue(redacted.contains("alex@"))
    }

    func testMissingDatabaseFallsBackToNeondb() throws {
        let noDatabase = "postgres://alex:pw@ep-x.eu-central-1.aws.neon.tech"
        XCTAssertEqual(try NeonConnection(connectionString: noDatabase).database, "neondb")
    }

    func testRejectsGarbage() {
        for bad in ["", "hello", "https://neon.tech",
                    "postgresql://alex@ep-x.eu-central-1.aws.neon.tech/db",   // без пароля
                    "postgresql://:pw@ep-x.eu-central-1.aws.neon.tech/db",     // без имени
                    "postgresql://alex:pw@localhost/db"] {                     // не Neon
            XCTAssertThrowsError(try NeonConnection(connectionString: bad), bad) {
                XCTAssertEqual($0 as? NeonError, .invalidConnectionString)
            }
        }
    }
}

final class NeonSQLTests: XCTestCase {

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testHeadersCarryTheConnectionAndRawMode() throws {
        let connection = try NeonConnection(
            connectionString: "postgresql://a:b@ep-x.eu-central-1.aws.neon.tech/db")
        let headers = NeonSQL.headers(for: connection)
        XCTAssertEqual(headers["Neon-Connection-String"], connection.connectionString)
        XCTAssertEqual(headers["Neon-Raw-Text-Output"], "true")
        XCTAssertEqual(headers["Neon-Array-Mode"], "true")
    }

    func testSingleQueryBody() throws {
        let body = try json(NeonSQL.body([NeonQuery("SELECT $1", [.text("x"), .null])]))
        XCTAssertEqual(body["query"] as? String, "SELECT $1")
        let params = try XCTUnwrap(body["params"] as? [Any])
        XCTAssertEqual(params.first as? String, "x")
        XCTAssertTrue(params.last is NSNull)
    }

    func testBatchBodyIsOneTransaction() throws {
        let body = try json(NeonSQL.body([NeonQuery("SELECT 1"), NeonQuery("SELECT 2")]))
        let queries = try XCTUnwrap(body["queries"] as? [[String: Any]])
        XCTAssertEqual(queries.map { $0["query"] as? String }, ["SELECT 1", "SELECT 2"])
    }

    func testValuesAreNeverSplicedIntoSQL() throws {
        // Защита от инъекции: опасная строка уходит параметром, а не текстом.
        let evil = "x'); DROP TABLE ajfm_backups; --"
        let query = CloudBackupSQL.insert(device: evil, noteCount: 1, matureWords: 0, payload: "{}")
        XCTAssertFalse(query.sql.contains(evil))
        XCTAssertEqual(query.params.first, .text(evil))
    }

    func testParsesASingleResult() throws {
        let data = Data("""
        {"fields":[{"name":"id","dataTypeID":20},{"name":"device","dataTypeID":25}],
         "rows":[["7","iPhone"],["8",null]],"command":"SELECT","rowCount":2}
        """.utf8)
        let result = try XCTUnwrap(try NeonSQL.parse(data, batch: false).first)
        XCTAssertEqual(result.fields, ["id", "device"])
        XCTAssertEqual(result.value("id", row: 0), "7")
        XCTAssertNil(result.value("device", row: 1))
        XCTAssertNil(result.value("missing", row: 0))
        XCTAssertNil(result.value("id", row: 5))
    }

    func testParsesABatch() throws {
        let data = Data("""
        {"results":[{"fields":[],"rows":[]},{"fields":[{"name":"id"}],"rows":[["42"]]}]}
        """.utf8)
        let results = try NeonSQL.parse(data, batch: true)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[1].value("id", row: 0), "42")
    }

    func testMalformedResponsesAreErrors() {
        for text in ["not json", "{}", #"{"results": 3}"#] {
            XCTAssertThrowsError(try NeonSQL.parse(Data(text.utf8), batch: text.contains("results")))
        }
    }

    func testErrorMessageFromJSONOrText() {
        XCTAssertEqual(NeonSQL.errorMessage(from: Data(#"{"message":"relation missing"}"#.utf8)),
                       "relation missing")
        XCTAssertEqual(NeonSQL.errorMessage(from: Data(" Gateway timeout \n".utf8)),
                       "Gateway timeout")
    }
}

final class CloudBackupSQLTests: XCTestCase {

    func testListParsesRowsAndSkipsBrokenOnes() {
        let result = NeonResult(
            fields: ["id", "device", "created", "note_count", "mature_words", "bytes"],
            rows: [["3", "iPhone", "1790000000", "120", "40", "52000"],
                   [nil, "iPhone", "1790000000", "1", "0", "10"]])
        let entries = CloudBackupSQL.parseList(result)
        XCTAssertEqual(entries.count, 1, "строка без id пропускается")
        XCTAssertEqual(entries[0].id, 3)
        XCTAssertEqual(entries[0].createdAt, Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(entries[0].noteCount, 120)
        XCTAssertEqual(entries[0].matureWords, 40)
        XCTAssertEqual(entries[0].bytes, 52_000)
    }

    func testPruneKeepsAtLeastOne() {
        XCTAssertEqual(CloudBackupSQL.prune(keep: 0).params, [.text("1")])
        XCTAssertEqual(CloudBackupSQL.prune(keep: 5).params, [.text("5")])
    }

    func testEraseDropsOnlyTheAppTableAndToleratesItsAbsence() {
        let sql = CloudBackupSQL.dropAll.sql
        XCTAssertEqual(sql, "DROP TABLE IF EXISTS \(CloudBackupSQL.table)")
        XCTAssertTrue(CloudBackupSQL.dropAll.params.isEmpty)
    }

    func testFetchUsesAParameter() {
        let query = CloudBackupSQL.fetch(id: 12)
        XCTAssertTrue(query.sql.contains("$1"))
        XCTAssertEqual(query.params, [.text("12")])
    }

    func testPayloadIsStoredAsTextNotJsonb() {
        // jsonb переставляет ключи — восстановление должно получить ровно
        // отправленное.
        XCTAssertTrue(CloudBackupSQL.createTable.sql.contains("payload text"))
    }

    func testUploadIsDueDaily() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(CloudBackupSQL.isDue(lastUpload: nil, now: now))
        XCTAssertFalse(CloudBackupSQL.isDue(lastUpload: now.addingTimeInterval(-3_600), now: now))
        XCTAssertTrue(CloudBackupSQL.isDue(lastUpload: now.addingTimeInterval(-86_400), now: now))
    }

    func testClockMovedBackDoesNotBlockUploadsForever() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(CloudBackupSQL.isDue(lastUpload: now.addingTimeInterval(86_400 * 30), now: now))
    }
}
