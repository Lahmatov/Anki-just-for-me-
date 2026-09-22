import XCTest
@testable import AJFMCore

final class EventLogTests: XCTestCase {

    func testRecordsAndReturnsNewestFirst() {
        let log = EventLog(limit: 10)
        log.info(.importing, "первое")
        log.info(.importing, "второе")

        let entries = log.recent()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.message, "второе", "свежее сверху")
    }

    func testBufferDoesNotGrowForever() {
        // Журнал живёт в памяти всё время работы приложения и не должен
        // раздуваться: старое вытесняется новым.
        let log = EventLog(limit: 5)
        for index in 1...20 {
            log.info(.review, "запись \(index)")
        }
        XCTAssertEqual(log.count, 5)
        XCTAssertEqual(log.recent().first?.message, "запись 20")
        XCTAssertEqual(log.recent().last?.message, "запись 16")
    }

    func testFilterByLevel() {
        let log = EventLog(limit: 10)
        log.debug(.app, "мелочь")
        log.info(.app, "событие")
        log.error(.app, "сломалось")

        XCTAssertEqual(log.recent(minimumLevel: .warning).count, 1)
        XCTAssertEqual(log.recent(minimumLevel: .info).count, 2)
        XCTAssertEqual(log.recent(minimumLevel: .debug).count, 3)
    }

    func testFilterByCategory() {
        let log = EventLog(limit: 10)
        log.info(.importing, "набор добавлен")
        log.info(.speech, "запись начата")

        XCTAssertEqual(log.recent(category: .speech).count, 1)
        XCTAssertEqual(log.recent(category: .speech).first?.message, "запись начата")
        XCTAssertEqual(log.recent(category: .backup).count, 0)
    }

    func testLimitOnRead() {
        let log = EventLog(limit: 100)
        for index in 1...10 { log.info(.app, "\(index)") }
        XCTAssertEqual(log.recent(limit: 3).count, 3)
    }

    func testLevelOrdering() {
        XCTAssertLessThan(LogLevel.debug, LogLevel.info)
        XCTAssertLessThan(LogLevel.info, LogLevel.warning)
        XCTAssertLessThan(LogLevel.warning, LogLevel.error)
    }

    func testClear() {
        let log = EventLog(limit: 10)
        log.info(.app, "что-то")
        log.clear()
        XCTAssertEqual(log.count, 0)
        XCTAssertTrue(log.recent().isEmpty)
    }

    func testExportIsChronologicalAndReadable() {
        let log = EventLog(limit: 10)
        log.info(.importing, "набор добавлен", detail: "20 слов")
        log.error(.network, "разбор не удался")

        let text = log.exportText()
        let lines = text.split(separator: "\n").map(String.init)

        // В выгрузке порядок обычный — её читают сверху вниз.
        XCTAssertTrue(lines[0].contains("набор добавлен"))
        XCTAssertTrue(lines[1].contains("20 слов"), "подробности идут следом")
        XCTAssertTrue(lines[2].contains("разбор не удался"))
        XCTAssertTrue(lines[0].contains("importing"))
    }

    func testExportRespectsLevelFilter() {
        let log = EventLog(limit: 10)
        log.debug(.app, "мелочь")
        log.error(.app, "сломалось")

        let text = log.exportText(minimumLevel: .error)
        XCTAssertFalse(text.contains("мелочь"))
        XCTAssertTrue(text.contains("сломалось"))
    }

    func testEmptyExportIsEmptyString() {
        XCTAssertEqual(EventLog(limit: 10).exportText(), "")
    }

    func testConcurrentWritesDoNotCrash() {
        // Записи приходят и с главного актора, и из аудиопотока.
        let log = EventLog(limit: 1000)
        let group = DispatchGroup()
        for worker in 0..<8 {
            DispatchQueue.global().async(group: group) {
                for index in 0..<100 {
                    log.info(.review, "поток \(worker) запись \(index)")
                }
            }
        }
        group.wait()
        XCTAssertEqual(log.count, 800)
    }
}
