import SwiftUI

// MARK: - 归档页面

struct ArchiveView: View {
    @EnvironmentObject var orderManager: OrderManager
    @EnvironmentObject var authManager: AuthManager
    
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth: Int? = nil
    @State private var showHistoryOrders: Bool = false
    @State private var historyOrders: [Order] = []
    @State private var isLoadingHistory: Bool = false
    
    private let months = Array(1...12)
    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 12)
    ]
    
    var body: some View {
        NavigationSplitView {
            // 左侧年月选择
            VStack(spacing: 0) {
                // 年份选择器
                HStack {
                    Button {
                        selectedYear -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(selectedYear)年")
                        .font(.headline)
                        .frame(width: 80)
                    
                    Button {
                        selectedYear += 1
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedYear >= Calendar.current.component(.year, from: Date()))
                }
                .padding()
                
                Divider()
                
                // 月份网格
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(months, id: \.self) { month in
                        MonthButton(
                            month: month,
                            count: archivedOrdersForMonth(month).count,
                            isSelected: selectedMonth == month
                        ) {
                            selectedMonth = month
                        }
                    }
                }
                .padding()
                
                Spacer()
                
                // 查看历史订单按钮
                Divider()
                Button {
                    showHistoryOrders = true
                    loadHistoryOrders()
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("查看历史订单")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .padding()
            }
            .frame(minWidth: 200)
            .navigationTitle("归档")
        } detail: {
            // 右侧订单列表
            if let month = selectedMonth {
                ArchivedOrderListView(
                    year: selectedYear,
                    month: month,
                    orders: archivedOrdersForMonth(month)
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("请选择月份查看归档订单")
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showHistoryOrders) {
            HistoryOrdersView(
                orders: $historyOrders,
                isLoading: $isLoadingHistory,
                onRefresh: loadHistoryOrders
            )
        }
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
    
    /// 加载历史订单
    private func loadHistoryOrders() {
        isLoadingHistory = true
        Task {
            do {
                let orders = try await APIService.shared.getHistoryOrders()
                await MainActor.run {
                    historyOrders = orders
                    isLoadingHistory = false
                }
            } catch {
                await MainActor.run {
                    isLoadingHistory = false
                }
                print("加载历史订单失败: \(error)")
            }
        }
    }
}

// MARK: - 月份按钮

struct MonthButton: View {
    let month: Int
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(month)月")
                    .font(.headline)
                
                Text("\(count) 单")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 70, height: 50)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 归档订单列表

struct ArchivedOrderListView: View {
    let year: Int
    let month: Int
    let orders: [Order]
    @EnvironmentObject var orderManager: OrderManager
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text("\(year)年\(month)月 归档订单")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text("\(orders.count) 单 · \(totalPhotos) 张")
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            if orders.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("该月份暂无归档订单")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(orders) { order in
                    ArchivedOrderRow(order: order)
                }
                .listStyle(.inset)
            }
        }
    }
    
    private var totalPhotos: Int {
        orders.reduce(0) { $0 + $1.totalCount }
    }
}

// MARK: - 归档订单行

struct ArchivedOrderRow: View {
    let order: Order
    @EnvironmentObject var orderManager: OrderManager
    @EnvironmentObject var authManager: AuthManager
    
    private var assignedStaff: User? {
        guard let assignedTo = order.assignedTo else { return nil }
        return orderManager.staffList.first { $0.id == assignedTo }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 归档状态标记
            Image(systemName: "checkmark.square.fill")
                .foregroundColor(.green)
            
            // 订单信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(order.orderNumber)
                        .font(.headline)
                    
                    Text("·")
                        .foregroundColor(.secondary)
                    
                    Text(order.shootLocation)
                    
                    // 类型标签
                    Text(order.shootType.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(order.shootType == .wedding ? Color.pink.opacity(0.2) : Color.purple.opacity(0.2))
                        .foregroundColor(order.shootType == .wedding ? .pink : .purple)
                        .cornerRadius(4)
                }
                
                HStack(spacing: 16) {
                    Text("\(order.totalCount) 张")
                        .foregroundColor(.secondary)
                    
                    if let staff = assignedStaff {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(red: staff.calendarColorRed, green: staff.calendarColorGreen, blue: staff.calendarColorBlue))
                                .frame(width: 8, height: 8)
                            Text(staff.displayName)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    if let completedAt = order.completedAt {
                        Text("完成于 \(formatDate(completedAt))")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.caption)
            }
            
            Spacer()
            
            // 管理员可以取消归档
            if authManager.hasAdminPrivilege {
                Button {
                    Task { await orderManager.unarchiveOrder(order) }
                } label: {
                    Text("取消归档")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}

// MARK: - 历史订单视图

struct HistoryOrdersView: View {
    @Binding var orders: [Order]
    @Binding var isLoading: Bool
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var orderManager: OrderManager
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if orders.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("暂无历史订单")
                            .foregroundColor(.secondary)
                        Text("归档超过12个月的订单会自动转入历史")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 统计信息
                    HStack {
                        Text("共 \(orders.count) 单")
                        Spacer()
                        Text("总计 \(orders.reduce(0) { $0 + $1.totalCount }) 张")
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    
                    // 订单列表
                    List(orders) { order in
                        HistoryOrderRow(order: order)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("历史订单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 400)
        #endif
    }
}

// MARK: - 历史订单行

struct HistoryOrderRow: View {
    let order: Order
    @EnvironmentObject var orderManager: OrderManager
    
    private var assignedStaff: User? {
        guard let assignedTo = order.assignedTo else { return nil }
        return orderManager.staffList.first { $0.id == assignedTo }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .foregroundColor(.gray)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(order.orderNumber)
                        .font(.headline)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(order.shootLocation)
                }
                
                HStack(spacing: 16) {
                    Text("\(order.totalCount) 张")
                        .foregroundColor(.secondary)
                    
                    if let staff = assignedStaff {
                        Text(staff.displayName)
                            .foregroundColor(.secondary)
                    }
                    
                    if let archiveMonth = order.archiveMonth, !archiveMonth.isEmpty {
                        Text("归档于 \(archiveMonth)")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.caption)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ArchiveView()
        .environmentObject(OrderManager())
        .environmentObject(AuthManager())
}
