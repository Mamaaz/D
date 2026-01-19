import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var orderManager: OrderManager
    
    @State private var showUserManagement: Bool = false
    @State private var showImportSheet: Bool = false
    @State private var showPerformanceConfig: Bool = false
    @State private var showMonthlyPerformance: Bool = false
    @State private var isExporting: Bool = false
    
    // SwiftUI 对话框状态
    @State private var showExportFormatDialog: Bool = false
    @State private var showDeleteConfirmSheet: Bool = false
    @State private var deleteConfirmText: String = ""
    
    var body: some View {
        Form {
            // 服务器设置
            Section("服务器设置") {
                TextField("服务器地址", text: $settingsManager.serverAddress)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: settingsManager.serverAddress) { newValue in
                        APIService.shared.configure(baseURL: newValue)
                    }
                
                HStack {
                    Text("连接状态")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("已连接 (Mock)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 提醒设置 (仅登录后显示)
            if authManager.isAuthenticated {
                Section("通知提醒") {
                    Toggle("启用到期提醒", isOn: $settingsManager.reminderEnabled)
                    
                    if settingsManager.reminderEnabled {
                        Stepper(
                            "提前 \(settingsManager.reminderDaysBefore) 天提醒",
                            value: $settingsManager.reminderDaysBefore,
                            in: 1...14
                        )
                        
                        HStack {
                            Text("通知权限")
                            Spacer()
                            if NotificationService.shared.isAuthorized {
                                Text("已授权")
                                    .foregroundColor(.green)
                            } else {
                                Button("请求权限") {
                                    Task {
                                        await NotificationService.shared.requestAuthorization()
                                    }
                                }
                            }
                        }
                        
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
                }
            }
            
            // 管理员功能
            if authManager.hasAdminPrivilege {
                // AI 配置 (仅管理员) - 使用提取的组件
                AISettingsSection()
                
                // 腾讯文档同步 (仅管理员)
                TencentDocsSyncSection()
                
                // 交付规则 (仅管理员)
                Section("交付规则") {
                    Stepper(
                        "提前 \(settingsManager.advanceDays) 天",
                        value: $settingsManager.advanceDays,
                        in: 0...30
                    )
                    
                    Text("设置后，解析订单时会自动将交付日期提前相应天数")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 绩效配置 (仅管理员)
                Section("绩效管理") {
                    Button {
                        showPerformanceConfig = true
                    } label: {
                        HStack {
                            Label("绩效配置", systemImage: "chart.bar.fill")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        showMonthlyPerformance = true
                    } label: {
                        HStack {
                            Label("月度工资社保", systemImage: "dollarsign.circle.fill")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                
                // 数据管理
                Section("数据管理") {
                    Button {
                        showImportSheet = true
                    } label: {
                        Label("导入 Excel 数据", systemImage: "square.and.arrow.down.fill")
                    }
                    
                    Button {
                        showExportFormatDialog = true
                    } label: {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Label("导出所有数据", systemImage: "square.and.arrow.up.fill")
                        }
                    }
                    .disabled(isExporting)
                    
                    // 完整备份（含头像）
                    Button {
                        exportFullBackup()
                    } label: {
                        Label("完整备份（含头像）", systemImage: "arrow.down.doc.fill")
                    }
                    
                    Button {
                        importFullBackup()
                    } label: {
                        Label("恢复完整备份", systemImage: "arrow.up.doc.fill")
                    }
                    
                    Text("完整备份包含 JSON 数据和头像文件（ZIP 格式）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button {
                        importMigrationData()
                    } label: {
                        Label("导入旧版迁移数据", systemImage: "clock.arrow.circlepath")
                    }
                    
                    Text("从旧版 JSON 备份文件恢复数据")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 危险操作
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmSheet = true
                    } label: {
                        Label("删除所有数据", systemImage: "trash.fill")
                    }
                }
            }
            
            // 关于
            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                
                // 仅登录后显示当前用户
                if authManager.isAuthenticated {
                    HStack {
                        Text("当前用户")
                        Spacer()
                        Text("\(authManager.currentUser?.displayName ?? "-") (\(authManager.currentUser?.role.displayName ?? "-"))")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 退出登录 (仅登录后显示)
            if authManager.isAuthenticated {
                Section {
                    Button(role: .destructive) {
                        authManager.logout()
                    } label: {
                        HStack {
                            Spacer()
                            Text("退出登录")
                            Spacer()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .sheet(isPresented: $showUserManagement) {
            UserManagementView()
        }
        .sheet(isPresented: $showImportSheet) {
            ImportDataView()
        }
        .sheet(isPresented: $showPerformanceConfig) {
            StaffPerformanceConfigView()
        }
        .sheet(isPresented: $showMonthlyPerformance) {
            MonthlyPerformanceView()
        }
        .confirmationDialog("选择导出格式", isPresented: $showExportFormatDialog) {
            Button("导出 CSV") {
                selectCSVExportType()
            }
            Button("导出 JSON") {
                performJSONExport()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前订单数: \(orderManager.orders.count)，人员数: \(orderManager.staffList.count)")
        }
        .sheet(isPresented: $showDeleteConfirmSheet) {
            DeleteConfirmationSheet(
                isPresented: $showDeleteConfirmSheet,
                confirmText: $deleteConfirmText,
                onConfirm: {
                    Task {
                        await deleteAllData()
                    }
                }
            )
        }
    }
    
    // MARK: - 刷新通知
    
    private func refreshNotifications() {
        Task {
            await NotificationService.shared.scheduleDeadlineReminders(
                for: orderManager.orders,
                daysBefore: settingsManager.reminderDaysBefore
            )
        }
    }
    
    // MARK: - 导出数据
    
    private func selectCSVExportType() {
        // 使用 SwiftUI confirmationDialog 选择 CSV 类型
        let alert = NSAlert()
        alert.messageText = "选择 CSV 类型"
        alert.addButton(withTitle: "订单数据")
        alert.addButton(withTitle: "人员数据")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            exportCSV(type: .orders)
        case .alertSecondButtonReturn:
            exportCSV(type: .staff)
        default:
            break
        }
    }
    
    private func performJSONExport() {
        exportJSON()
    }
    
    private enum ExportType {
        case orders, staff
    }
    
    private func exportCSV(type: ExportType) {
        let panel = NSSavePanel()
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none).replacingOccurrences(of: "/", with: "-")
        
        switch type {
        case .orders:
            panel.nameFieldStringValue = "tvtxiu_orders_\(dateStr).csv"
        case .staff:
            panel.nameFieldStringValue = "tvtxiu_staff_\(dateStr).csv"
        }
        
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "选择导出位置"
        panel.prompt = "导出"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let csvContent: String
                
                switch type {
                case .orders:
                    csvContent = generateOrdersCSV()
                case .staff:
                    csvContent = generateStaffCSV()
                }
                
                try csvContent.write(to: url, atomically: true, encoding: .utf8)
                print("CSV 已导出到: \(url.path)")
                
                // 可选：在 Finder 中显示
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            } catch {
                print("导出失败: \(error)")
            }
        }
    }
    
    private func generateOrdersCSV() -> String {
        var csv = "订单号,拍摄日期,拍摄地点,摄影师,摄影顾问,总张数,加片数,类型,分群,加急,投诉,分配时间,初修截止,精修截止,婚期,负责人,状态,归档月份,备注\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for order in orderManager.orders {
            let fields: [String] = [
                order.orderNumber,
                order.shootDate,
                order.shootLocation,
                order.photographer,
                order.consultant,
                "\(order.totalCount)",
                "\(order.extraCount)",
                order.shootType.displayName,
                order.isInGroup ? "是" : "否",
                order.isUrgent ? "是" : "否",
                order.isComplaint ? "是" : "否",
                order.assignedAt != nil ? dateFormatter.string(from: order.assignedAt!) : "",
                order.trialDeadline != nil ? dateFormatter.string(from: order.trialDeadline!) : "",
                order.finalDeadline != nil ? dateFormatter.string(from: order.finalDeadline!) : "",
                order.weddingDate,
                order.assignedTo != nil ? (orderManager.staffList.first(where: { $0.id == order.assignedTo })?.displayName ?? "") : "",
                order.isCompleted ? "已完成" : "待处理",
                order.archiveMonth ?? "",
                order.remarks
            ]
            csv += fields.map { escapeCSV($0) }.joined(separator: ",") + "\n"
        }
        
        return csv
    }
    
    private func generateStaffCSV() -> String {
        var csv = "用户名,昵称,真名,角色,基础单价,进群加项,加急加项,投诉加项,婚礼系数,日历颜色(R),日历颜色(G),日历颜色(B)\n"
        
        for staff in orderManager.staffList {
            let fields: [String] = [
                staff.username,
                staff.nickname,
                staff.realName,
                staff.role.displayName,
                String(format: "%.2f", staff.basePrice),
                String(format: "%.2f", staff.groupBonus),
                String(format: "%.2f", staff.urgentBonus),
                String(format: "%.2f", staff.complaintBonus),
                String(format: "%.2f", staff.weddingMultiplier),
                String(format: "%.2f", staff.calendarColorRed),
                String(format: "%.2f", staff.calendarColorGreen),
                String(format: "%.2f", staff.calendarColorBlue)
            ]
            csv += fields.map { escapeCSV($0) }.joined(separator: ",") + "\n"
        }
        
        return csv
    }
    
    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
    
    private func exportJSON() {
        // 先从 API 获取最新数据再导出，确保数据完整
        Task {
            // 刷新数据确保完整
            await orderManager.loadFromAPI()
            
            await MainActor.run {
                struct ExportData: Codable {
                    let exportDate: String
                    let orders: [Order]
                    let staffList: [User]
                }
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                
                let exportData = ExportData(
                    exportDate: dateFormatter.string(from: Date()),
                    orders: orderManager.orders,
                    staffList: orderManager.staffList
                )
                
                // 检查数据完整性
                if orderManager.staffList.isEmpty {
                    let alert = NSAlert()
                    alert.messageText = "警告"
                    alert.informativeText = "员工列表为空，导出的数据可能不完整。\n建议使用「完整备份（含头像）」功能从服务器获取完整数据。"
                    alert.addButton(withTitle: "继续导出")
                    alert.addButton(withTitle: "取消")
                    alert.alertStyle = .warning
                    
                    if alert.runModal() != .alertFirstButtonReturn {
                        return
                    }
                }
                
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "tvtxiu_export_\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none).replacingOccurrences(of: "/", with: "-")).json"
                panel.allowedContentTypes = [.json]
                panel.message = "选择导出位置"
                panel.prompt = "导出"
                
                if panel.runModal() == .OK, let url = panel.url {
                    do {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        encoder.dateEncodingStrategy = .iso8601
                        let data = try encoder.encode(exportData)
                        try data.write(to: url)
                        
                        // 显示导出成功信息
                        let successAlert = NSAlert()
                        successAlert.messageText = "导出成功"
                        successAlert.informativeText = "已导出 \(orderManager.orders.count) 条订单，\(orderManager.staffList.count) 位员工"
                        successAlert.addButton(withTitle: "在 Finder 中显示")
                        successAlert.addButton(withTitle: "确定")
                        
                        if successAlert.runModal() == .alertFirstButtonReturn {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                        }
                    } catch {
                        let errorAlert = NSAlert()
                        errorAlert.messageText = "导出失败"
                        errorAlert.informativeText = error.localizedDescription
                        errorAlert.alertStyle = .critical
                        errorAlert.runModal()
                    }
                }
            }
        }
    }
    
    // MARK: - 导入迁移数据
    
    private func importMigrationData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "选择迁移数据文件 (JSON)"
        panel.prompt = "导入"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    let data = try Data(contentsOf: url)
                    let result = try await APIService.shared.importMigrationData(data: data)
                    
                    // 显示结果
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "迁移完成"
                        alert.informativeText = result
                        alert.addButton(withTitle: "确定")
                        alert.runModal()
                        
                        // 刷新数据
                        Task {
                            await orderManager.loadFromAPI()
                        }
                    }
                } catch {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "迁移失败"
                        alert.informativeText = error.localizedDescription
                        alert.addButton(withTitle: "确定")
                        alert.alertStyle = .critical
                        alert.runModal()
                    }
                }
            }
        }
    }
    
    // MARK: - 完整备份（含头像）
    
    private func exportFullBackup() {
        let panel = NSSavePanel()
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none).replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "tvtxiu_backup_\(dateStr).zip"
        panel.allowedContentTypes = [.zip]
        panel.message = "选择备份保存位置"
        panel.prompt = "导出"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    // 从服务器下载备份
                    let backupData = try await APIService.shared.downloadBackup()
                    try backupData.write(to: url)
                    
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "备份成功"
                        alert.informativeText = "完整备份（含头像）已保存到:\n\(url.path)"
                        alert.addButton(withTitle: "在 Finder 中显示")
                        alert.addButton(withTitle: "确定")
                        
                        if alert.runModal() == .alertFirstButtonReturn {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                        }
                    }
                } catch {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "备份失败"
                        alert.informativeText = error.localizedDescription
                        alert.addButton(withTitle: "确定")
                        alert.alertStyle = .critical
                        alert.runModal()
                    }
                }
            }
        }
    }
    
    private func importFullBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "选择备份文件 (ZIP)"
        panel.prompt = "恢复"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    let data = try Data(contentsOf: url)
                    let result = try await APIService.shared.restoreBackup(data: data)
                    
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "恢复完成"
                        alert.informativeText = result
                        alert.addButton(withTitle: "确定")
                        alert.runModal()
                        
                        // 刷新数据
                        Task {
                            await orderManager.loadFromAPI()
                        }
                    }
                } catch {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "恢复失败"
                        alert.informativeText = error.localizedDescription
                        alert.addButton(withTitle: "确定")
                        alert.alertStyle = .critical
                        alert.runModal()
                    }
                }
            }
        }
    }
    
    // MARK: - 删除所有数据
    
    private func deleteAllData() async {
        do {
            try await APIService.shared.deleteAllData()
            
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "删除成功"
                alert.informativeText = "所有订单数据已删除"
                alert.addButton(withTitle: "确定")
                alert.runModal()
                
                // 刷新数据
                Task {
                    await orderManager.loadFromAPI()
                }
            }
        } catch {
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "删除失败"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "确定")
                alert.alertStyle = .critical
                alert.runModal()
            }
        }
    }
}

// MARK: - 用户管理视图

struct UserManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var orderManager: OrderManager
    @EnvironmentObject var authManager: AuthManager
    
    @State private var showAddUser: Bool = false
    @State private var editingUser: User?
    @State private var showDeleteConfirm: Bool = false
    @State private var userToDelete: User?
    @State private var showDeleteError: Bool = false
    @State private var deleteErrorMessage: String = ""
    
    @State private var newUsername: String = ""
    @State private var newPassword: String = ""
    @State private var newRole: UserRole = .staff
    @State private var newBasePrice: Double = 8.0
    
    // 活跃后期人员
    private var activeStaff: [User] {
        orderManager.staffList.filter { !$0.isHidden && $0.role.isRegularStaff }
    }
    
    // 离职后期人员
    private var hiddenStaff: [User] {
        orderManager.staffList.filter { $0.isHidden && $0.role.isRegularStaff }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // 管理员列表
                Section("管理员") {
                    ForEach(adminUsers) { user in
                        UserRowWithActions(
                            user: user,
                            canEdit: authManager.currentUser?.role == .admin,
                            onEdit: { editingUser = user },
                            onDelete: nil // 管理员不能删除
                        )
                    }
                }
                
                // 活跃后期人员列表
                Section("后期人员") {
                    if activeStaff.isEmpty {
                        Text("暂无后期人员")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(activeStaff) { user in
                            UserRowWithActions(
                                user: user,
                                canEdit: true,
                                onEdit: { editingUser = user },
                                onDelete: {
                                    userToDelete = user
                                    showDeleteConfirm = true
                                },
                                onHide: {
                                    hideUser(user)
                                }
                            )
                        }
                    }
                }
                
                // 离职人员列表（隐藏的）
                if !hiddenStaff.isEmpty {
                    Section("离职人员") {
                        ForEach(hiddenStaff) { user in
                            UserRowWithActions(
                                user: user,
                                canEdit: true,
                                onEdit: { editingUser = user },
                                onDelete: {
                                    userToDelete = user
                                    showDeleteConfirm = true
                                },
                                onHide: {
                                    unhideUser(user)
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("用户管理")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddUser = true
                    } label: {
                        Label("添加用户", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddUser) {
                addUserSheet
            }
            .sheet(item: $editingUser) { user in
                EditUserSheet(user: user, orderManager: orderManager)
            }
            .alert("确认删除", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    if let user = userToDelete {
                        deleteUser(user)
                    }
                }
            } message: {
                if let user = userToDelete {
                    Text("确定要删除用户「\(user.displayName)」吗？")
                }
            }
            .alert("无法删除", isPresented: $showDeleteError) {
                Button("确定") { }
            } message: {
                Text(deleteErrorMessage)
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
    }
    
    /// 获取管理员用户列表（包括当前登录的管理员）
    private var adminUsers: [User] {
        // 从 orderManager 获取所有管理员用户
        var admins = orderManager.staffList.filter { $0.role == .admin || $0.role == .subAdmin }
        
        // 如果当前登录用户是管理员但不在列表中，添加到列表
        if let currentUser = authManager.currentUser,
           currentUser.role == .admin || currentUser.role == .subAdmin,
           !admins.contains(where: { $0.id == currentUser.id }) {
            admins.insert(currentUser, at: 0)
        }
        
        return admins
    }
    
    private var addUserSheet: some View {
        NavigationStack {
            Form {
                Section("账户信息") {
                    TextField("名称（登录 + 显示）", text: $newUsername)
                    SecureField("密码", text: $newPassword)
                }
                
                Section("基本信息") {
                    Picker("角色", selection: $newRole) {
                        ForEach([UserRole.staff, UserRole.outsource, UserRole.subAdmin], id: \.self) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    
                    if newRole == .staff || newRole == .outsource {
                        HStack {
                            Text("基础单价")
                            Spacer()
                            TextField("元/张", value: $newBasePrice, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }
                }
            }
            .navigationTitle("添加用户")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        resetAddUserForm()
                        showAddUser = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        addUser()
                    }
                    .disabled(newUsername.isEmpty || newPassword.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 300)
        #endif
    }
    
    private func addUser() {
        let user = User(
            username: newUsername,
            nickname: newUsername,
            realName: "",
            role: newRole,
            basePrice: newBasePrice
        )
        orderManager.staffList.append(user)
        // TODO: 保存密码到后端
        resetAddUserForm()
        showAddUser = false
    }
    
    private func resetAddUserForm() {
        newUsername = ""
        newPassword = ""
        newRole = .staff
        newBasePrice = 8.0
    }
    
    // MARK: - 用户操作
    
    /// 隐藏用户（离职）
    private func hideUser(_ user: User) {
        Task {
            do {
                let updatedUser = try await UserService.shared.hideUser(id: user.id)
                // 更新本地列表
                if let index = orderManager.staffList.firstIndex(where: { $0.id == user.id }) {
                    orderManager.staffList[index] = updatedUser
                }
            } catch {
                print("隐藏用户失败: \(error)")
            }
        }
    }
    
    /// 取消隐藏用户
    private func unhideUser(_ user: User) {
        Task {
            do {
                let updatedUser = try await UserService.shared.unhideUser(id: user.id)
                // 更新本地列表
                if let index = orderManager.staffList.firstIndex(where: { $0.id == user.id }) {
                    orderManager.staffList[index] = updatedUser
                }
            } catch {
                print("取消隐藏用户失败: \(error)")
            }
        }
    }
    
    /// 删除用户（调用后端 API）
    private func deleteUser(_ user: User) {
        Task {
            do {
                try await UserService.shared.deleteUser(id: user.id)
                // 从本地列表移除
                orderManager.staffList.removeAll { $0.id == user.id }
            } catch let error as APIError {
                switch error {
                case .validationError(let message):
                    deleteErrorMessage = message
                    showDeleteError = true
                default:
                    deleteErrorMessage = "删除失败: \(error.localizedDescription)"
                    showDeleteError = true
                }
            } catch {
                deleteErrorMessage = "删除失败: \(error.localizedDescription)"
                showDeleteError = true
            }
        }
    }
}

// MARK: - 用户行（带操作按钮）

struct UserRowWithActions: View {
    let user: User
    let canEdit: Bool
    let onEdit: () -> Void
    let onDelete: (() -> Void)?
    let onHide: (() -> Void)?  // 隐藏/显示回调
    
    init(user: User, canEdit: Bool, onEdit: @escaping () -> Void, onDelete: (() -> Void)?, onHide: (() -> Void)? = nil) {
        self.user = user
        self.canEdit = canEdit
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onHide = onHide
    }
    
    var body: some View {
        HStack {
            // 用户颜色圆点
            Circle()
                .fill(Color(red: user.calendarColorRed, green: user.calendarColorGreen, blue: user.calendarColorBlue))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(String(user.displayName.prefix(1)))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                )
                .opacity(user.isHidden ? 0.5 : 1.0)  // 隐藏用户显示半透明
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(user.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(user.isHidden ? .secondary : .primary)
                    
                    Text(user.role.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(roleColor.opacity(0.2))
                        .foregroundColor(roleColor)
                        .cornerRadius(4)
                    
                    // 离职标识
                    if user.isHidden {
                        Text("离职")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.gray)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 8) {
                    Text("@\(user.username)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if user.role == .staff || user.role == .outsource {
                        Text("¥\(String(format: "%.0f", user.basePrice))/张")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // 隐藏/显示按钮
            if let onHide = onHide {
                Button {
                    onHide()
                } label: {
                    Image(systemName: user.isHidden ? "eye" : "eye.slash")
                        .foregroundColor(user.isHidden ? .green : .orange)
                }
                .buttonStyle(.plain)
                .help(user.isHidden ? "恢复显示" : "隐藏（离职）")
            }
            
            // 编辑按钮
            if canEdit {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            
            // 删除按钮
            if let onDelete = onDelete {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var roleColor: Color {
        switch user.role {
        case .admin: return .red
        case .subAdmin: return .orange
        case .staff: return .blue
        case .outsource: return .green
        }
    }
}

// MARK: - 编辑用户弹窗

struct EditUserSheet: View {
    let user: User
    let orderManager: OrderManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var basePrice: Double = 8.0
    @State private var groupBonus: Double = 2.0
    @State private var urgentBonus: Double = 5.0
    @State private var complaintBonus: Double = 8.0
    @State private var weddingMultiplier: Double = 0.8
    @State private var colorRed: Double = 0.5
    @State private var colorGreen: Double = 0.5
    @State private var colorBlue: Double = 0.5
    @State private var isSaving: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("账户信息") {
                    TextField("名称（登录 + 显示）", text: $username)
                    SecureField("新密码（留空不修改）", text: $password)
                }
                
                // 后期和外包人员显示绩效配置
                if user.role == .staff || user.role == .outsource {
                    Section("绩效配置") {
                        HStack {
                            Text("基础单价")
                            Spacer()
                            TextField("元/张", value: $basePrice, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        HStack {
                            Text("进群加项")
                            Spacer()
                            TextField("元", value: $groupBonus, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        HStack {
                            Text("加急加项")
                            Spacer()
                            TextField("元", value: $urgentBonus, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        HStack {
                            Text("投诉加项")
                            Spacer()
                            TextField("元", value: $complaintBonus, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        HStack {
                            Text("婚礼系数")
                            Spacer()
                            TextField("系数", value: $weddingMultiplier, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }
                }
                
                Section("日历颜色") {
                    HStack {
                        Circle()
                            .fill(Color(red: colorRed, green: colorGreen, blue: colorBlue))
                            .frame(width: 40, height: 40)
                        
                        VStack {
                            Slider(value: $colorRed, in: 0...1) {
                                Text("红")
                            }
                            Slider(value: $colorGreen, in: 0...1) {
                                Text("绿")
                            }
                            Slider(value: $colorBlue, in: 0...1) {
                                Text("蓝")
                            }
                        }
                    }
                }
            }
            .navigationTitle("编辑用户")
            .onAppear {
                username = user.username
                basePrice = user.basePrice
                groupBonus = user.groupBonus
                urgentBonus = user.urgentBonus
                complaintBonus = user.complaintBonus
                weddingMultiplier = user.weddingMultiplier
                colorRed = user.calendarColorRed
                colorGreen = user.calendarColorGreen
                colorBlue = user.calendarColorBlue
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveChanges()
                    }
                    .disabled(username.isEmpty || isSaving)
                }
            }
        }
        #if os(macOS)
        .frame(width: 450, height: 550)
        #endif
    }
    
    private func saveChanges() {
        isSaving = true
        
        Task {
            do {
                let updateRequest = UpdateUserAPIRequest(
                    username: username,
                    role: nil,
                    password: nil,
                    basePrice: basePrice,
                    groupBonus: groupBonus,
                    urgentBonus: urgentBonus,
                    complaintBonus: complaintBonus,
                    weddingMultiplier: weddingMultiplier,
                    calendarColorRed: colorRed,
                    calendarColorGreen: colorGreen,
                    calendarColorBlue: colorBlue
                )
                
                let _: APIUser = try await APIService.shared.request(
                    endpoint: "/api/users/\(user.id.uuidString)",
                    method: .put,
                    body: updateRequest
                )
                
                await orderManager.loadFromAPI()
                
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                }
                print("保存用户失败: \(error)")
            }
        }
    }
}

// MARK: - 导入数据视图

struct ImportDataView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var orderManager: OrderManager
    
    @State private var selectedFile: URL?
    @State private var isImporting: Bool = false
    @State private var importResult: String?
    @State private var importError: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("导入 Excel 数据")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("支持从腾讯文档导出的 .xlsx 格式文件")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button {
                    selectFile()
                } label: {
                    HStack {
                        Image(systemName: "folder.fill")
                        Text("选择文件")
                    }
                    .padding()
                    .frame(maxWidth: 200)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(isImporting)
                
                if let file = selectedFile {
                    VStack(spacing: 12) {
                        Text("已选择: \(file.lastPathComponent)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button {
                            uploadFile()
                        } label: {
                            HStack {
                                if isImporting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.up.circle.fill")
                                }
                                Text(isImporting ? "导入中..." : "开始导入")
                            }
                            .padding()
                            .frame(maxWidth: 200)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .disabled(isImporting)
                    }
                }
                
                if let result = importResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                }
                
                if let error = importError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("导入数据")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 400)
        #endif
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "xlsx")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "选择要导入的 Excel 文件"
        panel.prompt = "选择"
        
        if panel.runModal() == .OK {
            selectedFile = panel.url
            importResult = nil
            importError = nil
        }
    }
    
    private func uploadFile() {
        guard let fileURL = selectedFile else { return }
        
        isImporting = true
        importResult = nil
        importError = nil
        
        Task {
            do {
                let data = try Data(contentsOf: fileURL)
                let result = try await APIService.shared.importExcel(data: data, filename: fileURL.lastPathComponent)
                
                await MainActor.run {
                    isImporting = false
                    importResult = result
                    
                    // 刷新数据
                    Task {
                        await orderManager.loadFromAPI()
                    }
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - 删除确认 Sheet

struct DeleteConfirmationSheet: View {
    @Binding var isPresented: Bool
    @Binding var confirmText: String
    let onConfirm: () -> Void
    
    @State private var showError: Bool = false
    
    var body: some View {
        VStack(spacing: 24) {
            // 警告图标
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            // 标题和说明
            VStack(spacing: 8) {
                Text("确认删除所有数据？")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("此操作不可撤销！请输入「立即删除」以确认")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // 输入框
            TextField("输入: 立即删除", text: $confirmText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
            
            if showError {
                Text("请输入「立即删除」以确认操作")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            // 按钮
            HStack(spacing: 16) {
                Button("取消") {
                    confirmText = ""
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("确认删除") {
                    if confirmText == "立即删除" {
                        confirmText = ""
                        isPresented = false
                        onConfirm()
                    } else {
                        showError = true
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(32)
        #if os(macOS)
        .frame(width: 400)
        #endif
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
        .environmentObject(SettingsManager())
        .environmentObject(OrderManager())
}
