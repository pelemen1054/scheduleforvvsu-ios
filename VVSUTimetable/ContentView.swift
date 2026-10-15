import SwiftUI
import UserNotifications

private enum ScheduleMode: String, CaseIterable, Identifiable {
    case group = "Группа"
    case teacher = "Преподаватель"
    var id: String { rawValue }
}

struct ContentView: View {
    @AppStorage("selectedGroup") private var selectedGroup = ""
    @AppStorage("selectedTeacher") private var selectedTeacher = ""
    @AppStorage("darkTheme") private var darkTheme = false
    @AppStorage("autoRefresh") private var autoRefresh = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("notificationLeadMinutes") private var notificationLeadMinutes = 30
    @AppStorage("notifyBeforeLesson") private var notifyBeforeLesson = true
    @AppStorage("notifyAfterLongWindow") private var notifyAfterLongWindow = true
    @AppStorage("themeColor") private var themeColor = "blue"
    @AppStorage("favoriteGroupsRaw") private var favoriteGroupsRaw = ""
    @AppStorage("scheduleCache") private var scheduleCache = ""
    @AppStorage("lastRefreshISO") private var lastRefreshISO = ""

    @State private var mode: ScheduleMode = .group
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var suggestions: [String] = []
    @State private var lessons: [Lesson] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cacheNotice: String?
    @State private var showDatePicker = false
    @State private var showNotificationTest = false

    private let repository = VvsuRepository()
    private let accentNames = ["blue", "red", "orange", "green", "purple", "pink", "teal"]

    private var favorites: [String] {
        favoriteGroupsRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted()
    }

    private var selectedName: String {
        mode == .group ? selectedGroup : selectedTeacher
    }

    private var accent: Color {
        switch themeColor {
        case "red": return .red
        case "orange": return .orange
        case "green": return .green
        case "purple": return .purple
        case "pink": return .pink
        case "teal": return .teal
        default: return Color(red: 0.16, green: 0.43, blue: 0.82)
        }
    }

    private var dayLessons: [Lesson] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: selectedDate)
        return lessons.filter { $0.date == day }.sorted { startMinutes($0.time) < startMinutes($1.time) }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            scheduleScreen
                .tabItem { Label("Расписание", systemImage: "calendar") }
                .tag(0)
            settingsScreen
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(1)
        }
        .tint(accent)
        .preferredColorScheme(darkTheme ? .dark : .light)
        .task {
            restoreCache()
            if autoRefresh && !selectedName.isEmpty { await refreshSchedule() }
        }
        .task(id: searchText + mode.rawValue) {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.count >= 2 else { suggestions = []; return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            do {
                suggestions = mode == .group
                    ? try await repository.searchGroups(query)
                    : try await repository.searchTeachers(query)
            } catch {
                suggestions = []
            }
        }
        .onChange(of: notificationsEnabled) { _, enabled in
            if !enabled { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
            else { scheduleReminders() }
        }
    }

    private var scheduleScreen: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Тип расписания", selection: $mode) {
                        ForEach(ScheduleMode.allCases) { item in Text(item.rawValue).tag(item) }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        Label(mode == .group ? "Учебная группа" : "Преподаватель",
                              systemImage: mode == .group ? "person.3.fill" : "person.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField(mode == .group ? "Введите название группы" : "Введите ФИО преподавателя", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit { Task { await chooseCurrentSearch() } }
                            if !searchText.isEmpty {
                                Button { searchText = ""; suggestions = [] } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            }
                        }
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                        if !suggestions.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button {
                                        Task { await selectSuggestion(suggestion) }
                                    } label: {
                                        HStack {
                                            Text(suggestion).foregroundStyle(.primary)
                                            Spacer()
                                            Image(systemName: "arrow.up.left").foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 12)
                                    }
                                    .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }

                        if !selectedName.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text("Выбрано: (selectedName)").lineLimit(1)
                                Spacer()
                                if mode == .group {
                                    Button { toggleFavorite(selectedGroup) } label: {
                                        Image(systemName: favorites.contains(selectedGroup) ? "star.fill" : "star")
                                            .foregroundStyle(.yellow)
                                    }
                                    .accessibilityLabel(favorites.contains(selectedGroup) ? "Убрать из избранного" : "Добавить в избранное")
                                }
                            }
                            .font(.subheadline)
                        }
                    }

                    HStack(spacing: 8) {
                        Button { shiftDate(-1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }
                            .accessibilityLabel("Предыдущий день")
                        Spacer(minLength: 0)
                        Button { showDatePicker = true } label: {
                            VStack(spacing: 3) {
                                Text(dateTitle).font(.headline)
                                Text(Calendar.current.isDateInToday(selectedDate) ? "Сегодня" : "Выбрать дату")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 0)
                        Button("Сегодня") { selectedDate = Calendar.current.startOfDay(for: Date()) }
                            .font(.subheadline.weight(.medium))
                        Button { shiftDate(1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }
                            .accessibilityLabel("Следующий день")
                    }
                    .padding(.horizontal, 4)

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Занятия").font(.title2.bold())
                            if !lastRefreshISO.isEmpty {
                                Text("Обновлено: \(formattedRefreshDate)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button { Task { await refreshSchedule() } } label: {
                            if isLoading { ProgressView() } else { Image(systemName: "arrow.clockwise").font(.title3) }
                        }
                        .disabled(isLoading || selectedName.isEmpty)
                        .accessibilityLabel("Обновить расписание")
                    }

                    if let cacheNotice {
                        Label(cacheNotice, systemImage: "externaldrive")
                            .font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10).background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10).background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    if selectedName.isEmpty {
                        ContentUnavailableView("Выберите расписание", systemImage: "calendar.badge.magnifyingglass",
                                               description: Text("Введите название группы или ФИО преподавателя в поле выше."))
                            .padding(.top, 20)
                    } else if isLoading && lessons.isEmpty {
                        ProgressView("Загружаем расписание…").padding(30)
                    } else if dayLessons.isEmpty {
                        ContentUnavailableView("Занятий нет", systemImage: "calendar",
                                               description: Text("На выбранную дату занятия не найдены. Проверьте другие дни или обновите расписание."))
                            .padding(.top, 16)
                    } else {
                        ForEach(dayLessons) { lesson in lessonCard(lesson) }
                    }
                }
                .padding()
            }
            .navigationTitle("ВВГУ timetable")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if mode == .group && !favorites.isEmpty {
                        Menu {
                            ForEach(favorites, id: \.self) { group in
                                Button(group) { Task { await selectSuggestion(group) } }
                            }
                        } label: { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                        .accessibilityLabel("Избранные группы")
                    }
                }
            }
            .refreshable { await refreshSchedule() }
            .sheet(isPresented: $showDatePicker) {
                NavigationStack {
                    DatePicker("Дата расписания", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                        .navigationTitle("Выбрать дату")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Готово") { showDatePicker = false } }
                            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { showDatePicker = false } }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var settingsScreen: some View {
        NavigationStack {
            Form {
                Section("Расписание") {
                    LabeledContent("Группа", value: selectedGroup.isEmpty ? "Не выбрана" : selectedGroup)
                    Button("Изменить группу") { mode = .group; selectedTab = 0; searchText = selectedGroup }
                    LabeledContent("Преподаватель", value: selectedTeacher.isEmpty ? "Не выбран" : selectedTeacher)
                    Button("Изменить преподавателя") { mode = .teacher; selectedTab = 0; searchText = selectedTeacher }
                    Toggle("Автообновление при запуске", isOn: $autoRefresh)
                }
                Section("Избранные группы") {
                    if favorites.isEmpty {
                        Text("Добавляйте группы в избранное звёздочкой на экране расписания.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(favorites, id: \.self) { group in
                            HStack {
                                Button(group) { Task { await selectSuggestion(group) }; selectedTab = 0 }
                                Spacer()
                                Button(role: .destructive) { toggleFavorite(group) } label: { Image(systemName: "trash") }
                            }
                        }
                    }
                }
                Section("Оформление") {
                    Toggle("Тёмная тема", isOn: $darkTheme)
                    Picker("Акцентный цвет", selection: $themeColor) {
                        Text("Синий").tag("blue")
                        Text("Красный").tag("red")
                        Text("Оранжевый").tag("orange")
                        Text("Зелёный").tag("green")
                        Text("Фиолетовый").tag("purple")
                        Text("Розовый").tag("pink")
                        Text("Бирюзовый").tag("teal")
                    }
                }
                Section("Напоминания о занятиях") {
                    Toggle("Включить уведомления", isOn: $notificationsEnabled)
                    if notificationsEnabled {
                        Picker("Напоминать заранее", selection: $notificationLeadMinutes) {
                            Text("5 минут").tag(5)
                            Text("10 минут").tag(10)
                            Text("15 минут").tag(15)
                            Text("30 минут").tag(30)
                            Text("60 минут").tag(60)
                        }
                        Toggle("Перед первой парой и после длинного окна", isOn: $notifyBeforeLesson)
                        Toggle("Напоминать после окна от 30 минут", isOn: $notifyAfterLongWindow)
                        Button("Проверить уведомления") { requestNotificationPermissionAndTest() }
                    }
                    Text("iOS может ограничивать доставку уведомлений в зависимости от настроек устройства.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Кэш и обновление") {
                    LabeledContent("Последнее обновление", value: lastRefreshISO.isEmpty ? "Пока не обновлялось" : formattedRefreshDate)
                    Button("Обновить расписание сейчас") { selectedTab = 0; Task { await refreshSchedule() } }
                        .disabled(selectedName.isEmpty)
                    Button("Очистить локальный кэш", role: .destructive) {
                        scheduleCache = ""; lessons = []; cacheNotice = nil
                    }
                }
                Section("О приложении") {
                    LabeledContent("Версия", value: "1.0.4")
                    Link(destination: URL(string: "https://www.vvsu.ru/")!) { Label("Официальный сайт ВВГУ", systemImage: "safari") }
                    Link(destination: URL(string: "https://github.com/pelemen1054/scheduleforvvsu-ios")!) { Label("Исходный код на GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                    Link(destination: URL(string: "https://t.me/VVSUTimtableSupportBot")!) { Label("Поддержка в Telegram", systemImage: "paperplane") }
                    Text("Независимый проект, не являющийся официальным приложением университета.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
        }
    }

    private func lessonCard(_ lesson: Lesson) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(lesson.time).font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 92, alignment: .leading).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 6) {
                Text(lesson.subject).font(.headline)
                if !lesson.teacher.isEmpty { Label(lesson.teacher, systemImage: "person").font(.subheadline).foregroundStyle(.secondary) }
                if !lesson.type.isEmpty { Label(lesson.type, systemImage: "book.closed").font(.caption).foregroundStyle(.secondary) }
                if !lesson.room.isEmpty { Label(lesson.room, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary) }
                if mode == .teacher && !lesson.group.isEmpty { Label(lesson.group, systemImage: "person.3").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary, lineWidth: 1))
    }

    private var dateTitle: String {
        selectedDate.formatted(.dateTime.locale(Locale(identifier: "ru_RU")).weekday(.wide).day().month(.wide))
    }

    private var formattedRefreshDate: String {
        guard let date = ISO8601DateFormatter().date(from: lastRefreshISO) else { return lastRefreshISO }
        return date.formatted(.dateTime.locale(Locale(identifier: "ru_RU")).day().month(.abbreviated).hour().minute())
    }

    private func shiftDate(_ amount: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: amount, to: selectedDate) {
            selectedDate = Calendar.current.startOfDay(for: next)
        }
    }

    private func startMinutes(_ time: String) -> Int {
        let start = time.components(separatedBy: "-").first?.trimmingCharacters(in: .whitespaces) ?? ""
        let pieces = start.split(separator: ":").compactMap { Int($0) }
        return pieces.count == 2 ? pieces[0] * 60 + pieces[1] : Int.max
    }

    private func chooseCurrentSearch() async {
        let value = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if suggestions.contains(value) { await selectSuggestion(value) }
        else if mode == .group {
            do {
                let options = try await repository.searchGroups(value)
                if let match = options.first(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) ?? options.first {
                    await selectSuggestion(match)
                } else { errorMessage = "Не удалось найти группу. Выбери один из вариантов подсказки." }
            } catch { errorMessage = error.localizedDescription }
        } else {
            do {
                let options = try await repository.searchTeachers(value)
                if let match = options.first(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) ?? options.first {
                    await selectSuggestion(match)
                } else { errorMessage = "Не удалось найти преподавателя. Выбери один из вариантов подсказки." }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func selectSuggestion(_ value: String) async {
        if mode == .group { selectedGroup = value } else { selectedTeacher = value }
        searchText = value
        suggestions = []
        await refreshSchedule()
    }

    private func refreshSchedule() async {
        guard !selectedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        errorMessage = nil
        cacheNotice = nil
        defer { isLoading = false }
        do {
            let downloaded = mode == .group
                ? try await repository.loadGroup(selectedGroup)
                : try await repository.loadTeacher(selectedTeacher)
            lessons = downloaded
            if let data = try? JSONEncoder().encode(downloaded) {
                scheduleCache = String(decoding: data, as: UTF8.self)
            }
            lastRefreshISO = ISO8601DateFormatter().string(from: Date())
            scheduleCache = scheduleCache
            cacheNotice = nil
            scheduleReminders()
        } catch {
            errorMessage = error.localizedDescription
            if lessons.isEmpty { restoreCache() }
            if !lessons.isEmpty { cacheNotice = "Нет соединения или обновление не удалось. Показано сохранённое расписание; оно может быть устаревшим." }
        }
    }

    private func restoreCache() {
        guard let data = scheduleCache.data(using: .utf8),
              let saved = try? JSONDecoder().decode([Lesson].self, from: data),
              !saved.isEmpty else { return }
        lessons = saved
        cacheNotice = "Показано сохранённое расписание. Подключитесь к интернету, чтобы обновить данные."
    }

    private func toggleFavorite(_ group: String) {
        guard !group.isEmpty else { return }
        var values = Set(favorites)
        if values.contains(group) { values.remove(group) } else { values.insert(group) }
        favoriteGroupsRaw = values.sorted().joined(separator: "\n")
    }

    private func requestNotificationPermissionAndTest() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                guard granted else { errorMessage = "Разреши уведомления для приложения в настройках iPhone."; return }
                let content = UNMutableNotificationContent()
                content.title = "ВВГУ timetable"
                content.body = "Проверочное уведомление работает."
                content.sound = .default
                let request = UNNotificationRequest(identifier: "vvsu-test-notification", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
                UNUserNotificationCenter.current().add(request)
                showNotificationTest = true
            }
        }
    }

    private func scheduleReminders() {
        guard notificationsEnabled else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let now = Date()
            let calendar = Calendar.current
            let sorted = lessons.sorted { ($0.date + $0.time) < ($1.date + $1.time) }
            var requests: [UNNotificationRequest] = []
            for (index, lesson) in sorted.enumerated() {
                guard let start = lessonStart(lesson), start > now else { continue }
                let previous = index > 0 ? sorted[index - 1] : nil
                let previousEnd = previous.flatMap(lessonEnd)
                let gap = previousEnd.map { start.timeIntervalSince($0) / 60 } ?? .greatestFiniteMagnitude
                let shouldNotify = (notifyBeforeLesson && (previousEnd == nil || gap > 15)) || (notifyAfterLongWindow && gap >= 30)
                guard shouldNotify, let fireDate = calendar.date(byAdding: .minute, value: -notificationLeadMinutes, to: start), fireDate > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Напоминание о паре"
                content.body = "\(lesson.subject) начнётся через \(notificationLeadMinutes) мин. · \(lesson.time)"
                content.sound = .default
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                requests.append(UNNotificationRequest(identifier: lesson.id, content: content, trigger: trigger))
            }
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            for request in requests.prefix(60) { UNUserNotificationCenter.current().add(request) }
        }
    }

    private func lessonStart(_ lesson: Lesson) -> Date? {
        guard let date = lesson.parsedDate else { return nil }
        let time = lesson.time.components(separatedBy: "-").first?.trimmingCharacters(in: .whitespaces) ?? ""
        let pieces = time.split(separator: ":").compactMap { Int($0) }
        guard pieces.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: pieces[0], minute: pieces[1], second: 0, of: date)
    }

    private func lessonEnd(_ lesson: Lesson) -> Date? {
        guard let date = lesson.parsedDate else { return nil }
        let time = lesson.time.components(separatedBy: "-").dropFirst().first?.trimmingCharacters(in: .whitespaces) ?? ""
        let pieces = time.split(separator: ":").compactMap { Int($0) }
        guard pieces.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: pieces[0], minute: pieces[1], second: 0, of: date)
    }
}
