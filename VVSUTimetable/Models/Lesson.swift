import Foundation

struct Lesson: Identifiable, Codable, Hashable {
    var id: String { "\(date)|\(time)|\(subject)|\(group)|\(teacher)" }
    let date: String
    let time: String
    let subject: String
    let teacher: String
    let type: String
    let room: String
    let group: String

    var parsedDate: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }
}
