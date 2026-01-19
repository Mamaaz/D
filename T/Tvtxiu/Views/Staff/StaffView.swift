import SwiftUI

// MARK: - 团队视图

struct StaffView: View {
    @EnvironmentObject var orderManager: OrderManager
    @EnvironmentObject var authManager: AuthManager
    
    @State private var selectedStaff: User?
    @State private var showStaffDetail: Bool = false
    @State private var selectedMonth: Date = Date()
    @State private var showAddUser: Bool = false
    @State private var selectedRoleTab: UserRole = .admin // 角色标签页选择
    @State private var showHiddenStaff: Bool = false // 显示离职人员
    
    private let calendar = Calendar.current
    
    var body: some View {
        Group {
            if authManager.hasAdminPrivilege {
                // 管理员视图：显示所有人员
                adminView
            } else {
                // 普通用户视图：只显示自己
                staffPersonalView
            }
        }
    }
    
    // MARK: - 管理员视图
    
    private var adminView: some View {
        VStack(spacing: 0) {
            // 顶部标题
            HStack {
                Text("团队管理")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // 月份选择
                monthPicker
            }
            .padding()
            
            Divider()
            
            // 角色标签页
            Picker("角色", selection: $selectedRoleTab) {
                Text("主管理 (\(staffCount(for: .admin)))").tag(UserRole.admin)
                Text("副管理 (\(staffCount(for: .subAdmin)))").tag(UserRole.subAdmin)
                Text("后期人员 (\(staffCount(for: .staff)))").tag(UserRole.staff)
                Text("外包 (\(staffCount(for: .outsource)))").tag(UserRole.outsource)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // 离职人员提示
            if !hiddenStaff.isEmpty {
                Button {
                    showHiddenStaff.toggle()
                } label: {
                    HStack {
                        Image(systemName: showHiddenStaff ? "eye.slash.fill" : "eye.slash")
                        Text("离职人员 (\(hiddenStaff.count))")
                        Spacer()
                        Image(systemName: showHiddenStaff ? "chevron.up" : "chevron.down")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // 当前角色的人员卡片
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 280, maximum: 350), spacing: 16)
                ], spacing: 16) {
                    ForEach(filteredStaffByRole) { staff in
                        StaffCardView(
                            staff: staff,
                            allTimeStats: getAllTimeStats(for: staff),
                            isHidden: false,
                            onHide: { hideUser(staff) }
                        ) {
                            selectedStaff = staff
                        }
                    }
                    
                    // 当前角色的添加用户卡片
                    AddUserCard(role: selectedRoleTab) {
                        showAddUser = true
                    }
                }
                .padding()
                
                // 离职人员区域
                if showHiddenStaff && !hiddenStaff.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("离职人员")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 280, maximum: 350), spacing: 16)
                        ], spacing: 16) {
                            ForEach(hiddenStaff) { staff in
                                StaffCardView(
                                    staff: staff,
                                    allTimeStats: getAllTimeStats(for: staff),
                                    isHidden: true,
                                    onHide: { unhideUser(staff) }
                                ) {
                                    selectedStaff = staff
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                }
            }
        }
        .sheet(item: $selectedStaff) { staff in
            StaffDetailView(staff: staff, month: selectedMonth, isAdmin: true)
                .environmentObject(orderManager)
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showAddUser) {
            AddUserSheet()
                .environmentObject(orderManager)
        }
    }
    
    // MARK: - 普通用户视图
    
    private var staffPersonalView: some View {
        VStack(spacing: 0) {
            // 顶部标题
            HStack {
                Text("我的信息")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // 月份选择
                monthPicker
            }
            .padding()
            
            Divider()
            
            if let currentUser = authManager.currentUser {
                ScrollView {
                    VStack(spacing: 20) {
                        // 个人信息卡片
                        personalInfoCard(for: currentUser)
                        
                        // 本月统计
                        monthStatsCard(for: currentUser)
                        
                        // 月度趋势
                        monthlyTrendCard(for: currentUser)
                    }
                    .padding()
                }
            } else {
                Text("无法获取用户信息")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - 月份选择器
    
    private var monthPicker: some View {
        HStack(spacing: 8) {
            Button {
                selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            
            Text(ChineseLunarCalendar.formatMonthYear(selectedMonth))
                .font(.subheadline)
                .fontWeight(.medium)
            
            Button {
                selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - 个人信息卡片
    
    private func personalInfoCard(for user: User) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // 头像
                staffAvatar(for: user, size: 80)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(user.role.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: user.calendarColorRed, green: user.calendarColorGreen, blue: user.calendarColorBlue))
                            .frame(width: 12, height: 12)
                        Text("日历颜色")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - 月度统计卡片
    
    private func monthStatsCard(for user: User) -> some View {
        let stats = getMonthStats(for: user)
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("本月统计")
                .font(.headline)
            
            HStack(spacing: 20) {
                StatBox(title: "订单数", value: "\(stats.orderCount)", color: .blue)
                StatBox(title: "总张数", value: "\(stats.totalPhotos)", color: .green)
                StatBox(title: "已完成", value: "\(stats.completedPhotos)", color: .orange)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - 月度趋势卡片
    
    private func monthlyTrendCard(for user: User) -> some View {
        let trendData = getMonthlyTrend(for: user)
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("近6个月趋势")
                .font(.headline)
            
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(trendData, id: \.month) { item in
                    VStack(spacing: 4) {
                        Text("\(item.photos)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue)
                            .frame(width: 30, height: max(CGFloat(item.photos) / CGFloat(max(trendData.map { $0.photos }.max() ?? 1, 1)) * 100, 4))
                        
                        Text(item.monthLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 140)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - 头像
    
    private func staffAvatar(for user: User, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(red: user.calendarColorRed, green: user.calendarColorGreen, blue: user.calendarColorBlue).opacity(0.3))
                .frame(width: size, height: size)
            
            Text(String(user.displayName.prefix(1)))
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(Color(red: user.calendarColorRed, green: user.calendarColorGreen, blue: user.calendarColorBlue))
        }
    }
    
    // MARK: - 数据计算
    
    /// 根据选中的角色标签过滤人员（按姓名排序，排除隐藏用户）
    private var filteredStaffByRole: [User] {
        orderManager.staffList
            .filter { $0.role == selectedRoleTab && !$0.isHidden }
            .sorted { $0.displayName < $1.displayName }
    }
    
    /// 获取隐藏（离职）的人员
    private var hiddenStaff: [User] {
        orderManager.staffList
            .filter { $0.isHidden }
            .sorted { $0.displayName < $1.displayName }
    }
    
    /// 获取指定角色的人数（排除隐藏用户）
    private func staffCount(for role: UserRole) -> Int {
        orderManager.staffList.filter { $0.role == role && !$0.isHidden }.count
    }
    
    private func getMonthStats(for user: User) -> (orderCount: Int, totalPhotos: Int, completedPhotos: Int) {
        let userOrders = orderManager.orders.filter { order in
            guard order.assignedTo == user.id,
                  let assignedAt = order.assignedAt else { return false }
            return calendar.isDate(assignedAt, equalTo: selectedMonth, toGranularity: .month)
        }
        
        let orderCount = userOrders.count
        let totalPhotos = userOrders.reduce(0) { $0 + $1.totalCount }
        let completedPhotos = userOrders.filter { $0.isCompleted }.reduce(0) { $0 + $1.totalCount }
        
        return (orderCount, totalPhotos, completedPhotos)
    }
    
    /// 获取用户累计统计（所有时间）
    private func getAllTimeStats(for user: User) -> (orderCount: Int, totalPhotos: Int, completedPhotos: Int) {
        let userOrders = orderManager.orders.filter { order in
            order.assignedTo == user.id
        }
        
        let orderCount = userOrders.count
        let totalPhotos = userOrders.reduce(0) { $0 + $1.totalCount }
        let completedPhotos = userOrders.filter { $0.isCompleted }.reduce(0) { $0 + $1.totalCount }
        
        return (orderCount, totalPhotos, completedPhotos)
    }
    
    private func getMonthlyTrend(for user: User) -> [(month: Date, photos: Int, monthLabel: String)] {
        var result: [(month: Date, photos: Int, monthLabel: String)] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M月"
        
        for i in (0..<6).reversed() {
            guard let month = calendar.date(byAdding: .month, value: -i, to: Date()) else { continue }
            
            let photos = orderManager.orders.filter { order in
                guard order.assignedTo == user.id,
                      order.isCompleted,
                      let completedAt = order.completedAt else { return false }
                return calendar.isDate(completedAt, equalTo: month, toGranularity: .month)
            }.reduce(0) { $0 + $1.totalCount }
            
            result.append((month: month, photos: photos, monthLabel: dateFormatter.string(from: month)))
        }
        
        return result
    }
    
    // MARK: - 用户操作
    
    /// 隐藏用户（离职）
    private func hideUser(_ user: User) {
        Task {
            do {
                let updatedUser = try await UserService.shared.hideUser(id: user.id)
                if let index = orderManager.staffList.firstIndex(where: { $0.id == user.id }) {
                    orderManager.staffList[index] = updatedUser
                }
                ToastManager.shared.success("已标记离职", message: "\(user.displayName) 已移至离职人员")
            } catch {
                ToastManager.shared.error("操作失败", message: error.localizedDescription)
            }
        }
    }
    
    /// 取消隐藏用户
    private func unhideUser(_ user: User) {
        Task {
            do {
                let updatedUser = try await UserService.shared.unhideUser(id: user.id)
                if let index = orderManager.staffList.firstIndex(where: { $0.id == user.id }) {
                    orderManager.staffList[index] = updatedUser
                }
                ToastManager.shared.success("已恢复", message: "\(user.displayName) 已恢复为在职状态")
            } catch {
                ToastManager.shared.error("操作失败", message: error.localizedDescription)
            }
        }
    }
}

// MARK: - 人员卡片视图

struct StaffCardView: View {
    let staff: User
    let allTimeStats: (orderCount: Int, totalPhotos: Int, completedPhotos: Int)
    var isHidden: Bool = false
    var onHide: (() -> Void)? = nil
    let action: () -> Void
    
    private var staffColor: Color {
        Color(red: staff.calendarColorRed, green: staff.calendarColorGreen, blue: staff.calendarColorBlue)
    }
    
    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(staffColor.opacity(0.2))
                .frame(width: 60, height: 60)
            
            Text(String(staff.displayName.prefix(1)))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(staffColor)
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                // 顶部：头像和基本信息
                HStack(spacing: 16) {
                    // 头像
                    Group {
                        if let avatarUrl = staff.avatarUrl, !avatarUrl.isEmpty {
                            AsyncImage(url: URL(string: "\(APIService.shared.baseURL)\(avatarUrl)")) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .clipShape(Circle())
                                case .failure(_), .empty:
                                    avatarFallback
                                @unknown default:
                                    avatarFallback
                                }
                            }
                        } else {
                            avatarFallback
                        }
                    }
                    .opacity(isHidden ? 0.5 : 1.0)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(staff.displayName)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(isHidden ? .secondary : .primary)
                            
                            // 离职标识
                            if isHidden {
                                Text("离职")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.3))
                                    .foregroundColor(.gray)
                                    .cornerRadius(4)
                            }
                        }
                        
                        HStack(spacing: 8) {
                            Text(staff.role.displayName)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(staffColor.opacity(0.15))
                                .foregroundColor(staffColor)
                                .cornerRadius(6)
                            
                            // 外包标识
                            if staff.role == .outsource {
                                Image(systemName: "person.badge.shield.checkmark.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            
                            Circle()
                                .fill(staffColor)
                                .frame(width: 10, height: 10)
                        }
                    }
                    
                    Spacer()
                    
                    // 隐藏/显示按钮
                    if let onHide = onHide {
                        Button {
                            onHide()
                        } label: {
                            Image(systemName: isHidden ? "eye" : "eye.slash")
                                .font(.title3)
                                .foregroundColor(isHidden ? .green : .orange)
                        }
                        .buttonStyle(.plain)
                        .help(isHidden ? "恢复显示" : "标记为离职")
                    }
                }
                
                Divider()
                
                // 底部：累计统计数据
                HStack(spacing: 0) {
                    StatItem(value: "\(allTimeStats.orderCount)", label: "订单", color: .blue)
                    StatItem(value: "\(allTimeStats.totalPhotos)", label: "总张", color: .green)
                    StatItem(value: "\(allTimeStats.completedPhotos)", label: "完成", color: .orange)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(isHidden ? 0.1 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(staffColor.opacity(isHidden ? 0.15 : 0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 统计项

struct StatItem: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 人员行视图（保留用于其他场景）

struct StaffRowView: View {
    let staff: User
    let monthStats: (orderCount: Int, totalPhotos: Int, completedPhotos: Int)
    let isAdmin: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // 头像
                ZStack {
                    Circle()
                        .fill(Color(red: staff.calendarColorRed, green: staff.calendarColorGreen, blue: staff.calendarColorBlue).opacity(0.3))
                        .frame(width: 50, height: 50)
                    
                    Text(String(staff.displayName.prefix(1)))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(red: staff.calendarColorRed, green: staff.calendarColorGreen, blue: staff.calendarColorBlue))
                }
                
                // 信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(staff.displayName)
                            .font(.headline)
                        
                        Text(staff.role.displayName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        
                        // 外包标识
                        if staff.role == .outsource {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Label("\(monthStats.orderCount) 单", systemImage: "doc.text")
                        Label("\(monthStats.totalPhotos) 张", systemImage: "photo")
                        Label("\(monthStats.completedPhotos) 完成", systemImage: "checkmark.circle")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 箭头
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 统计框

struct StatBox: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - 添加用户卡片

struct AddUserCard: View {
    let role: UserRole
    let onTap: () -> Void
    
    private var roleText: String {
        switch role {
        case .admin: return "添加主管理"
        case .subAdmin: return "添加副管理"
        case .staff: return "添加后期人员"
        case .outsource: return "添加外包"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text(roleText)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 添加用户表单

struct AddUserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var orderManager: OrderManager
    
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var role: UserRole = .staff
    @State private var basePrice: Double = 8.0
    @State private var isSaving: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("账户信息") {
                    TextField("用户名（登录+显示）", text: $username)
                    SecureField("密码", text: $password)
                }
                
                Section("角色类型") {
                    Picker("角色", selection: $role) {
                        Text("后期人员").tag(UserRole.staff)
                        Text("外包人员").tag(UserRole.outsource)
                        Text("副管理员").tag(UserRole.subAdmin)
                    }
                    .pickerStyle(.menu)
                    
                    if role == .staff || role == .outsource {
                        HStack {
                            Text("基础单价")
                            Spacer()
                            TextField("元/张", value: $basePrice, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("添加用户")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        createUser()
                    }
                    .disabled(username.isEmpty || password.isEmpty || isSaving)
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 350)
        #endif
    }
    
    private func createUser() {
        isSaving = true
        
        Task {
            do {
                let request = CreateUserAPIRequest(
                    username: username,
                    password: password,
                    role: role.rawValue,
                    basePrice: basePrice
                )
                
                let _: APIUser = try await APIService.shared.request(
                    endpoint: "/api/users",
                    method: .post,
                    body: request
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
                print("创建用户失败: \(error)")
            }
        }
    }
}

struct CreateUserAPIRequest: Encodable {
    let username: String
    let password: String
    let role: String
    let basePrice: Double
}

#Preview {
    StaffView()
        .environmentObject(OrderManager())
        .environmentObject(AuthManager())
}
