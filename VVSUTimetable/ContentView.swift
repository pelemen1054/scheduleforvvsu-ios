import SwiftUI

private enum ScheduleMode: String, CaseIterable {
    case group = "Группа"
    case teacher = "Преподаватель"
}

private struct Lesson: Identifiable {
    let id = UUID()
    let time: String
    let title: String
    let details: String
    let room: String
}

struct ContentView: View {
    @State private var mode: ScheduleMode = .group
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var selectedTab = 0
    @State private var selectedGroup = "Выберите группу"
    @State private var selectedTeacher = "Выберите преподавателя"
    @State private var isDarkMode = false

    private let lessons = [
        Lesson(time: "09:00–10:30", title: "Название дисциплины", details: "Лекция · Преподаватель", room: "Ауд. 101"),
        Lesson(time: "10:40–12:10", title: "Название дисциплины", details: "Практическое занятие", room: "Ауд. 204"),
        Lesson(time: "12:40–14:10", title: "Название дисциплины", details: "Лабораторная работа", room: "Корпус 2")
    ]

    var body: some View {
        TabView(selection: $selectedTab) {
            scheduleScreen
                .tabItem { Label("Расписание", systemImage: "calendar") }
                .tag(0)

            settingsScreen
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(1)
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .tint(Color(red: 0.16, green: 0.43, blue: 0.82))
    }

    private var scheduleScreen: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("Тип расписания", selection: $mode) {
                        ForEach(ScheduleMode.allCases, id: \.self) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        selectedTab = 1
                    } label: {
                        HStack {
                            Image(systemName: mode == .group ? "person.3.fill" : "person.fill")
                            Text(mode == .group ? selectedGroup : selectedTeacher)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    HStack {
                        Button { shiftDate(by: -1) } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 42, height: 42)
                        }
                        .accessibilityLabel("Предыдущий день")

                        Spacer()
                        VStack(spacing: 3) {
                            Text(dateTitle)
                                .font(.headline)
                            Text(Calendar.current.isDateInToday(selectedDate) ? "Сегодня" : "Выбранная дата")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Сегодня") {
                            selectedDate = Calendar.current.startOfDay(for: Date())
                        }
                        .font(.subheadline.weight(.medium))
                        Spacer()

                        Button { shiftDate(by: 1) } label: {
                            Image(systemName: "chevron.right")
                                .frame(width: 42, height: 42)
                        }
                        .accessibilityLabel("Следующий день")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Занятия")
                                .font(.title3.bold())
                            Spacer()
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Обновить расписание")
                        }

                        Text("Это предварительный макет. Подключение к реальному расписанию ВВГУ будет добавлено следующим этапом.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                        ForEach(lessons) { lesson in
                            lessonCard(lesson)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("ВВГУ timetable")
        }
    }

    private var settingsScreen: some View {
        NavigationStack {
            Form {
                Section("Расписание") {
                    Picker("Группа", selection: $selectedGroup) {
                        Text("Выберите группу").tag("Выберите группу")
                        Text("Пример: БИ-123").tag("БИ-123")
                    }
                    Picker("Преподаватель", selection: $selectedTeacher) {
                        Text("Выберите преподавателя").tag("Выберите преподавателя")
                        Text("Пример: Иванов И. И.").tag("Пример: Иванов И. И.")
                    }
                }

                Section("Оформление") {
                    Toggle("Тёмная тема", isOn: $isDarkMode)
                }

                Section("О приложении") {
                    LabeledContent("Версия", value: "0.1.0 · прототип")
                    Link(destination: URL(string: "https://www.vvsu.ru/")!) {
                        Label("Официальный сайт ВВГУ", systemImage: "safari")
                    }
                    Link(destination: URL(string: "https://github.com/pelemen1054/scheduleforvvsu-ios")!) {
                        Label("Исходный код", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
            .navigationTitle("Настройки")
        }
    }

    private func lessonCard(_ lesson: Lesson) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(lesson.time)
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 94, alignment: .leading)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 6) {
                Text(lesson.title)
                    .font(.headline)
                Text(lesson.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(lesson.room, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary, lineWidth: 1))
    }

    private var dateTitle: String {
        selectedDate.formatted(
            .dateTime.locale(Locale(identifier: "ru_RU")).weekday(.wide).day().month(.wide)
        )
    }

    private func shiftDate(by amount: Int) {
        if let nextDate = Calendar.current.date(byAdding: .day, value: amount, to: selectedDate) {
            selectedDate = nextDate
        }
    }
}
