import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var orderManager: OrderManager
    @EnvironmentObject var authManager: AuthManager
    
    @State private var selectedMonth: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }()
    
    // 年度趋势图的年份选择
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showYearComparison: Bool = false
    
    // 完成张数图表状态
    @State private var showPhotosExpanded: Bool = false
    @State private var showPhotosYearComparison: Bool = false
    
    // 模块折叠状态
    @State private var isOverviewCollapsed: Bool = false
    @State private var isRankingCollapsed: Bool = false
    @State private var isTrendChartCollapsed: Bool = false
    @State private var isPhotosChartCollapsed: Bool = false
    @State private var isDetailTableCollapsed: Bool = false
    
    // 管理员标签切换（订单统计 vs 拍摄统计）
    @State private var selectedStatsTab: StatsTab = .order
    
    enum StatsTab: String, CaseIterable {
        case order = "订单统计"
        case shooting = "拍摄统计"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 管理员标签切换器
            if authManager.hasAdminPrivilege {
                statsTabPicker
            }
            
            // 根据选中的标签显示内容
            if authManager.hasAdminPrivilege && selectedStatsTab == .shooting {
                ShootingStatsView()
            } else {
                orderStatsContent
            }
        }
    }
    
    // MARK: - 标签切换器
    
    private var statsTabPicker: some View {
        Picker("统计类型", selection: $selectedStatsTab) {
            ForEach(StatsTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 300)
        .padding()
    }
    
    // MARK: - 订单统计内容
    
    private var orderStatsContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 概览卡片 (根据权限显示不同内容)
                overviewCards
                
                // 完成张数排行榜 (所有人可见)
                completedPhotosRanking
                
                // 月度趋势 (根据权限显示不同数据)
                monthlyTrendChart
                
                // 月度完成张数图表（新增）
                monthlyPhotosChart
                
                // 详细表格 (仅管理员可见)
                if authManager.hasAdminPrivilege {
                    filterSection
                    detailTable
                }
            }
            .padding()
        }
    }
    
    // MARK: - 概览卡片
    
    private var overviewCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 可折叠头部
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isOverviewCollapsed.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isOverviewCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("本月概览")
                        .font(.headline)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if !isOverviewCollapsed {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    OverviewCard(
                        title: myStatsPrefix + "订单",
                        value: "\(myOrdersThisMonth.count)",
                        icon: "doc.text.fill",
                        color: .blue
                    )
                    
                    OverviewCard(
                        title: myStatsPrefix + "张数",
                        value: "\(myOrdersThisMonth.reduce(0) { $0 + $1.totalCount })",
                        icon: "photo.stack.fill",
                        color: .purple
                    )
                    
                    OverviewCard(
                        title: "已完成",
                        value: "\(myOrdersThisMonth.filter { $0.isCompleted }.count)",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    
                    OverviewCard(
                        title: "完成率",
                        value: myCompletionRate,
                        icon: "chart.pie.fill",
                        color: .orange
                    )
                    
                    // 投诉完成张数
                    OverviewCard(
                        title: "投诉完成",
                        value: "\(complaintCompletedPhotos)",
                        icon: "exclamationmark.triangle.fill",
                        color: Color(red: 0.6, green: 0.1, blue: 0.1)
                    )
                }
            }
        }
    }
    
    // MARK: - 完成张数排行榜 (所有人可见)
    
    private var completedPhotosRanking: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 可折叠头部
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isRankingCollapsed.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isRankingCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("🏆 完成张数排行榜")
                        .font(.headline)
                    
                    Spacer()
                    
                    Picker("", selection: $selectedMonth) {
                        ForEach(availableMonths, id: \.self) { month in
                            Text(formatMonth(month)).tag(month)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if !isRankingCollapsed {
                rankingList
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var rankingHeader: some View {
        HStack {
            Text("🏆 完成张数排行榜")
                .font(.headline)
            
            Spacer()
            
            Picker("", selection: $selectedMonth) {
                ForEach(availableMonths, id: \.self) { month in
                    Text(formatMonth(month)).tag(month)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
        }
    }
    
    private var rankingList: some View {
        VStack(spacing: 0) {
            ForEach(completedPhotosRankingData.indices, id: \.self) { index in
                let stat = completedPhotosRankingData[index]
                let isMe = isCurrentUser(stat.staff)
                
                RankingRowView(
                    index: index,
                    stat: stat,
                    isCurrentUser: isMe,
                    totalCount: completedPhotosRankingData.count
                )
            }
        }
        .background(Color.gray.opacity(0.02))
        .cornerRadius(12)
    }
    
    // MARK: - 月度趋势图表（增强版）
    
    private var monthlyTrendChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 可折叠头部
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isTrendChartCollapsed.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isTrendChartCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(authManager.hasAdminPrivilege ? "月度订单趋势" : "我的月度趋势")
                        .font(.headline)
                    
                    Spacer()
                    
                    if !isTrendChartCollapsed {
                        // 对比上年开关
                        Toggle(isOn: $showYearComparison) {
                            Text("\(selectedYear - 1)")
                                .font(.caption)
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .tint(showYearComparison ? .blue : .gray)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if !isTrendChartCollapsed {
            
            // 年份选择器
            HStack {
                Button {
                    selectedYear -= 1
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                
                Text("\(String(selectedYear))年")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(minWidth: 80)
                
                Button {
                    if selectedYear < Calendar.current.component(.year, from: Date()) {
                        selectedYear += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(selectedYear >= Calendar.current.component(.year, from: Date()))
                
                Spacer()
            }
            
            // 图表
            Chart {
                ForEach(yearlyOrderTrendData, id: \.month) { stat in
                    LineMark(
                        x: .value("月份", stat.monthLabel),
                        y: .value("订单数", stat.orderCount)
                    )
                    .foregroundStyle(.blue)
                    .symbol(.circle)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    
                    PointMark(
                        x: .value("月份", stat.monthLabel),
                        y: .value("订单数", stat.orderCount)
                    )
                    .foregroundStyle(stat.isCurrentMonth ? .orange : .blue)
                    .symbolSize(stat.isCurrentMonth ? 80 : 40)
                }
                
                // 上年对比线（虚线）
                if showYearComparison {
                    ForEach(lastYearOrderTrendData, id: \.month) { stat in
                        LineMark(
                            x: .value("月份", stat.monthLabel),
                            y: .value("订单数", stat.orderCount)
                        )
                        .foregroundStyle(.gray.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 200)
            
            // 图例
            if showYearComparison {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle().fill(.blue).frame(width: 8, height: 8)
                        Text("\(String(selectedYear))年").font(.caption)
                    }
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(.gray.opacity(0.6))
                            .frame(width: 16, height: 2)
                        Text("\(String(selectedYear - 1))年").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            } // 结束 if !isTrendChartCollapsed
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - 月度完成张数图表（新增）
    
    private var monthlyPhotosChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 可折叠头部
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPhotosChartCollapsed.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isPhotosChartCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("月度完成张数")
                        .font(.headline)
                    
                    Spacer()
                    
                    if !isPhotosChartCollapsed {
                        // 展开/收起按钮（仅管理员）
                        if authManager.hasAdminPrivilege {
                            Button {
                                withAnimation {
                                    showPhotosExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: showPhotosExpanded ? "person.3.fill" : "person.fill")
                                    Text(showPhotosExpanded ? "收起" : "展开")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        // 对比上年开关
                        Toggle(isOn: $showPhotosYearComparison) {
                            Text("\(selectedYear - 1)")
                                .font(.caption)
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .tint(showPhotosYearComparison ? .green : .gray)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if !isPhotosChartCollapsed {
            
            // 图表
            Chart {
                if showPhotosExpanded && authManager.hasAdminPrivilege {
                    // 展开模式：显示每个人的线
                    ForEach(orderManager.staffList) { staff in
                        let staffData = generateStaffPhotosData(for: staff, year: selectedYear)
                        let staffColor = Color(red: staff.calendarColorRed, green: staff.calendarColorGreen, blue: staff.calendarColorBlue)
                        
                        ForEach(staffData) { stat in
                            LineMark(
                                x: .value("月份", stat.monthLabel),
                                y: .value("张数", stat.completedPhotos),
                                series: .value("人员", staff.displayName)
                            )
                            .foregroundStyle(staffColor)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                } else {
                    // 默认模式：显示总数
                    ForEach(yearlyPhotosData, id: \.month) { stat in
                        LineMark(
                            x: .value("月份", stat.monthLabel),
                            y: .value("张数", stat.completedPhotos)
                        )
                        .foregroundStyle(.green)
                        .symbol(.circle)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        
                        PointMark(
                            x: .value("月份", stat.monthLabel),
                            y: .value("张数", stat.completedPhotos)
                        )
                        .foregroundStyle(stat.isCurrentMonth ? .orange : .green)
                        .symbolSize(stat.isCurrentMonth ? 80 : 40)
                    }
                }
                
                // 上年对比线（虚线）
                if showPhotosYearComparison && !showPhotosExpanded {
                    ForEach(lastYearPhotosData, id: \.month) { stat in
                        LineMark(
                            x: .value("月份", stat.monthLabel),
                            y: .value("张数", stat.completedPhotos)
                        )
                        .foregroundStyle(.gray.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel()
                }
            }
            .frame(height: showPhotosExpanded ? 300 : 200)
            
            // 图例
            if showPhotosExpanded && authManager.hasAdminPrivilege {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(orderManager.staffList) { staff in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(red: staff.calendarColorRed, green: staff.calendarColorGreen, blue: staff.calendarColorBlue))
                                    .frame(width: 8, height: 8)
                                Text(staff.displayName)
                                    .font(.caption)
                            }
                        }
                    }
                }
            } else if showPhotosYearComparison {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("\(String(selectedYear))年").font(.caption)
                    }
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(.gray.opacity(0.6))
                            .frame(width: 16, height: 2)
                        Text("\(String(selectedYear - 1))年").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            } // 结束 if !isPhotosChartCollapsed
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - 筛选器 (仅管理员)
    
    private var filterSection: some View {
        HStack {
            Text("详细统计")
                .font(.headline)
            
            Spacer()
            
            Button {
                // 导出功能
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - 详细表格 (仅管理员)
    
    private var detailTable: some View {
        VStack(spacing: 0) {
            // 表头
            HStack {
                Text("人员")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("订单数")
                    .frame(width: 70)
                Text("总张数")
                    .frame(width: 70)
                Text("已完成")
                    .frame(width: 70)
                Text("完成张数")
                    .frame(width: 80)
                Text("投诉完成")
                    .frame(width: 80)
                Text("完成率")
                    .frame(width: 70)
            }
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .padding()
            .background(Color.gray.opacity(0.1))
            
            // 数据行
            ForEach(allStaffStats, id: \.staff.id) { stat in
                HStack {
                    HStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(String(stat.staff.displayName.prefix(1)))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            )
                        Text(stat.staff.displayName)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("\(stat.orderCount)")
                        .frame(width: 70)
                    
                    Text("\(stat.totalPhotos)")
                        .frame(width: 70)
                    
                    Text("\(stat.completedCount)")
                        .frame(width: 70)
                    
                    Text("\(stat.completedPhotos)")
                        .foregroundColor(.green)
                        .frame(width: 80)
                    
                    Text("\(stat.complaintPhotos)")
                        .foregroundColor(stat.complaintPhotos > 0 ? Color(red: 0.6, green: 0.1, blue: 0.1) : .secondary)
                        .frame(width: 80)
                    
                    Text(stat.completionRate)
                        .foregroundColor(stat.completedCount == stat.orderCount && stat.orderCount > 0 ? .green : .primary)
                        .frame(width: 70)
                }
                .font(.subheadline)
                .padding()
                
                Divider()
            }
        }
        .background(Color.gray.opacity(0.02))
        .cornerRadius(12)
    }
    
    // MARK: - 数据计算
    
    private var myStatsPrefix: String {
        authManager.hasAdminPrivilege ? "本月" : "我的"
    }
    
    private var myOrdersThisMonth: [Order] {
        let monthOrders = orderManager.orders.filter { $0.assignedMonth == selectedMonth }
        
        if authManager.hasAdminPrivilege {
            return monthOrders
        } else {
            // 普通用户只看自己的
            return monthOrders.filter { $0.assignedTo == authManager.currentUser?.id }
        }
    }
    
    private var myCompletionRate: String {
        guard !myOrdersThisMonth.isEmpty else { return "0%" }
        let rate = Double(myOrdersThisMonth.filter { $0.isCompleted }.count) / Double(myOrdersThisMonth.count) * 100
        return String(format: "%.0f%%", rate)
    }
    
    /// 投诉完成张数 (被标记投诉且已完成的订单总张数)
    private var complaintCompletedPhotos: Int {
        let orders = authManager.hasAdminPrivilege
            ? orderManager.orders
            : orderManager.orders.filter { $0.assignedTo == authManager.currentUser?.id }
        
        return orders
            .filter { $0.isComplaint && $0.isCompleted && $0.assignedMonth == selectedMonth }
            .reduce(0) { $0 + $1.totalCount }
    }
    
    private var availableMonths: [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        
        var months: Set<String> = []
        for order in orderManager.orders {
            if let month = order.assignedMonth {
                months.insert(month)
            }
        }
        
        months.insert(formatter.string(from: Date()))
        
        return months.sorted().reversed()
    }
    
    private func formatMonth(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2 else { return month }
        return "\(parts[0])年\(parts[1])月"
    }
    
    private func isCurrentUser(_ user: User) -> Bool {
        user.id == authManager.currentUser?.id
    }
    
    private func medalColor(for index: Int) -> Color {
        switch index {
        case 0: return Color.yellow
        case 1: return Color.gray
        case 2: return Color.orange
        default: return Color.clear
        }
    }
    
    /// 完成张数排行榜数据 (所有人可见)
    private var completedPhotosRankingData: [StaffStat] {
        orderManager.staffList.map { staff in
            let orders = orderManager.orders.filter {
                $0.assignedTo == staff.id && $0.assignedMonth == selectedMonth
            }
            let completedOrders = orders.filter { $0.isCompleted }
            let complaintOrders = completedOrders.filter { $0.isComplaint }
            
            return StaffStat(
                staff: staff,
                orderCount: orders.count,
                totalPhotos: orders.reduce(0) { $0 + $1.totalCount },
                completedCount: completedOrders.count,
                completedPhotos: completedOrders.reduce(0) { $0 + $1.totalCount },
                complaintPhotos: complaintOrders.reduce(0) { $0 + $1.totalCount },
                completionRate: orders.isEmpty ? "0%" : String(format: "%.0f%%", Double(completedOrders.count) / Double(orders.count) * 100)
            )
        }
        .sorted { $0.completedPhotos > $1.completedPhotos }
    }
    
    /// 全部人员详细统计 (仅管理员)
    private var allStaffStats: [StaffStat] {
        completedPhotosRankingData.sorted { $0.orderCount > $1.orderCount }
    }
    
    /// 月度统计数据
    private var myMonthlyStats: [MonthlyStat] {
        availableMonths.prefix(6).reversed().map { month in
            let orders: [Order]
            if authManager.hasAdminPrivilege {
                orders = orderManager.orders.filter { $0.assignedMonth == month }
            } else {
                orders = orderManager.orders.filter {
                    $0.assignedMonth == month && $0.assignedTo == authManager.currentUser?.id
                }
            }
            let completedPhotos = orders.filter { $0.isCompleted }.reduce(0) { $0 + $1.totalCount }
            return MonthlyStat(month: month, orderCount: orders.count, photos: completedPhotos)
        }
    }
    
    // MARK: - 年度趋势数据（1-12月固定显示）
    
    private var yearlyOrderTrendData: [YearlyTrendStat] {
        generateYearlyTrendData(for: selectedYear)
    }
    
    private var lastYearOrderTrendData: [YearlyTrendStat] {
        generateYearlyTrendData(for: selectedYear - 1)
    }
    
    private func generateYearlyTrendData(for year: Int) -> [YearlyTrendStat] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let currentMonth = calendar.component(.month, from: Date())
        
        return (1...12).map { month in
            let monthStr = String(format: "%04d-%02d", year, month)
            
            let orders: [Order]
            if authManager.hasAdminPrivilege {
                orders = orderManager.orders.filter { $0.assignedMonth == monthStr }
            } else {
                orders = orderManager.orders.filter {
                    $0.assignedMonth == monthStr && $0.assignedTo == authManager.currentUser?.id
                }
            }
            
            let completedOrders = orders.filter { $0.isCompleted }
            
            return YearlyTrendStat(
                month: month,
                monthLabel: "\(month)月",
                orderCount: orders.count,
                completedPhotos: completedOrders.reduce(0) { $0 + $1.totalCount },
                isCurrentMonth: (year == currentYear && month == currentMonth)
            )
        }
    }
    
    // MARK: - 月度完成张数数据
    
    private var yearlyPhotosData: [YearlyTrendStat] {
        generateYearlyTrendData(for: selectedYear)
    }
    
    private var lastYearPhotosData: [YearlyTrendStat] {
        generateYearlyTrendData(for: selectedYear - 1)
    }
    
    private func generateStaffPhotosData(for staff: User, year: Int) -> [YearlyTrendStat] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let currentMonth = calendar.component(.month, from: Date())
        
        return (1...12).map { month in
            let monthStr = String(format: "%04d-%02d", year, month)
            
            let orders = orderManager.orders.filter {
                $0.assignedTo == staff.id && $0.assignedMonth == monthStr && $0.isCompleted
            }
            
            return YearlyTrendStat(
                month: month,
                monthLabel: "\(month)月",
                orderCount: orders.count,
                completedPhotos: orders.reduce(0) { $0 + $1.totalCount },
                isCurrentMonth: (year == currentYear && month == currentMonth)
            )
        }
    }
}

// MARK: - 数据结构

struct StaffStat {
    let staff: User
    let orderCount: Int
    let totalPhotos: Int
    let completedCount: Int
    let completedPhotos: Int      // 已完成订单的总张数
    let complaintPhotos: Int      // 投诉完成张数
    let completionRate: String
}

struct MonthlyStat {
    let month: String
    let orderCount: Int
    let photos: Int
}

struct YearlyTrendStat: Identifiable {
    let id = UUID()
    let month: Int            // 1-12
    let monthLabel: String    // "1月"..."12月"
    let orderCount: Int       // 订单数
    let completedPhotos: Int  // 完成张数
    let isCurrentMonth: Bool  // 是否当前月
}

// MARK: - 概览卡片

struct OverviewCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - 排行榜行视图

struct RankingRowView: View {
    let index: Int
    let stat: StaffStat
    let isCurrentUser: Bool
    let totalCount: Int
    
    private let complaintColor = Color(red: 0.6, green: 0.1, blue: 0.1)
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                rankBadge
                avatar
                nameLabel
                Spacer()
                complaintBadge
                photosLabel
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
            .background(isCurrentUser ? Color.blue.opacity(0.05) : Color.clear)
            
            if index < totalCount - 1 {
                Divider()
            }
        }
    }
    
    private var rankBadge: some View {
        ZStack {
            if index < 3 {
                Circle()
                    .fill(medalColor)
                    .frame(width: 28, height: 28)
                Text("\(index + 1)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            } else {
                Text("\(index + 1)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: 28)
            }
        }
    }
    
    private var avatar: some View {
        Circle()
            .fill(isCurrentUser ? Color.blue : Color.gray.opacity(0.2))
            .frame(width: 32, height: 32)
            .overlay(
                Text(String(stat.staff.displayName.prefix(1)))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isCurrentUser ? .white : .primary)
            )
    }
    
    private var nameLabel: some View {
        HStack(spacing: 4) {
            Text(stat.staff.displayName)
                .font(.subheadline)
                .fontWeight(isCurrentUser ? .bold : .regular)
                .foregroundColor(isCurrentUser ? .blue : .primary)
            
            if isCurrentUser {
                Text("(我)")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }
    
    @ViewBuilder
    private var complaintBadge: some View {
        if stat.complaintPhotos > 0 {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text("\(stat.complaintPhotos)")
                    .font(.caption)
            }
            .foregroundColor(complaintColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(complaintColor.opacity(0.1))
            .cornerRadius(4)
        }
    }
    
    private var photosLabel: some View {
        Text("\(stat.completedPhotos) 张")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.green)
    }
    
    private var medalColor: Color {
        switch index {
        case 0: return Color.yellow
        case 1: return Color.gray
        case 2: return Color.orange
        default: return Color.clear
        }
    }
}

#Preview {
    StatsView()
        .environmentObject(OrderManager())
        .environmentObject(AuthManager())
}
