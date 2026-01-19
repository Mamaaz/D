import SwiftUI

// MARK: - 结算页面

struct SettlementView: View {
    @EnvironmentObject var orderManager: OrderManager
    @EnvironmentObject var authManager: AuthManager
    
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    
    private let months = Array(1...12)
    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // 年份选择器
            yearSelector
            
            Divider()
            
            // 月度卡片网格
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(months, id: \.self) { month in
                        MonthlySettlementCard(
                            year: selectedYear,
                            month: month,
                            archivedOrders: archivedOrdersForMonth(month),
                            staffList: orderManager.staffList,
                            currentUser: authManager.currentUser,
                            isAdmin: authManager.hasAdminPrivilege,
                            currentUserId: authManager.currentUser?.id,
                            currentUserRole: authManager.currentUser?.role
                        )
                    }
                }
                .padding()
            }
        }
    }
    
    private var yearSelector: some View {
        HStack {
            Button {
                selectedYear -= 1
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            
            Text("\(selectedYear)年 结算")
                .font(.title2)
                .fontWeight(.bold)
                .frame(width: 150)
            
            Button {
                selectedYear += 1
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(selectedYear >= Calendar.current.component(.year, from: Date()))
            
            Spacer()
            
            // 年度汇总
            if authManager.hasAdminPrivilege {
                HStack(spacing: 16) {
                    Text("年度总计:")
                        .foregroundColor(.secondary)
                    Text("\(yearTotalCount) 张")
                        .fontWeight(.semibold)
                    Text("¥\(yearTotalPerformance, specifier: "%.0f")")
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
    }
    
    /// 获取指定月份的已归档订单
    private func archivedOrdersForMonth(_ month: Int) -> [Order] {
        let monthStr = String(format: "%04d-%02d", selectedYear, month)
        
        let orders = orderManager.orders.filter { order in
            order.isArchived && order.archiveMonth == monthStr
        }
        
        // 如果是管理员，返回所有订单；否则只返回自己的
        if authManager.hasAdminPrivilege {
            return orders
        } else {
            return orders.filter { $0.assignedTo == authManager.currentUser?.id }
        }
    }
    
    /// 年度总张数
    private var yearTotalCount: Int {
        months.reduce(0) { $0 + archivedOrdersForMonth($1).reduce(0) { $0 + $1.totalCount } }
    }
    
    /// 年度总绩效
    private var yearTotalPerformance: Double {
        var total: Double = 0
        for month in months {
            let orders = archivedOrdersForMonth(month)
            for order in orders {
                if let assignedTo = order.assignedTo,
                   let staff = orderManager.staffList.first(where: { $0.id == assignedTo }) {
                    total += order.totalPerformance(user: staff)
                }
            }
        }
        return total
    }
}

// MARK: - 月度结算卡片

struct MonthlySettlementCard: View {
    let year: Int
    let month: Int
    let archivedOrders: [Order]
    let staffList: [User]
    let currentUser: User?
    let isAdmin: Bool
    let currentUserId: UUID?
    let currentUserRole: UserRole?
    
    /// 是否为外包人员视图（简化显示）
    private var isOutsourceView: Bool {
        !isAdmin && currentUserRole == .outsource
    }
    
    private var monthName: String {
        "\(month)月"
    }
    
    private var orderCount: Int {
        archivedOrders.count
    }
    
    private var totalPhotos: Int {
        archivedOrders.reduce(0) { $0 + $1.totalCount }
    }
    
    /// 每人的详细绩效统计
    private var staffPerformanceData: [StaffPerformanceRow] {
        var result: [StaffPerformanceRow] = []
        
        // 如果 staffList 为空且有 currentUser，使用 currentUser
        let effectiveStaffList: [User]
        if staffList.isEmpty, let user = currentUser {
            effectiveStaffList = [user]
        } else {
            effectiveStaffList = staffList
        }
        
        for staff in effectiveStaffList {
            let staffOrders = archivedOrders.filter { $0.assignedTo == staff.id }
            if staffOrders.isEmpty { continue }
            
            var row = StaffPerformanceRow(staff: staff)
            
            for order in staffOrders {
                let count = order.totalCount
                
                if order.shootType == .wedding {
                    if order.isComplaint {
                        row.weddingComplaint += count
                    } else if order.isUrgent {
                        row.weddingUrgent += count
                    } else if order.isInGroup {
                        row.weddingInGroup += count
                    } else {
                        row.weddingNormal += count
                    }
                } else {
                    if order.isComplaint {
                        row.ceremonyComplaint += count
                    } else if order.isUrgent {
                        row.ceremonyUrgent += count
                    } else if order.isInGroup {
                        row.ceremonyInGroup += count
                    } else {
                        row.ceremonyNormal += count
                    }
                }
                
                // 投诉张数（用于外包视图）
                if order.isComplaint {
                    row.complaintCount += count
                }
                
                row.totalPerformance += order.totalPerformance(user: staff)
            }
            
            // 总张数
            row.totalCount = staffOrders.reduce(0) { $0 + $1.totalCount }
            
            result.append(row)
        }
        
        return result.sorted { $0.totalPerformance > $1.totalPerformance }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 卡片标题
            HStack {
                Text(monthName)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                if orderCount > 0 {
                    Text("\(orderCount) 单 · \(totalPhotos) 张")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if archivedOrders.isEmpty {
                Text("暂无归档订单")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else if isOutsourceView {
                // 外包人员简化视图
                outsourceSimplifiedView
            } else {
                // 管理员/后期人员详细视图
                detailedView
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - 外包人员简化视图
    
    private var outsourceSimplifiedView: some View {
        VStack(spacing: 6) {
            // 表头：姓名、基础/张、投诉/张、总张数、总绩效
            HStack(spacing: 0) {
                Text("姓名").frame(width: 50, alignment: .leading)
                Text("基础/张").frame(width: 55, alignment: .trailing)
                Text("投诉/张").frame(width: 55, alignment: .trailing)
                Text("总张数").frame(width: 50, alignment: .trailing)
                Text("总绩效").frame(width: 60, alignment: .trailing)
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            
            Divider()
            
            ForEach(staffPerformanceData, id: \.staff.id) { row in
                HStack(spacing: 0) {
                    Text(row.staff.nickname)
                        .frame(width: 50, alignment: .leading)
                        .lineLimit(1)
                    
                    Text("¥\(Int(row.staff.basePrice))")
                        .frame(width: 55, alignment: .trailing)
                        .foregroundColor(.blue)
                    
                    Text("¥\(Int(row.staff.complaintBonus))")
                        .frame(width: 55, alignment: .trailing)
                        .foregroundColor(.orange)
                    
                    Text("\(row.totalCount)")
                        .frame(width: 50, alignment: .trailing)
                    
                    Text("¥\(row.totalPerformance, specifier: "%.0f")")
                        .frame(width: 60, alignment: .trailing)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                .font(.system(size: 11))
            }
            
            // 月度总计
            Divider()
            
            HStack {
                Text("本月合计")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("¥\(monthTotalPerformance, specifier: "%.0f")")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
        }
    }
    
    // MARK: - 管理员/后期详细视图
    
    private var detailedView: some View {
        VStack(spacing: 6) {
            // 人员绩效列表（水平滚动）
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 6) {
                    // 表头
                    HStack(spacing: 0) {
                        Text("姓名").frame(width: 55, alignment: .leading)
                        Text("¥/张").frame(width: 35, alignment: .trailing)
                        Text("纱").frame(width: 35, alignment: .trailing)
                        Text("纱群").frame(width: 35, alignment: .trailing)
                        Text("纱急").frame(width: 35, alignment: .trailing)
                        Text("纱诉").frame(width: 35, alignment: .trailing)
                        Text("礼").frame(width: 35, alignment: .trailing)
                        Text("礼群").frame(width: 35, alignment: .trailing)
                        Text("礼急").frame(width: 35, alignment: .trailing)
                        Text("礼诉").frame(width: 35, alignment: .trailing)
                        Text("合计").frame(width: 55, alignment: .trailing)
                    }
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    
                    Divider()
                    
                    ForEach(staffPerformanceData, id: \.staff.id) { row in
                        HStack(spacing: 0) {
                            // 姓名 + 外包标识
                            HStack(spacing: 2) {
                                Text(row.staff.nickname)
                                    .lineLimit(1)
                                
                                if row.staff.role == .outsource {
                                    Text("外")
                                        .font(.system(size: 7))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(Color.orange)
                                        .cornerRadius(3)
                                }
                            }
                            .frame(width: 55, alignment: .leading)
                            
                            Text("\(Int(row.staff.basePrice))")
                                .frame(width: 35, alignment: .trailing)
                                .foregroundColor(.secondary)
                            
                            cellText(row.weddingNormal)
                            cellText(row.weddingInGroup)
                            cellText(row.weddingUrgent)
                            cellText(row.weddingComplaint)
                            cellText(row.ceremonyNormal)
                            cellText(row.ceremonyInGroup)
                            cellText(row.ceremonyUrgent)
                            cellText(row.ceremonyComplaint)
                            
                            Text("¥\(row.totalPerformance, specifier: "%.0f")")
                                .frame(width: 55, alignment: .trailing)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                        .font(.system(size: 10))
                    }
                }
            }
            
            // 月度总计
            Divider()
            
            HStack {
                Text("本月合计")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("¥\(monthTotalPerformance, specifier: "%.0f")")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
        }
    }
    
    @ViewBuilder
    private func cellText(_ value: Int) -> some View {
        Text(value > 0 ? "\(value)" : "-")
            .frame(width: 35, alignment: .trailing)
            .foregroundColor(value > 0 ? .primary : .secondary.opacity(0.5))
    }
    
    private var monthTotalPerformance: Double {
        staffPerformanceData.reduce(0) { $0 + $1.totalPerformance }
    }
}

// MARK: - 人员绩效行数据

struct StaffPerformanceRow {
    let staff: User
    var weddingNormal: Int = 0       // 婚纱普通
    var weddingInGroup: Int = 0      // 婚纱进群
    var weddingUrgent: Int = 0       // 婚纱加急
    var weddingComplaint: Int = 0    // 婚纱投诉
    var ceremonyNormal: Int = 0      // 婚礼普通
    var ceremonyInGroup: Int = 0     // 婚礼进群
    var ceremonyUrgent: Int = 0      // 婚礼加急
    var ceremonyComplaint: Int = 0   // 婚礼投诉
    var complaintCount: Int = 0      // 投诉总张数（外包视图用）
    var totalCount: Int = 0          // 总张数（外包视图用）
    var totalPerformance: Double = 0 // 总绩效
}

#Preview {
    SettlementView()
        .environmentObject(OrderManager())
        .environmentObject(AuthManager())
}
