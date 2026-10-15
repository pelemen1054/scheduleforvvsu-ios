import Foundation
import SwiftSoup

enum VvsuRepositoryError: LocalizedError {
    case invalidResponse
    case groupNotFound
    case teacherNotFound
    case emptySchedule
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Не удалось прочитать ответ сайта ВВГУ."
        case .groupNotFound: return "Группа не найдена. Проверь название и выбери подсказку."
        case .teacherNotFound: return "Преподаватель не найден. Проверь ФИО и выбери подсказку."
        case .emptySchedule: return "Расписание не найдено для выбранной группы или преподавателя."
        case .server(let message): return message
        }
    }
}

struct VvsuRepository {
    private let timetableBase = URL(string: "https://www.vvsu.ru/timetable/")!
    private let groupFilterURL = URL(string: "https://www.vvsu.ru/local/controllers/getFilterValues.php")!
    private let portfolioBase = URL(string: "https://portfolio.vvsu.ru/")!
    private let teacherSearchURL = URL(string: "https://portfolio.vvsu.ru/controller/elementLoad.php")!

    private var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1", "Accept-Language": "ru-RU,ru;q=0.9"]
        return URLSession(configuration: config)
    }

    func searchGroups(_ query: String) async throws -> [String] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else { return [] }
        var components = URLComponents(url: groupFilterURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "substr", value: value),
            URLQueryItem(name: "hlBlockId", value: "46"),
            URLQueryItem(name: "hlBlockFieldName", value: "UF_GROUP_NAME"),
            URLQueryItem(name: "hlBlockFieldId", value: "UF_GROUP_ID")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { throw VvsuRepositoryError.invalidResponse }
        return Array(NSOrderedSet(array: items.compactMap { $0["value"] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).compactMap { $0 as? String }.prefix(8)
    }

    func searchTeachers(_ query: String) async throws -> [String] {
        let value = query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard value.count >= 2 else { return [] }
        var request = URLRequest(url: teacherSearchURL)
        request.httpMethod = "POST"
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(portfolioBase.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "url", value: "/page/1/"),
            URLQueryItem(name: "GetInfoBlock", value: #"{"filters":[],"filterDates":[]}"#),
            URLQueryItem(name: "element", value: "2146741160"),
            URLQueryItem(name: "clearPager", value: "true"),
            URLQueryItem(name: "search", value: value)
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await session.data(for: request)
        let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self), portfolioBase.absoluteString)
        return Array(NSOrderedSet(array: try doc.select("a[href*=/resume/tid/]").array().map { try $0.text() }
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty })).compactMap { $0 as? String }.prefix(8)
    }

    func loadGroup(_ group: String) async throws -> [Lesson] {
        let name = group.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = try await groupOptions(name)
        guard let matched = options.first(where: { ($0["value"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }),
              let groupID = matched["id"] as? String,
              let groupName = matched["value"] as? String else { throw VvsuRepositoryError.groupNotFound }

        let filter: [[String: Any]] = [[
            "valueId": groupID,
            "valueData": groupName,
            "hlBlockId": 46,
            "hlBlockFieldName": "UF_GROUP_NAME",
            "hlBlockFieldId": "UF_GROUP_ID"
        ]]
        let body: [String: Any] = ["filterQueryParams": filter]
        var request = URLRequest(url: URL(string: "https://www.vvsu.ru/timetable/index.php")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: request)
        let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self), timetableBase.absoluteString)
        let lessons = try parseGroupPage(doc, group: groupName)
        guard !lessons.isEmpty else { throw VvsuRepositoryError.emptySchedule }
        return lessons
    }

    func loadTeacher(_ teacher: String) async throws -> [Lesson] {
        let name = teacher.trimmingCharacters(in: .whitespacesAndNewlines)
        var request = URLRequest(url: teacherSearchURL)
        request.httpMethod = "POST"
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(portfolioBase.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "url", value: "/page/1/"),
            URLQueryItem(name: "GetInfoBlock", value: #"{"filters":[],"filterDates":[]}"#),
            URLQueryItem(name: "element", value: "2146741160"),
            URLQueryItem(name: "clearPager", value: "true"),
            URLQueryItem(name: "search", value: name)
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await session.data(for: request)
        let searchDoc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self), portfolioBase.absoluteString)
        let links = try searchDoc.select("a[href*=/resume/tid/]").array()
        let normalized = name.lowercased()
        guard let link = try links.first(where: { try $0.text().lowercased() == normalized }) ?? links.first(where: { try $0.text().lowercased().contains(normalized) }) ?? links.first() else {
            throw VvsuRepositoryError.teacherNotFound
        }
        let profile = try link.attr("href")
        guard let tid = profile.range(of: #"/resume/tid/(\d+)"#, options: .regularExpression).map({ String(profile[$0]).components(separatedBy: "/").last! }) else {
            throw VvsuRepositoryError.teacherNotFound
        }
        let url = URL(string: "https://portfolio.vvsu.ru/timetable/tid/\(tid)/")!
        let (pageData, _) = try await session.data(from: url)
        let doc = try SwiftSoup.parse(String(decoding: pageData, as: UTF8.self), url.absoluteString)
        let lessons = try parseTeacherPage(doc, teacherName: name)
        guard !lessons.isEmpty else { throw VvsuRepositoryError.emptySchedule }
        return lessons
    }

    private func groupOptions(_ name: String) async throws -> [[String: Any]] {
        var components = URLComponents(url: groupFilterURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "substr", value: name),
            URLQueryItem(name: "hlBlockId", value: "46"),
            URLQueryItem(name: "hlBlockFieldName", value: "UF_GROUP_NAME"),
            URLQueryItem(name: "hlBlockFieldId", value: "UF_GROUP_ID")
        ]
        let (data, _) = try await session.data(from: components.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { throw VvsuRepositoryError.invalidResponse }
        return items
    }

    private func parseGroupPage(_ doc: Document, group: String) throws -> [Lesson] {
        let dateRegex = try NSRegularExpression(pattern: #"\d{1,2}\.\d{1,2}\.\d{4}"#)
        let timeRegex = try NSRegularExpression(pattern: #"\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2}"#)
        var currentDate: String?
        var result: [Lesson] = []
        for table in try doc.select("table").array() {
            for row in try table.select("tr").array() {
                let cells = try row.select("td[data-th]").array().map { element -> (String, String) in
                    (try element.attr("data-th").trimmingCharacters(in: .whitespacesAndNewlines),
                     try element.text().split(whereSeparator: \.isWhitespace).joined(separator: " "))
                }
                guard !cells.isEmpty else { continue }
                func value(_ key: String) -> String { cells.first(where: { $0.0.caseInsensitiveCompare(key) == .orderedSame })?.1 ?? "" }
                let dateText = value("Дата")
                let timeText = value("Время")
                let subject = value("Дисциплина")
                let type = value("Занятие")
                let room = value("Аудитория")
                let teacher = value("Преподаватель")
                if let match = firstMatch(dateRegex, in: dateText) { currentDate = isoDate(match) ?? currentDate }
                guard let date = currentDate, let time = firstMatch(timeRegex, in: timeText), !subject.isEmpty else { continue }
                result.append(Lesson(date: date, time: time, subject: subject, teacher: teacher, type: type, room: room, group: group))
            }
        }
        return result
    }

    private func parseTeacherPage(_ doc: Document, teacherName: String) throws -> [Lesson] {
        let dateRegex = try NSRegularExpression(pattern: #"\d{1,2}\.\d{1,2}\.\d{4}"#)
        let timeRegex = try NSRegularExpression(pattern: #"\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2}"#)
        var currentDate: String?
        var result: [Lesson] = []
        for table in try doc.select("table").array() {
            for row in try table.select("tr").array() {
                let cells = try row.select("th,td").array().map { try $0.text().split(whereSeparator: \.isWhitespace).joined(separator: " ") }.filter { !$0.isEmpty }
                guard !cells.isEmpty else { continue }
                let full = cells.joined(separator: " ")
                if full.localizedCaseInsensitiveContains("День недели") || full.localizedCaseInsensitiveContains("Дисциплина") || full.localizedCaseInsensitiveContains("Время") { continue }
                if let match = firstMatch(dateRegex, in: full) { currentDate = isoDate(match) ?? currentDate }
                guard let date = currentDate, let index = cells.firstIndex(where: { firstMatch(timeRegex, in: $0) != nil }), let time = firstMatch(timeRegex, in: cells[index]), cells.indices.contains(index + 1) else { continue }
                let subject = cells[index + 1]
                let typeValues = ["лекция", "практика", "семинар", "лабораторная", "экзамен", "мероприятие"]
                guard !subject.isEmpty, !typeValues.contains(subject.lowercased()) else { continue }
                let type = cells.first(where: { typeValues.contains($0.lowercased()) }) ?? ""
                let room = cells.first(where: { $0.range(of: #"\d+[А-Яа-яA-Za-z]?\s*,\s*.+ "#, options: .regularExpression) != nil }) ?? ""
                let groups = cells.dropFirst(index + 2).filter { $0 != type && $0 != room && firstMatch(timeRegex, in: $0) == nil && firstMatch(dateRegex, in: $0) == nil && ($0.contains("-") || $0.contains("/")) }
                result.append(Lesson(date: date, time: time, subject: subject, teacher: teacherName, type: type, room: room, group: Array(Set(groups)).joined(separator: ", ")))
            }
        }
        return result
    }

    private func firstMatch(_ regex: NSRegularExpression, in value: String) -> String? {
        let ns = value as NSString
        guard let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range)
    }

    private func isoDate(_ value: String) -> String? {
        let input = DateFormatter()
        input.locale = Locale(identifier: "ru_RU")
        input.dateFormat = "d.M.yyyy"
        guard let date = input.date(from: value) else { return nil }
        let output = DateFormatter()
        output.locale = Locale(identifier: "en_US_POSIX")
        output.dateFormat = "yyyy-MM-dd"
        return output.string(from: date)
    }
}
