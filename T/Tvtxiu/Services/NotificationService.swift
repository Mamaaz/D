import Foundation
import UserNotifications

// MARK: - 通知服务

@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()
    
    @Published var isAuthorized: Bool = false
    @Published var pendingNotifications: Int = 0
    
    // MARK: - 请求权限
    
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            
            if granted {
                print("通知权限已授权")
            } else {
                print("通知权限被拒绝")
            }
        } catch {
            print("请求通知权限失败: \(error.localizedDescription)")
        }
    }
    
    /// 检查权限状态
    func checkAuthorizationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }
    
    // MARK: - 提醒订单即将到期
    
    /// 为即将到期的订单设置提醒
    func scheduleDeadlineReminders(for orders: [Order], daysBefore: Int) async {
        if !isAuthorized {
            await requestAuthorization()
        }
        
        guard isAuthorized else { return }
        
        let center = UNUserNotificationCenter.current()
        
        // 清除旧的提醒
        center.removeAllPendingNotificationRequests()
        
        let now = Date()
        var scheduledCount = 0
        
        for order in orders {
            // 跳过已完成或已归档的订单
            guard !order.isCompleted, !order.isArchived else { continue }
            
            // 获取交付日期
            guard let deadline = order.finalDeadline else { continue }
            
            // 计算提醒时间（提前 N 天）
            guard let reminderDate = Calendar.current.date(byAdding: .day, value: -daysBefore, to: deadline) else { continue }
            
            // 设置为当天上午 9 点
            var components = Calendar.current.dateComponents([.year, .month, .day], from: reminderDate)
            components.hour = 9
            components.minute = 0
            
            guard let notificationDate = Calendar.current.date(from: components),
                  notificationDate > now else { continue }
            
            // 创建通知内容
            let content = UNMutableNotificationContent()
            content.title = "📅 订单即将到期"
            content.body = "\(order.orderNumber) 将于 \(daysBefore) 天后到期，请及时处理"
            content.sound = .default
            content.userInfo = ["orderId": order.id.uuidString]
            
            // 创建触发器
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate),
                repeats: false
            )
            
            // 创建请求
            let request = UNNotificationRequest(
                identifier: "deadline-\(order.id.uuidString)",
                content: content,
                trigger: trigger
            )
            
            do {
                try await center.add(request)
                scheduledCount += 1
            } catch {
                print("设置通知失败: \(error.localizedDescription)")
            }
        }
        
        pendingNotifications = scheduledCount
        print("已设置 \(scheduledCount) 个到期提醒")
    }
    
    // MARK: - 即时通知
    
    /// 发送即时通知
    func sendNotification(title: String, body: String, userInfo: [String: Any] = [:]) async {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        let center = UNUserNotificationCenter.current()
        try? await center.add(request)
    }
    
    /// 发送加急订单通知
    func sendUrgentOrderNotification(order: Order) async {
        await sendNotification(
            title: "⚡️ 新加急订单",
            body: "订单 \(order.orderNumber) 已标记为加急，请优先处理",
            userInfo: ["orderId": order.id.uuidString, "type": "urgent"]
        )
    }
    
    /// 发送投诉订单通知
    func sendComplaintOrderNotification(order: Order) async {
        await sendNotification(
            title: "🚨 投诉订单",
            body: "订单 \(order.orderNumber) 收到投诉，请立即处理",
            userInfo: ["orderId": order.id.uuidString, "type": "complaint"]
        )
    }
    
    // MARK: - 清除通知
    
    /// 清除所有待处理通知
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        pendingNotifications = 0
    }
    
    /// 获取待处理通知数量
    func updatePendingCount() async {
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        pendingNotifications = requests.count
    }
}
