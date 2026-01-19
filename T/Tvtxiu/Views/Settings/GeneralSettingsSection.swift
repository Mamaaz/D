import SwiftUI

// MARK: - 通用设置区域

/// 服务器设置和通知设置（从 SettingsView 提取）
struct GeneralSettingsSection: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var orderManager: OrderManager
    
    var body: some View {
        Group {
            serverSettingsSection
            
            if authManager.isAuthenticated {
                notificationSettingsSection
            }
        }
    }
    
    // MARK: - 服务器设置
    
    private var serverSettingsSection: some View {
        Section("服务器设置") {
            TextField("服务器地址", text: $settingsManager.serverAddress)
                .textFieldStyle(.roundedBorder)
                .onChange(of: settingsManager.serverAddress) { newValue in
                    APIService.shared.configure(baseURL: newValue)
                }
            
            HStack {
                Text("连接状态")
                Spacer()
                HStack(spacing: TvtDesign.Spacing.xs) {
                    Circle()
                        .fill(TvtDesign.Colors.success)
                        .frame(width: 8, height: 8)
                    Text("已连接 (Mock)")
                        .font(TvtDesign.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - 通知设置
    
    private var notificationSettingsSection: some View {
        Section("通知提醒") {
            Toggle("启用到期提醒", isOn: $settingsManager.reminderEnabled)
            
            if settingsManager.reminderEnabled {
                Stepper(
                    "提前 \(settingsManager.reminderDaysBefore) 天提醒",
                    value: $settingsManager.reminderDaysBefore,
                    in: 1...14
                )
                
                notificationPermissionRow
                refreshNotificationsButton
            }
        }
    }
    
    private var notificationPermissionRow: some View {
        HStack {
            Text("通知权限")
            Spacer()
            if NotificationService.shared.isAuthorized {
                Text("已授权")
                    .foregroundColor(TvtDesign.Colors.success)
            } else {
                Button("请求权限") {
                    Task {
                        await NotificationService.shared.requestAuthorization()
                    }
                }
            }
        }
    }
    
    private var refreshNotificationsButton: some View {
        Button {
            refreshNotifications()
        } label: {
            HStack {
                Image(systemName: "bell.badge")
                Text("刷新提醒 (\(NotificationService.shared.pendingNotifications) 个待发送)")
            }
        }
        .disabled(!NotificationService.shared.isAuthorized)
    }
    
    // MARK: - 方法
    
    private func refreshNotifications() {
        Task {
            await NotificationService.shared.scheduleDeadlineReminders(
                for: orderManager.orders,
                daysBefore: settingsManager.reminderDaysBefore
            )
        }
    }
}

// MARK: - 预览

#Preview {
    Form {
        GeneralSettingsSection()
    }
    .environmentObject(AuthManager())
    .environmentObject(SettingsManager())
    .environmentObject(OrderManager())
    .frame(width: 500)
}
