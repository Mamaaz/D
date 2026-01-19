import SwiftUI
import AppKit

// MARK: - 人员详情视图

struct StaffDetailView: View {
    let staff: User
    let month: Date
    let isAdmin: Bool
    
    @EnvironmentObject var orderManager: OrderManager
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var editedName: String = ""
    @State private var editedRole: UserRole = .staff
    @State private var newPassword: String = ""
    @State private var editedBasePrice: Double = 8.0
    @State private var editedGroupBonus: Double = 2.0
    @State private var editedUrgentBonus: Double = 5.0
    @State private var editedComplaintBonus: Double = 8.0
    @State private var editedWeddingMultiplier: Double = 0.8
    @State private var editedColorRed: Double = 0.5
    @State private var editedColorGreen: Double = 0.5
    @State private var editedColorBlue: Double = 0.5
    @State private var hexColor: String = "#808080" // Hex 色值输入
    
    // 头像选择
    @State private var avatarImage: NSImage?
    @State private var isUploadingAvatar: Bool = false
    @State private var currentAvatarUrl: String?
    
    // 月度绩效配置
    @State private var monthlySalary: Double = 0
    @State private var isSaving: Bool = false
    
    // 删除用户确认
    @State private var showDeleteConfirm: Bool = false
    @State private var isDeleting: Bool = false
    
    private let calendar = Calendar.current
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 头像区域
                    avatarSection
                    
                    Divider()
                    
                    // 基本信息
                    if isAdmin {
                        editableInfoSection
                    } else {
                        readOnlyInfoSection
                    }
                    
                    Divider()
                    
                    // 月度统计
                    monthStatsSection
                    
                    // 管理员专属：月度绩效配置
                    if isAdmin {
                        Divider()
                        performanceConfigSection
                        
                        Divider()
                        costCalculationSection
                        
                        Divider()
                        adminActionsSection
                    }
                }
                .padding()
            }
            .navigationTitle(staff.displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                
                if isAdmin {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            saveChanges()
                        }
                        .disabled(isSaving)
                    }
                }
            }
        }
        .onAppear {
            editedName = staff.username
            editedRole = staff.role
            editedBasePrice = staff.basePrice
            editedGroupBonus = staff.groupBonus
            editedUrgentBonus = staff.urgentBonus
            editedComplaintBonus = staff.complaintBonus
            editedWeddingMultiplier = staff.weddingMultiplier
            editedColorRed = staff.calendarColorRed
            editedColorGreen = staff.calendarColorGreen
            editedColorBlue = staff.calendarColorBlue
            hexColor = rgbToHex(r: staff.calendarColorRed, g: staff.calendarColorGreen, b: staff.calendarColorBlue)
            currentAvatarUrl = staff.avatarUrl
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteUser()
            }
        } message: {
            Text("确定要删除用户「\(staff.displayName)」吗？\n该用户负责的订单将变为未分配状态。")
        }
    }
    
    // MARK: - 头像区域
    
    private var avatarSection: some View {
        VStack(spacing: 12) {
            ZStack {
                // 显示头像图片或默认头像
                if let avatarImage = avatarImage {
                    Image(nsImage: avatarImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                } else if let avatarUrl = currentAvatarUrl, !avatarUrl.isEmpty {
                    AsyncImage(url: URL(string: "\(APIService.shared.baseURL)\(avatarUrl)")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        default:
                            defaultAvatarView
                        }
                    }
                } else {
                    defaultAvatarView
                }
                
                // 上传中指示器
                if isUploadingAvatar {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 100, height: 100)
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            
            if isAdmin {
                Button("更换头像") {
                    selectAvatarFile()
                }
                .font(.caption)
                .disabled(isUploadingAvatar)
            }
        }
    }
    
    private var defaultAvatarView: some View {
        ZStack {
            Circle()
                .fill(Color(red: editedColorRed, green: editedColorGreen, blue: editedColorBlue).opacity(0.3))
                .frame(width: 100, height: 100)
            
            Text(String(staff.displayName.prefix(1)))
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(Color(red: editedColorRed, green: editedColorGreen, blue: editedColorBlue))
        }
    }
    
    // MARK: - 选择头像文件
    
    private func selectAvatarFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "选择头像图片"
        panel.prompt = "选择"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await loadAndUploadImage(from: url)
            }
        }
    }
    
    // MARK: - 头像上传
    
    private func loadAndUploadImage(from url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            guard let image = NSImage(data: data) else { return }
            
            await MainActor.run {
                self.avatarImage = image
                self.isUploadingAvatar = true
            }
            
            // 压缩图片
            let compressedData: Data
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                compressedData = jpegData
            } else {
                compressedData = data
            }
            
            // 上传
            let newAvatarUrl = try await APIService.shared.uploadAvatar(
                userId: staff.id.uuidString,
                imageData: compressedData
            )
            
            await MainActor.run {
                self.currentAvatarUrl = newAvatarUrl
                self.isUploadingAvatar = false
            }
            
            // 刷新数据
            await orderManager.loadFromAPI()
            
        } catch {
            await MainActor.run {
                self.isUploadingAvatar = false
                self.avatarImage = nil
            }
            print("头像上传失败: \(error)")
        }
    }
    
    // MARK: - 可编辑信息
    
    private var editableInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("基本信息")
                .font(.headline)
            
            // 名称（登录 + 显示）
            HStack {
                Text("名称")
                    .foregroundColor(.secondary)
                Spacer()
                TextField("名称", text: $editedName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
            }
            
            // 角色（可编辑）
            HStack {
                Text("角色")
                    .foregroundColor(.secondary)
                Spacer()
                Picker("角色", selection: $editedRole) {
                    Text("后期人员").tag(UserRole.staff)
                    Text("外包人员").tag(UserRole.outsource)
                    Text("副管理员").tag(UserRole.subAdmin)
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            
            // 密码重置
            HStack {
                Text("重置密码")
                    .foregroundColor(.secondary)
                Spacer()
                SecureField("留空不修改", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
            }
            
            Divider()
            Text("绩效配置")
                .font(.headline)
            
            // 基础单价
            HStack {
                Text("基础单价")
                    .foregroundColor(.secondary)
                Spacer()
                TextField("元/张", value: $editedBasePrice, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("元/张")
                    .foregroundColor(.secondary)
            }
            
            // 进群加项
            HStack {
                Text("进群加项")
                    .foregroundColor(.secondary)
                Spacer()
                TextField("元", value: $editedGroupBonus, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("元")
                    .foregroundColor(.secondary)
            }
            
            // 加急加项
            HStack {
                Text("加急加项")
                    .foregroundColor(.secondary)
                Spacer()
                TextField("元", value: $editedUrgentBonus, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("元")
                    .foregroundColor(.secondary)
            }
            
            // 投诉加项
            HStack {
                Text("投诉加项")
                    .foregroundColor(.secondary)
                Spacer()
                TextField("元", value: $editedComplaintBonus, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("元")
                    .foregroundColor(.secondary)
            }
            
            // 婚礼系数
            HStack {
                Text("婚礼系数")
                    .foregroundColor(.secondary)
                Spacer()
                TextField("系数", value: $editedWeddingMultiplier, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
            
            Divider()
            
            // 日历颜色
            VStack(alignment: .leading, spacing: 8) {
                Text("日历颜色")
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    // 预览圆圆
                    Circle()
                        .fill(Color(red: editedColorRed, green: editedColorGreen, blue: editedColorBlue))
                        .frame(width: 40, height: 40)
                    
                    // Hex 色值输入
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("输入颜色 (e.g. #FF5733)", text: $hexColor)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: hexColor) { newValue in
                                if let rgb = hexToRgb(hex: newValue) {
                                    editedColorRed = rgb.r
                                    editedColorGreen = rgb.g
                                    editedColorBlue = rgb.b
                                }
                            }
                        
                        Text("使用 # 开头的六位十六进制颜色值")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - 只读信息
    
    private var readOnlyInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("基本信息")
                .font(.headline)
            
            InfoRowDetail(label: "名称", value: staff.username)
            InfoRowDetail(label: "角色", value: staff.role.displayName)
            InfoRowDetail(label: "基础单价", value: "\(String(format: "%.1f", staff.basePrice)) 元/张")
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - 月度统计
    
    private var monthStatsSection: some View {
        let stats = getMonthStats()
        
        return VStack(alignment: .leading, spacing: 16) {
            Text(ChineseLunarCalendar.formatMonthYear(month) + " 统计")
                .font(.headline)
            
            HStack(spacing: 16) {
                StatBox(title: "订单数", value: "\(stats.orderCount)", color: .blue)
                StatBox(title: "总张数", value: "\(stats.totalPhotos)", color: .green)
                StatBox(title: "已完成", value: "\(stats.completedPhotos)", color: .orange)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - 绩效配置
    
    private var performanceConfigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("月度绩效配置")
                .font(.headline)
            
            HStack {
                Text("工资社保合计")
                    .foregroundColor(.secondary)
                Spacer()
                TextField("金额", value: $monthlySalary, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Text("元")
                    .foregroundColor(.secondary)
            }
            
            // 自动计算的修图绩效
            let performance = calculatePerformance()
            HStack {
                Text("修图绩效")
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.2f 元", performance))
                    .fontWeight(.medium)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - 成本计算
    
    private var costCalculationSection: some View {
        let stats = getMonthStats()
        let performance = calculatePerformance()
        let totalCost = monthlySalary + performance
        let costPerPhoto = stats.completedPhotos > 0 ? totalCost / Double(stats.completedPhotos) : 0
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("成本计算")
                .font(.headline)
            
            HStack {
                Text("计算公式")
                    .foregroundColor(.secondary)
                Spacer()
                Text("(工资社保 + 修图绩效) ÷ 完成张数")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("单张成本")
                Spacer()
                Text(String(format: "%.2f 元/张", costPerPhoto))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(costPerPhoto > 15 ? .red : .green)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - 辅助方法
    
    private func getMonthStats() -> (orderCount: Int, totalPhotos: Int, completedPhotos: Int) {
        let userOrders = orderManager.orders.filter { order in
            guard order.assignedTo == staff.id,
                  let assignedAt = order.assignedAt else { return false }
            return calendar.isDate(assignedAt, equalTo: month, toGranularity: .month)
        }
        
        let orderCount = userOrders.count
        let totalPhotos = userOrders.reduce(0) { $0 + $1.totalCount }
        let completedPhotos = userOrders.filter { $0.isCompleted }.reduce(0) { $0 + $1.totalCount }
        
        return (orderCount, totalPhotos, completedPhotos)
    }
    
    private func calculatePerformance() -> Double {
        let userOrders = orderManager.orders.filter { order in
            guard order.assignedTo == staff.id,
                  order.isCompleted,
                  let completedAt = order.completedAt else { return false }
            return calendar.isDate(completedAt, equalTo: month, toGranularity: .month)
        }
        
        var totalPerformance: Double = 0
        
        for order in userOrders {
            var rate = editedBasePrice
            
            // 婚礼类型
            if order.shootType == .ceremony {
                rate *= editedWeddingMultiplier
            }
            
            // 加项：投诉 > 加急 > 进群
            if order.isComplaint {
                rate += editedComplaintBonus
            } else if order.isUrgent {
                rate += editedUrgentBonus
            } else if order.isInGroup {
                rate += editedGroupBonus
            }
            
            totalPerformance += rate * Double(order.totalCount)
        }
        
        return totalPerformance
    }
    
    private func saveChanges() {
        isSaving = true
        
        Task {
            do {
                let updateRequest = UpdateUserAPIRequest(
                    username: editedName,
                    role: editedRole.rawValue,
                    password: newPassword.isEmpty ? nil : newPassword,
                    basePrice: editedBasePrice,
                    groupBonus: editedGroupBonus,
                    urgentBonus: editedUrgentBonus,
                    complaintBonus: editedComplaintBonus,
                    weddingMultiplier: editedWeddingMultiplier,
                    calendarColorRed: editedColorRed,
                    calendarColorGreen: editedColorGreen,
                    calendarColorBlue: editedColorBlue
                )
                
                let _: APIUser = try await APIService.shared.request(
                    endpoint: "/api/users/\(staff.id.uuidString)",
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
            }
        }
    }
    
    private func deleteUser() {
        isDeleting = true
        
        Task {
            do {
                // 调用 API 删除用户
                try await APIService.shared.deleteUser(id: staff.id)
                
                await orderManager.loadFromAPI()
                
                await MainActor.run {
                    isDeleting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                }
                print("删除用户失败: \(error)")
            }
        }
    }
    
    // MARK: - 管理员操作区域
    
    private var adminActionsSection: some View {
        VStack(spacing: 12) {
            // 删除用户按钮
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Spacer()
                    if isDeleting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "trash.fill")
                        Text("删除此用户")
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .disabled(isDeleting || staff.role == .admin)
            
            if staff.role == .admin {
                Text("主管理员不可删除")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - 更新用户请求

struct UpdateUserAPIRequest: Encodable {
    let username: String?
    let role: String?
    let password: String?
    let basePrice: Double?
    let groupBonus: Double?
    let urgentBonus: Double?
    let complaintBonus: Double?
    let weddingMultiplier: Double?
    let calendarColorRed: Double?
    let calendarColorGreen: Double?
    let calendarColorBlue: Double?
}

// MARK: - 信息行

struct InfoRowDetail: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

// MARK: - Hex/RGB 转换辅助方法

extension StaffDetailView {
    /// RGB 转 Hex
    func rgbToHex(r: Double, g: Double, b: Double) -> String {
        let red = Int(r * 255)
        let green = Int(g * 255)
        let blue = Int(b * 255)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
    
    /// Hex 转 RGB
    func hexToRgb(hex: String) -> (r: Double, g: Double, b: Double)? {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        // 必须是 6 位
        guard hexSanitized.count == 6 else { return nil }
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        return (r, g, b)
    }
}

#Preview {
    let user = User(username: "test", nickname: "测试用户", role: .staff)
    StaffDetailView(staff: user, month: Date(), isAdmin: true)
        .environmentObject(OrderManager())
        .environmentObject(AuthManager())
}
