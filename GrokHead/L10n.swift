import Foundation

enum AppLanguage: String {
    case ru = "ru"
    case en = "en"
}

enum L10n {
    private static var lang: AppLanguage {
        AppSettings.shared.language
    }

    static func tr(_ ru: String, _ en: String) -> String {
        lang == .ru ? ru : en
    }

    static var openChat: String { tr("Открыть чат бота", "Open Bot Chat") }
    static var showHead: String { tr("Показать голову", "Show Head") }
    static var hideHead: String { tr("Скрыть голову", "Hide Head") }
    static var snoozeOneHour: String { tr("Отложить на 1 час", "Snooze for 1 Hour") }
    static var unsnoozeNow: String { tr("Включить уведомления сейчас", "Resume Notifications Now") }
    static var resetTasks: String { tr("Сбросить статус", "Reset Status") }
    static var recentTasksMenu: String { tr("Последние 10 задач", "Recent 10 Tasks") }
    static var noTasksYet: String { tr("Задач пока нет", "No tasks yet") }
    static var activeTasksHeader: String { tr("Текущие задачи", "Active Tasks") }
    static var settingsMenu: String { tr("Настройки…", "Settings…") }
    static var quitMenu: String { tr("Выход", "Quit") }

    static var notifDoneTitle: String { tr("GrokHead — Задача готова", "GrokHead — Task Completed") }
    static var settingsWindowTitle: String { tr("Настройки GrokHead", "GrokHead Settings") }

    static var tabGeneral: String { tr("Общие", "General") }
    static var tabSound: String { tr("Звук и Не беспокоить", "Sound & DND") }
    static var tabDisplay: String { tr("Экран и Система", "Display & System") }
}
