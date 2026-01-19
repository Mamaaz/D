import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var orderManager: OrderManager
    @EnvironmentObject var authManager: AuthManager
    
    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()
    
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
    
    var body: some View {
        VStack(spacing: 0) {
            // 月份导航
            monthNavigator
            
            Divider()
            
            HStack(alignment: .top, spacing: 0) {
                // 日历网格
                VStack {
                    // 星期标题
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(weekdays, id: \.self) { day in
                            Text(day)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                    
                    // 日期网格
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(daysInMonth(), id: \.self) { date in
                            DayCell(
                                date: date,
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                isCurrentMonth: calendar.isDate(date, equalTo: currentMonth, toGranularity: .month),
                                staffOrders: staffOrdersForDate(date),
                                hasOverdue: visibleOrdersForDate(date).contains { $0.isOverdue }
                            ) {
                                selectedDate = date
                            }
                        }
                    }
                    .padding()
                    
                    // 图例 (仅管理员显示)
                    if authManager.hasAdminPrivilege {
                        legendView
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // 人员柱状图
                        staffBarChartView
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                
                // 右侧订单列表
                VStack(alignment: .leading, spacing: 16) {
                    // 选中日期标题
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedDate, format: .dateTime.year().month().day().weekday(.wide))
                            .font(.headline)
                        
                        Text("待交付订单 \(visibleOrdersForSelectedDate.count) 个")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    
                    Divider()
                    
                    // 订单列表
                    if visibleOrdersForSelectedDate.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.5))
                            
                            Text("该日期无待交付订单")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(visibleOrdersForSelectedDate) { order in
                                    CalendarOrderCard(order: order, staffList: orderManager.staffList)
                                }
                            }
                            .padding()
                        }
                    }
                }
                .frame(width: 350)
            }
        }
    }
    
    // MARK: - 月份导航
    
    private var monthNavigator: some View {
        VStack(spacing: 12) {
            // 月份切换
            HStack {
                Button {
                    previousMonth()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // 中文月份标题
                Text(ChineseLunarCalendar.formatMonthYear(currentMonth))
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    nextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                
                Button {
                    currentMonth = Date()
                    selectedDate = Date()
                } label: {
                    Text("今天")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
            }
            
            // 月度统计
            HStack(spacing: 24) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.blue)
                    Text("本月订单")
                        .foregroundColor(.secondary)
                    Text("\(monthOrderCount) 个")
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "photo.stack")
                        .foregroundColor(.green)
                    Text("总张数")
                        .foregroundColor(.secondary)
                    Text("\(monthTotalPhotos) 张")
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                
                Spacer()
            }
            .font(.subheadline)
        }
        .padding()
    }
    
    // MARK: - 月度统计
    
    /// 本月订单数（基于交付时间）
    private var monthOrderCount: Int {
        visibleOrders().filter { order in
            guard let deadline = order.finalDeadline else { return false }
            return calendar.isDate(deadline, equalTo: currentMonth, toGranularity: .month)
        }.count
    }
    
    /// 本月总张数（基于交付时间）
    private var monthTotalPhotos: Int {
        visibleOrders().filter { order in
            guard let deadline = order.finalDeadline else { return false }
            return calendar.isDate(deadline, equalTo: currentMonth, toGranularity: .month)
        }.reduce(0) { $0 + $1.totalCount }
    }
    
    // MARK: - 图例视图
    
    private var legendView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("人员图例")
                .font(.caption)
                .foregroundColor(.secondary)
            
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
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    // MARK: - 人员柱状图
    
    /// 每个人的月度数据
    private var staffMonthlyData: [(staff: User, totalPhotos: Int, completedPhotos: Int)] {
        orderManager.staffList.map { staff in
            let staffOrders = orderManager.orders.filter { order in
                guard let deadline = order.finalDeadline else { return false }
                return order.assignedTo == staff.id &&
                       calendar.isDate(deadline, equalTo: currentMonth, toGranularity: .month)
            }
            
            let totalPhotos = staffOrders.reduce(0) { $0 + $1.totalCount }
            let completedPhotos = staffOrders.filter { $0.isCompleted }.reduce(0) { $0 + $1.totalCount }
            
            return (staff: staff, totalPhotos: totalPhotos, completedPhotos: completedPhotos)
        }
        .filter { $0.totalPhotos > 0 }
        .sorted { $0.totalPhotos > $1.totalPhotos }
    }
    
    /// 最大张数（用于计算柱状图比例）
    private var maxPhotos: Int {
        staffMonthlyData.map { $0.totalPhotos }.max() ?? 1
    }
    
    private var staffBarChartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本月人员工作量")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if staffMonthlyData.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(staffMonthlyData, id: \.staff.id) { item in
                        StaffBarRow(
                            staff: item.staff,
                            totalPhotos: item.totalPhotos,
                            completedPhotos: item.completedPhotos,
                            maxPhotos: maxPhotos
                        )
                    }
                }
            }
            
            // 图例说明
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 16, height: 8)
                    Text("待完成")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green.opacity(0.6))
                        .frame(width: 16, height: 8)
                    Text("已完成")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal)
    }
    
    // MARK: - 数据 (根据权限筛选)
    
    /// 当前用户可见的订单
    private func visibleOrders() -> [Order] {
        if authManager.hasAdminPrivilege {
            // 管理员可看到所有订单
            return orderManager.orders
        } else {
            // 后期人员只能看到自己的订单
            return orderManager.orders.filter { $0.assignedTo == authManager.currentUser?.id }
        }
    }
    
    private var visibleOrdersForSelectedDate: [Order] {
        visibleOrdersForDate(selectedDate)
    }
    
    private func visibleOrdersForDate(_ date: Date) -> [Order] {
        visibleOrders().filter { order in
            guard let deadline = order.finalDeadline, !order.isCompleted else { return false }
            return calendar.isDate(deadline, inSameDayAs: date)
        }
    }
    
    /// 返回某一天按人员分组的订单 (用于显示颜色圆点)
    private func staffOrdersForDate(_ date: Date) -> [(staff: User, count: Int)] {
        let ordersOnDate = visibleOrdersForDate(date)
        var result: [(staff: User, count: Int)] = []
        
        // 管理员：遍历所有员工
        if authManager.hasAdminPrivilege {
            for staff in orderManager.staffList {
                let count = ordersOnDate.filter { $0.assignedTo == staff.id }.count
                if count > 0 {
                    result.append((staff: staff, count: count))
                }
            }
        } else {
            // 普通用户：显示自己的订单
            if let currentUser = authManager.currentUser {
                let myOrders = ordersOnDate.filter { $0.assignedTo == currentUser.id }
                if !myOrders.isEmpty {
                    result.append((staff: currentUser, count: myOrders.count))
                }
            }
        }
        
        // 添加未分配的订单
        let unassignedCount = ordersOnDate.filter { $0.assignedTo == nil }.count
        if unassignedCount > 0 {
            // 使用灰色表示未分配
            let unassignedUser = User(
                username: "unassigned",
                nickname: "未分配",
                role: .staff,
                calendarColorRed: 0.5,
                calendarColorGreen: 0.5,
                calendarColorBlue: 0.5
            )
            result.append((staff: unassignedUser, count: unassignedCount))
        }
        
        return result
    }
    
    private func daysInMonth() -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let monthLastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end - 1)
        else {
            return []
        }
        
        var dates: [Date] = []
        var currentDate = monthFirstWeek.start
        
        while currentDate < monthLastWeek.end {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return dates
    }
    
    private func previousMonth() {
        currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }
    
    private func nextMonth() {
        currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
    }
}

// MARK: - 日期单元格

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isCurrentMonth: Bool
    let staffOrders: [(staff: User, count: Int)]
    let hasOverdue: Bool
    let action: () -> Void
    
    private let calendar = Calendar.current
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                // 公历日期
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                    .foregroundColor(textColor)
                
                // 农历日期
                Text(ChineseLunarCalendar.lunarDay(from: date))
                    .font(.system(size: 9))
                    .foregroundColor(lunarTextColor)
                    .lineLimit(1)
                
                // 颜色圆点区域 - 每个订单显示一个圆点
                if !staffOrders.isEmpty {
                    let allDots = generateDots(from: staffOrders)
                    HStack(spacing: 2) {
                        ForEach(Array(allDots.prefix(5).enumerated()), id: \.offset) { _, color in
                            Circle()
                                .fill(color)
                                .frame(width: 4, height: 4)
                        }
                        if allDots.count > 5 {
                            Text("+\(allDots.count - 5)")
                                .font(.system(size: 6))
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Spacer()
                        .frame(height: 5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(backgroundColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(hasOverdue && !isSelected ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var lunarTextColor: Color {
        if isSelected {
            return .white.opacity(0.8)
        } else if !isCurrentMonth {
            return .gray.opacity(0.3)
        } else {
            return .secondary
        }
    }
    
    private var textColor: Color {
        if isSelected {
            return .white
        } else if !isCurrentMonth {
            return .gray.opacity(0.5)
        } else if isToday {
            return .blue
        } else {
            return .primary
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .blue
        } else if isToday {
            return .blue.opacity(0.1)
        } else {
            return .clear
        }
    }
    
    private var isToday: Bool {
        calendar.isDateInToday(date)
    }
    
    /// 生成圆点颜色数组 - 每个订单一个圆点
    private func generateDots(from staffOrders: [(staff: User, count: Int)]) -> [Color] {
        var dots: [Color] = []
        for item in staffOrders {
            let color = Color(red: item.staff.calendarColorRed, green: item.staff.calendarColorGreen, blue: item.staff.calendarColorBlue)
            for _ in 0..<item.count {
                dots.append(color)
            }
        }
        return dots
    }
}

// MARK: - 人员柱状图行

struct StaffBarRow: View {
    let staff: User
    let totalPhotos: Int
    let completedPhotos: Int
    let maxPhotos: Int
    
    private var staffColor: Color {
        Color(red: staff.calendarColorRed, green: staff.calendarColorGreen, blue: staff.calendarColorBlue)
    }
    
    private var totalWidthRatio: CGFloat {
        guard maxPhotos > 0 else { return 0 }
        return CGFloat(totalPhotos) / CGFloat(maxPhotos)
    }
    
    private var completedWidthRatio: CGFloat {
        guard totalPhotos > 0 else { return 0 }
        return CGFloat(completedPhotos) / CGFloat(totalPhotos)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // 人名
            Text(staff.displayName)
                .font(.caption)
                .frame(width: 50, alignment: .leading)
            
            // 柱状图
            GeometryReader { geometry in
                let totalWidth = geometry.size.width * totalWidthRatio
                
                ZStack(alignment: .leading) {
                    // 总张数背景条（用个人颜色）
                    RoundedRectangle(cornerRadius: 3)
                        .fill(staffColor.opacity(0.3))
                        .frame(width: max(totalWidth, 4))
                    
                    // 已完成部分（用绿色覆盖）
                    if completedPhotos > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.green.opacity(0.7))
                            .frame(width: max(totalWidth * completedWidthRatio, 4))
                    }
                }
            }
            .frame(height: 14)
            
            // 数字
            HStack(spacing: 4) {
                Text("\(completedPhotos)")
                    .foregroundColor(.green)
                Text("/")
                    .foregroundColor(.secondary)
                Text("\(totalPhotos)")
                    .foregroundColor(.primary)
            }
            .font(.caption)
            .fontWeight(.medium)
            .frame(width: 70, alignment: .trailing)
        }
    }
}

// MARK: - 日历订单卡片

struct CalendarOrderCard: View {
    let order: Order
    let staffList: [User]
    @EnvironmentObject var authManager: AuthManager
    
    @State private var showDetail: Bool = false
    
    private var assignedStaff: User? {
        guard let assignedTo = order.assignedTo else { return nil }
        return staffList.first { $0.id == assignedTo }
    }
    
    /// 获取显示的人员名称
    private var displayedAssigneeName: String? {
        // 优先使用 API 返回的名称
        if let userName = order.assignedUserName, !userName.isEmpty {
            return userName
        }
        // 回退到 staffList 查找
        if let staff = assignedStaff {
            return staff.displayName
        }
        // 如果是分配给自己
        if order.assignedTo == authManager.currentUser?.id {
            return authManager.currentUser?.nickname ?? authManager.currentUser?.username ?? "我"
        }
        return nil
    }
    
    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 12) {
                // 人员颜色指示条
                Rectangle()
                    .fill(staffColor)
                    .frame(width: 4)
                    .cornerRadius(2)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(order.orderNumber)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        // 后期人员
                        if let name = displayedAssigneeName {
                            HStack(spacing: 4) {
                                if let staff = assignedStaff {
                                    Circle()
                                        .fill(Color(red: staff.calendarColorRed, green: staff.calendarColorGreen, blue: staff.calendarColorBlue))
                                        .frame(width: 8, height: 8)
                                } else if order.assignedTo == authManager.currentUser?.id, let user = authManager.currentUser {
                                    Circle()
                                        .fill(Color(red: user.calendarColorRed, green: user.calendarColorGreen, blue: user.calendarColorBlue))
                                        .frame(width: 8, height: 8)
                                }
                                Text(name)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        } else if order.assignedTo != nil {
                            Text("已分配")
                                .font(.caption)
                                .foregroundColor(.blue)
                        } else {
                            Text("未分配")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    HStack {
                        Label(order.shootLocation, systemImage: "mappin")
                        Label("\(order.totalCount)张", systemImage: "photo")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if order.isOverdue {
                    Text("逾期")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .cornerRadius(4)
                }
                
                // 箭头指示可点击
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            OrderDetailView(order: order)
        }
    }
    
    private var staffColor: Color {
        if order.isOverdue {
            return .red
        } else if let staff = assignedStaff {
            return Color(red: staff.calendarColorRed, green: staff.calendarColorGreen, blue: staff.calendarColorBlue)
        } else {
            return .gray
        }
    }
}

#Preview {
    CalendarView()
        .environmentObject(OrderManager())
        .environmentObject(AuthManager())
}
