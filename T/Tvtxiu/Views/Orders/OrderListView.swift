import SwiftUI

struct OrderListView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var orderManager: OrderManager
    
    @State private var showNewOrderSheet: Bool = false
    @State private var selectedOrder: Order?
    @State private var showFilterPopover: Bool = false
    @State private var selectedTab: OrderTab = .pending
    
    // 快捷筛选
    @State private var quickFilter: QuickFilter = .none
    
    enum QuickFilter: String, CaseIterable {
        case none = "全部"
        case urgent = "加急"
        case complaint = "投诉"
        case upcoming = "即将到期"
        case overdue = "已逾期"
    }
    
    enum OrderTab: String, CaseIterable {
        case pending = "待完成"
        case completed = "已完成"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部 Tab 切换
            tabSwitcher
            
            Divider()
            
            // 工具栏
            headerView
            
            // 快捷筛选标签
            quickFilterBar
            
            Divider()
            
            // 订单列表
            if orderManager.isLoading {
                // 加载中显示骨架屏
                ScrollView {
                    SkeletonOrderList(count: 6)
                }
            } else if displayedOrders.isEmpty {
                emptyStateView
            } else {
                orderListContent
            }
        }
        .sheet(isPresented: $showNewOrderSheet) {
            NewOrderView()
        }
        .sheet(item: $selectedOrder) { order in
            OrderDetailView(order: order)
        }
    }
    
    // MARK: - Tab 切换
    
    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(OrderTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Text(tab.rawValue)
                                .font(.headline)
                                .fontWeight(selectedTab == tab ? .bold : .medium)
                            
                            // 数量徽章
                            Text("\(countForTab(tab))")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(selectedTab == tab ? .white : .secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(selectedTab == tab ? tabColor(tab) : Color.gray.opacity(0.2))
                                .cornerRadius(10)
                        }
                        .foregroundColor(selectedTab == tab ? tabColor(tab) : .secondary)
                        
                        // 选中指示条
                        Rectangle()
                            .fill(selectedTab == tab ? tabColor(tab) : Color.clear)
                            .frame(height: 3)
                            .cornerRadius(1.5)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }
    
    private func countForTab(_ tab: OrderTab) -> Int {
        let orders = orderManager.filteredOrders
        switch tab {
        case .pending:
            return orders.filter { !$0.isCompleted }.count
        case .completed:
            return orders.filter { $0.isCompleted }.count
        }
    }
    
    private func tabColor(_ tab: OrderTab) -> Color {
        switch tab {
        case .pending: return .blue
        case .completed: return .green
        }
    }
    
    // MARK: - 当前显示的订单
    
    private var displayedOrders: [Order] {
        var orders = orderManager.filteredOrders
        
        // 应用 Tab 筛选
        switch selectedTab {
        case .pending:
            orders = orders.filter { !$0.isCompleted }
        case .completed:
            orders = orders.filter { $0.isCompleted }
        }
        
        // 应用快捷筛选
        let now = Date()
        let threeDaysLater = Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now
        
        switch quickFilter {
        case .none:
            break
        case .urgent:
            orders = orders.filter { $0.isUrgent }
        case .complaint:
            orders = orders.filter { $0.isComplaint }
        case .upcoming:
            orders = orders.filter { order in
                guard let deadline = order.finalDeadline else { return false }
                return deadline > now && deadline <= threeDaysLater
            }
        case .overdue:
            orders = orders.filter { order in
                guard let deadline = order.finalDeadline else { return false }
                return deadline < now && !order.isCompleted
            }
        }
        
        // 排序：加急优先，然后按交付时间
        return orders.sorted { order1, order2 in
            // 加急订单优先
            if order1.isUrgent != order2.isUrgent {
                return order1.isUrgent
            }
            // 投诉订单次优先
            if order1.isComplaint != order2.isComplaint {
                return order1.isComplaint
            }
            // 按交付时间排序
            let deadline1 = order1.finalDeadline ?? Date.distantFuture
            let deadline2 = order2.finalDeadline ?? Date.distantFuture
            return deadline1 < deadline2
        }
    }
    
    // MARK: - 快捷筛选栏
    
    private var quickFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QuickFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            quickFilter = quickFilter == filter ? .none : filter
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: iconForFilter(filter))
                                .font(.caption)
                            Text(filter.rawValue)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(quickFilter == filter ? colorForFilter(filter).opacity(0.2) : Color.gray.opacity(0.1))
                        .foregroundColor(quickFilter == filter ? colorForFilter(filter) : .secondary)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(quickFilter == filter ? colorForFilter(filter) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    private func iconForFilter(_ filter: QuickFilter) -> String {
        switch filter {
        case .none: return "list.bullet"
        case .urgent: return "bolt.fill"
        case .complaint: return "flag.fill"
        case .upcoming: return "clock.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        }
    }
    
    private func colorForFilter(_ filter: QuickFilter) -> Color {
        switch filter {
        case .none: return .blue
        case .urgent: return .orange
        case .complaint: return .red
        case .upcoming: return .purple
        case .overdue: return .red
        }
    }
    
    // MARK: - 顶部工具栏
    
    private var headerView: some View {
        HStack(spacing: 16) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("搜索订单编号、地点、客服...", text: $orderManager.searchText)
                    .textFieldStyle(.plain)
                
                if !orderManager.searchText.isEmpty {
                    Button {
                        orderManager.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            .frame(maxWidth: 400)
            
            // 筛选按钮
            Button {
                showFilterPopover.toggle()
            } label: {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("筛选订单")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(hasActiveFilters ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                .foregroundColor(hasActiveFilters ? .blue : .primary)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(hasActiveFilters ? Color.blue : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFilterPopover) {
                AdvancedFilterView()
                    .frame(width: 320)
            }
            
            Spacer()
            
            // 统计信息
            HStack(spacing: 16) {
                StatBadge(
                    title: "逾期",
                    count: orderManager.overdueOrders.count,
                    color: .red
                )
                
                StatBadge(
                    title: "今日交付",
                    count: orderManager.todayOrders.count,
                    color: .orange
                )
            }
            
            // 新建订单按钮 (仅管理员)
            if authManager.hasAdminPrivilege {
                Button {
                    showNewOrderSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("新建订单")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
    
    private var hasActiveFilters: Bool {
        orderManager.filterStaffId != nil ||
        orderManager.filterMonth != nil ||
        !orderManager.filterLocation.isEmpty ||
        !orderManager.filterPhotographer.isEmpty ||
        !orderManager.filterConsultant.isEmpty
    }
    
    // MARK: - 空状态
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: selectedTab == .completed ? "checkmark.circle" : "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text(selectedTab == .completed ? "暂无已完成订单" : "暂无待完成订单")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            if authManager.hasAdminPrivilege && selectedTab == .pending {
                Text("点击\"新建订单\"开始添加")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 订单列表内容
    
    private var orderListContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(displayedOrders) { order in
                    OrderRowView(order: order)
                        .onTapGesture {
                            selectedOrder = order
                        }
                        .onAppear {
                            // 无限滚动：接近底部时加载更多
                            orderManager.loadMoreIfNeeded(currentItem: order)
                        }
                }
                
                // 加载更多指示器
                if orderManager.isLoadingMore {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("加载更多...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else if !orderManager.hasMoreData && orderManager.orders.count > 0 {
                    Text("— 已加载全部 \(orderManager.orders.count) 条订单 —")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding()
        }
        .refreshable {
            await orderManager.refreshOrders()
        }
    }
}

// MARK: - 统计徽章

struct StatBadge: View {
    let title: String
    let count: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - 高级筛选弹窗

struct AdvancedFilterView: View {
    @EnvironmentObject var orderManager: OrderManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("筛选订单")
                .font(.headline)
            
            // 后期人员筛选
            VStack(alignment: .leading, spacing: 8) {
                Text("后期人员")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $orderManager.filterStaffId) {
                    Text("全部").tag(nil as UUID?)
                    Text("未分配").tag(OrderManager.unassignedFilterId as UUID?)
                    ForEach(orderManager.staffList) { staff in
                        Text(staff.displayName).tag(staff.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // 地点筛选
            VStack(alignment: .leading, spacing: 8) {
                Text("拍摄地点")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("输入地点关键词", text: $orderManager.filterLocation)
                    .textFieldStyle(.roundedBorder)
            }
            
            // 摄影师筛选
            VStack(alignment: .leading, spacing: 8) {
                Text("摄影师")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("输入摄影师关键词", text: $orderManager.filterPhotographer)
                    .textFieldStyle(.roundedBorder)
            }
            
            // 客服筛选
            VStack(alignment: .leading, spacing: 8) {
                Text("客服/顾问")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("输入客服关键词", text: $orderManager.filterConsultant)
                    .textFieldStyle(.roundedBorder)
            }
            
            // 张数范围
            VStack(alignment: .leading, spacing: 8) {
                Text("张数范围")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    TextField("最小", value: $orderManager.filterMinCount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    
                    Text("-")
                    
                    TextField("最大", value: $orderManager.filterMaxCount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    
                    Text("张")
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            Button {
                resetFilters()
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("重置所有筛选")
                }
                .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    private func resetFilters() {
        orderManager.filterStaffId = nil
        orderManager.filterMonth = nil
        orderManager.filterLocation = ""
        orderManager.filterPhotographer = ""
        orderManager.filterConsultant = ""
        orderManager.filterMinCount = nil
        orderManager.filterMaxCount = nil
        orderManager.showCompletedOnly = false
        orderManager.showPendingOnly = false
    }
}

// MARK: - 筛选标签

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OrderListView()
        .environmentObject(AuthManager())
        .environmentObject(OrderManager())
        .environmentObject(SettingsManager())
}
