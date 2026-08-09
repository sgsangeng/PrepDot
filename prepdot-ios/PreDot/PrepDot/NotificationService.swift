import UserNotifications
import SwiftUI

class NotificationService {
    static let shared = NotificationService()

    /// 请求通知权限
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return granted ?? false
    }

    /// 设置每日定时提醒
    func scheduleDailyReminder(hour: Int, minute: Int, target: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily_review"])

        let content = UNMutableNotificationContent()
        content.title = "今日复习时间到 🧠"
        content.body = "目标 \(target) 张卡片，打开 PrepDot 开始今日复习！"
        content.sound = .default
        content.badge = NSNumber(value: target)

        var comps = DateComponents()
        comps.hour   = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_review",
                                            content: content, trigger: trigger)
        center.add(request) { err in
            if let err { print("通知注册失败: \(err)") }
        }
    }

    /// 取消所有提醒
    func cancelAll() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["daily_review"])
    }
}

// MARK: - 提醒设置页（从 ProfileView 跳转）
struct NotificationSettingsView: View {
    @State private var enabled  = UserDefaults.standard.bool(forKey: "notify_enabled")
    @State private var hour     = UserDefaults.standard.integer(forKey: "notify_hour").nonZero ?? 9
    @State private var minute   = UserDefaults.standard.integer(forKey: "notify_minute")
    @State private var permDenied = false

    var body: some View {
        Form {
            Section {
                Toggle("开启每日复习提醒", isOn: $enabled)
                    .tint(.indigo)
                    .onChange(of: enabled) { _, on in
                        if on { requestAndSchedule() } else { NotificationService.shared.cancelAll() }
                        UserDefaults.standard.set(on, forKey: "notify_enabled")
                    }
            } footer: {
                Text("每天在指定时间收到一条提醒，帮你养成复习习惯")
            }

            if enabled {
                Section("提醒时间") {
                    DatePicker("时间", selection: Binding(
                        get: {
                            Calendar.current.date(
                                from: DateComponents(hour: hour, minute: minute)) ?? Date()
                        },
                        set: { date in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                            hour   = comps.hour ?? 9
                            minute = comps.minute ?? 0
                            UserDefaults.standard.set(hour,   forKey: "notify_hour")
                            UserDefaults.standard.set(minute, forKey: "notify_minute")
                            if enabled { requestAndSchedule() }
                        }
                    ), displayedComponents: .hourAndMinute)
                }
            }

            if permDenied {
                Section {
                    Label("通知权限被拒绝，请前往「设置 → PrepDot → 通知」开启",
                          systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("每日提醒")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func requestAndSchedule() {
        Task {
            let granted = await NotificationService.shared.requestPermission()
            await MainActor.run {
                if granted {
                    let target = UserDefaults.standard.integer(forKey: "studyTarget").nonZero ?? 20
                    NotificationService.shared.scheduleDailyReminder(hour: hour, minute: minute,
                                                                      target: target)
                    permDenied = false
                } else {
                    permDenied = true
                    enabled = false
                    UserDefaults.standard.set(false, forKey: "notify_enabled")
                }
            }
        }
    }
}

extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
