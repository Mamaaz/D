import SwiftUI
import Charts

// MARK: - 弹窗类型枚举

enum OrderSheetType: Identifiable {
    case pending
    case upcomingDeadline
    case urgent
    case complaint
    case monthlyNew
    case monthlyCompleted
    
    var id: Self { self }
    
    var title: String {
        switch self {
        case .pending: return "待处理订单"
        case .upcomingDeadline: return "即将到期订单"
        case .urgent: return "加急订单"
        case .complaint: return "投诉订单"
        case .monthlyNew: return "本月新增订单"
        case .monthlyCompleted: return "本月完成订单"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var orderManager: OrderManager
    @EnvironmentObject var authManager: AuthManager
    
    // MARK: - 弹窗状态
    @State private var selectedSheetType: OrderSheetType?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 欢迎信息
                welcomeSection
                
                // 今日概览（可点击）
                todayOverviewSection
                
                // 本月统计（可点击）
                monthlyStatsSection
                
                // 近期到期提醒
                upcomingDeadlinesSection
                
                // 年度趋势图（13个月）
                yearlyTrendChartSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("工作台")
        .sheet(item: $selectedSheetType) { sheetType in
            OrdersSheetView(
                title: sheetType.title,
                orders: ordersForSheetType(sheetType)
            )
        }
    }
    
    // MARK: - 欢迎信息
    
    private var welcomeSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(authManager.currentUser?.displayName ?? "用户")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
            
            Spacer()
            
            Text(formattedDate)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<12: return "早上好,"
        case 12..<14: return "中午好,"
        case 14..<18: return "下午好,"
        default: return "晚上好,"
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: Date())
    }
    
    // MARK: - 今日概览（可点击）
    
    private var todayOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日概览")
                .font(.headline)
            
            HStack(spacing: 16) {
                DashboardClickableCard(
                    title: "待处理",
                    value: "\(pendingOrdersCount)",
                    icon: "doc.text.fill",
                    color: .blue
                ) {
                    selectedSheetType = .pending
                }
                
                DashboardClickableCard(
                    title: "即将到期",
                    value: "\(upcomingDeadlineCount)",
                    icon: "clock.fill",
                    color: .orange
                ) {
                    selectedSheetType = .upcomingDeadline
                }
                
                DashboardClickableCard(
                    title: "加急订单",
                    value: "\(urgentOrdersCount)",
                    icon: "exclamationmark.triangle.fill",
                    color: .red
                ) {
                    selectedSheetType = .urgent
                }
                
                DashboardClickableCard(
                    title: "投诉订单",
                    value: "\(complaintOrdersCount)",
                    icon: "flag.fill",
                    color: .purple
                ) {
                    selectedSheetType = .complaint
                }
            }
        }
    }
    
    // MARK: - 本月统计（可点击）
    
    private var monthlyStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本月统计")
                .font(.headline)
            
            HStack(spacing: 16) {
                DashboardClickableStatCard(
                    title: "新增订单",
                    value: "\(monthlyNewOrdersCount)",
                    subtitle: "本月新增",
                    icon: "plus.circle.fill",
                    color: .green
                ) {
                    selectedSheetType = .monthlyNew
                }
                
                DashboardClickableStatCard(
                    title: "完成订单",
                    value: "\(monthlyCompletedOrdersCount)",
                    subtitle: "本月完成",
                    icon: "checkmark.circle.fill",
                    color: .blue
                ) {
                    selectedSheetType = .monthlyCompleted
                }
                
                DashboardClickableStatCard(
                    title: "完成张数",
                    value: "\(monthlyCompletedPhotos)",
                    subtitle: "本月处理",
                    icon: "photo.stack.fill",
                    color: .purple
                ) {
                    selectedSheetType = .monthlyCompleted
                }
            }
        }
    }
    
    // MARK: - 近期到期提醒
    
    private var upcomingDeadlinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("近期到期提醒")
                    .font(.headline)
                
                Spacer()
                
                Text("未来7天")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if upcomingDeadlineOrders.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.green.opacity(0.6))
                        Text("暂无即将到期的订单")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(upcomingDeadlineOrders.prefix(5)) { order in
                        DeadlineReminderRow(order: order)
                    }
                    
                    if upcomingDeadlineOrders.count > 5 {
                        Button {
                            selectedSheetType = .upcomingDeadline
                        } label: {
                            Text("查看全部 \(upcomingDeadlineOrders.count) 个订单")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - 年度趋势图（13个月）
    
    private var yearlyTrendChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("年度完成趋势")
                .font(.headline)
            
            Chart(yearlyData) { item in
                BarMark(
                    x: .value("月份", item.monthLabel),
                    y: .value("张数", item.count)
                )
                .foregroundStyle(item.isCurrentMonth ? Color.accentColor.gradient : Color.gray.opacity(0.5).gradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                }
            }
            .frame(height: 200)
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    // MARK: - 辅助方法
    
    /// 根据 Sheet 类型获取对应订单列表
    private func ordersForSheetType(_ type: OrderSheetType) -> [Order] {
        switch type {
        case .pending:
            return pendingOrders
        case .upcomingDeadline:
            return upcomingDeadlineOrders
        case .urgent:
            return urgentOrders
        case .complaint:
            return complaintOrders
        case .monthlyNew:
            return monthlyNewOrders
        case .monthlyCompleted:
            return monthlyCompletedOrders
        }
    }
    
    // MARK: - 计算属性
    
    private var activeOrders: [Order] {
        orderManager.filteredOrders.filter { !$0.isArchived }
    }
    
    // 今日概览数据
    private var pendingOrders: [Order] {
        activeOrders.filter { !$0.isCompleted }
    }
    
    private var pendingOrdersCount: Int { pendingOrders.count }
    
    private var upcomingDeadlineOrders: [Order] {
        let sevenDaysLater = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return activeOrders.filter { order in
            guard !order.isCompleted, let deadline = order.finalDeadline else { return false }
            return deadline <= sevenDaysLater && deadline >= Date()
        }.sorted { ($0.finalDeadline ?? Date()) < ($1.finalDeadline ?? Date()) }
    }
    
    private var upcomingDeadlineCount: Int {
        let threeDaysLater = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        return activeOrders.filter { order in
            guard !order.isCompleted, let deadline = order.finalDeadline else { return false }
            return deadline <= threeDaysLater && deadline >= Date()
        }.count
    }
    
    private var urgentOrders: [Order] {
        activeOrders.filter { $0.isUrgent && !$0.isCompleted }
    }
    
    private var urgentOrdersCount: Int { urgentOrders.count }
    
    private var complaintOrders: [Order] {
        activeOrders.filter { $0.isComplaint && !$0.isCompleted }
    }
    
    private var complaintOrdersCount: Int { complaintOrders.count }
    
    // 本月统计数据
    private var currentMonthStart: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    }
    
    private var monthlyNewOrders: [Order] {
        orderManager.filteredOrders.filter { $0.createdAt >= currentMonthStart }
    }
    
    private var monthlyNewOrdersCount: Int { monthlyNewOrders.count }
    
    private var monthlyCompletedOrders: [Order] {
        orderManager.filteredOrders.filter { order in
            guard let completedAt = order.completedAt else { return false }
            return completedAt >= currentMonthStart
        }
    }
    
    private var monthlyCompletedOrdersCount: Int { monthlyCompletedOrders.count }
    
    private var monthlyCompletedPhotos: Int {
        monthlyCompletedOrders.reduce(0) { $0 + $1.totalCount + $1.extraCount }
    }
    
    // 年度趋势数据（13个月，当前月居中）
    private var yearlyData: [MonthlyData] {
        let calendar = Calendar.current
        var data: [MonthlyData] = []
        
        // 当前月居中，左右各6个月，共13个月
        for offset in -6...6 {
            guard let targetDate = calendar.date(byAdding: .month, value: offset, to: Date()) else { continue }
            
            let components = calendar.dateComponents([.year, .month], from: targetDate)
            guard let monthStart = calendar.date(from: components),
                  let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { continue }
            
            // 计算该月完成张数
            let completedPhotos = orderManager.filteredOrders
                .filter { order in
                    guard let completedAt = order.completedAt else { return false }
                    return completedAt >= monthStart && completedAt < monthEnd
                }
                .reduce(0) { $0 + $1.totalCount + $1.extraCount }
            
            // 月份标签
            let formatter = DateFormatter()
            formatter.dateFormat = "M月"
            let label = formatter.string(from: targetDate)
            
            data.append(MonthlyData(
                monthLabel: label,
                count: completedPhotos,
                isCurrentMonth: offset == 0
            ))
        }
        
        return data
    }
}

// MARK: - 月度数据模型

struct MonthlyData: Identifiable {
    let id = UUID()
    let monthLabel: String
    let count: Int
    let isCurrentMonth: Bool
}

// MARK: - 可点击概览卡片

struct DashboardClickableCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.15))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 可点击统计卡片

struct DashboardClickableStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(color)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 到期提醒行

struct DeadlineReminderRow: View {
    let order: Order
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var orderManager: OrderManager
    
    private var daysRemaining: Int {
        guard let deadline = order.finalDeadline else { return 0 }
        return Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
    }
    
    private var urgencyColor: Color {
        if daysRemaining <= 1 { return .red }
        if daysRemaining <= 3 { return .orange }
        return .green
    }
    
    /// 格式化日期为中文格式（如：2025年9月7日）
    private func formatChineseDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }
    
    /// 获取后期人员信息（名称和颜色）
    private var assigneeInfo: (name: String, color: Color)? {
        guard let assignedTo = order.assignedTo else { return nil }
        
        // 从 staffList 查找用户
        if let staff = orderManager.staffList.first(where: { $0.id == assignedTo }) {
            let staffColor = Color(red: staff.calendarColorRed, green: staff.calendarColorGreen, blue: staff.calendarColorBlue)
            return (staff.displayName, staffColor)
        }
        
        // 如果是当前用户
        if assignedTo == authManager.currentUser?.id, let user = authManager.currentUser {
            let userColor = Color(red: user.calendarColorRed, green: user.calendarColorGreen, blue: user.calendarColorBlue)
            return (user.nickname, userColor)
        }
        
        // 回退到 API 返回的名称
        if let name = order.assignedUserName, !name.isEmpty {
            return (name, .blue)
        }
        
        return nil
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 天数指示
            VStack {
                Text("\(daysRemaining)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(urgencyColor)
                Text("天")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(order.orderNumber)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let info = assigneeInfo {
                        Text(info.name)
                            .font(.caption)
                            .foregroundColor(info.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(info.color.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(order.shootLocation)
                    Text("·")
                    Text("\(order.totalCount)张")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let deadline = order.finalDeadline {
                Text(formatChineseDate(deadline))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 订单列表弹窗

struct OrdersSheetView: View {
    let title: String
    let orders: [Order]
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(title)
                    .font(.headline)
                
                Spacer()
                
                Text("\(orders.count) 个订单")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding()
            
            Divider()
            
            if orders.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("暂无订单")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(orders) { order in
                    SheetOrderRow(order: order)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - 弹窗订单行

struct SheetOrderRow: View {
    let order: Order
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var orderManager: OrderManager
    
    @State private var showDetail = false
    
    /// 获取后期人员信息（名称和颜色）
    private var assigneeInfo: (name: String, color: Color)? {
        guard let assignedTo = order.assignedTo else { return nil }
        
        // 从 staffList 查找用户
        if let staff = orderManager.staffList.first(where: { $0.id == assignedTo }) {
            let staffColor = Color(red: staff.calendarColorRed, green: staff.calendarColorGreen, blue: staff.calendarColorBlue)
            return (staff.displayName, staffColor)
        }
        
        // 如果是当前用户
        if assignedTo == authManager.currentUser?.id, let user = authManager.currentUser {
            let userColor = Color(red: user.calendarColorRed, green: user.calendarColorGreen, blue: user.calendarColorBlue)
            return (user.nickname, userColor)
        }
        
        // 回退到 API 返回的名称
        if let name = order.assignedUserName, !name.isEmpty {
            return (name, .blue)
        }
        
        return nil
    }
    
    /// 格式化日期为中文格式（如：2025年9月7日）
    private func formatChineseDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }
    
    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(order.orderNumber)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if let info = assigneeInfo {
                            Text(info.name)
                                .font(.caption)
                                .foregroundColor(info.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(info.color.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text(order.shootLocation)
                        Text("·")
                        Text("\(order.totalCount)张")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let deadline = order.finalDeadline {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("截止")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatChineseDate(deadline))
                            .font(.caption)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            OrderDetailView(order: order)
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(OrderManager())
        .environmentObject(AuthManager())
}
