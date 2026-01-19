import SwiftUI

// MARK: - 拍摄统计视图

/// 拍摄订单统计页面（管理员专用）
struct ShootingStatsView: View {
    @EnvironmentObject var authManager: AuthManager
    
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var stats: ShootingStats?
    @State private var orders: [ShootingOrder] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    
    // 筛选和搜索
    @State private var searchText: String = ""
    @State private var matchedFilter: MatchedFilter = .all
    @State private var sortAscending: Bool = false
    
    // 分页
    @State private var displayLimit: Int = 20
    @State private var totalCount: Int = 0
    
    // 编辑弹窗
    @State private var selectedOrder: ShootingOrder?
    
    private let availableYears = [2024, 2025, 2026, 2027]
    
    enum MatchedFilter: String, CaseIterable {
        case all = "全部"
        case matched = "已分配"
        case completed = "已完成"
        case unmatched = "未分配"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            toolbar
            
            if isLoading && orders.isEmpty {
                Spacer()
                ProgressView("加载中...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                TvtErrorState(error: error) { loadData() }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: TvtDesign.Spacing.xl) {
                        // 统计卡片
                        if let stats = stats {
                            statsCards(stats)
                        }
                        
                        // 订单列表
                        ordersSection
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("拍摄统计")
        .onAppear { loadData() }
        .onChange(of: selectedYear) { _ in resetAndLoad() }
        .onChange(of: matchedFilter) { _ in resetAndLoad() }
        .onChange(of: sortAscending) { _ in resetAndLoad() }
        .sheet(item: $selectedOrder) { order in
            ShootingOrderEditSheet(order: order) { updatedOrder in
                if let index = orders.firstIndex(where: { $0.id == updatedOrder.id }) {
                    orders[index] = updatedOrder
                }
                loadStats()
            }
        }
    }
    
    // MARK: - 工具栏
    
    private var toolbar: some View {
        VStack(spacing: TvtDesign.Spacing.sm) {
            // 第一行：年份 + 筛选 + 排序 + 导出
            HStack {
                // 年份选择
                Picker("年份", selection: $selectedYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text("\(year)年").tag(year)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                
                Spacer()
                
                // 分配状态筛选
                Picker("状态", selection: $matchedFilter) {
                    ForEach(MatchedFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                
                // 排序按钮
                Button {
                    sortAscending.toggle()
                } label: {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                    Text(sortAscending ? "升序" : "降序")
                }
                .buttonStyle(.bordered)
                
                // 导出按钮
                Button {
                    exportToCSV()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                    Text("导出")
                }
                .buttonStyle(.bordered)
                
                // 同步匹配按钮
                Button {
                    syncMatches()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("同步匹配")
                }
                .buttonStyle(.bordered)
                .tint(.green)
                
                // 刷新
                Button { loadData() } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            
            // 第二行：搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索订单号、地点、摄影师...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit { resetAndLoad() }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        resetAndLoad()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(TvtDesign.Colors.tertiaryBackground)
            .cornerRadius(8)
        }
        .padding()
        .background(TvtDesign.Colors.secondaryBackground)
    }
    
    // MARK: - 统计卡片
    
    private func statsCards(_ stats: ShootingStats) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: TvtDesign.Spacing.lg) {
            // 拍摄订单 - 点击显示全部
            StatCardItem(title: "拍摄订单", value: stats.totalShooting, icon: "camera.fill", color: .blue, 
                        percentage: nil, isSelected: matchedFilter == .all)
                .onTapGesture { matchedFilter = .all }
            
            // 已分配后期 - 点击筛选已分配
            StatCardItem(title: "已分配后期", value: stats.totalAssigned, icon: "person.badge.plus", color: .purple,
                        percentage: stats.totalShooting > 0 ? Double(stats.totalAssigned) / Double(stats.totalShooting) * 100 : nil,
                        isSelected: matchedFilter == .matched)
                .onTapGesture { matchedFilter = .matched }
            
            // 已完成 - 点击筛选已完成
            StatCardItem(title: "已完成", value: stats.totalCompleted, icon: "checkmark.circle.fill", color: .green,
                        percentage: stats.totalShooting > 0 ? Double(stats.totalCompleted) / Double(stats.totalShooting) * 100 : nil,
                        isSelected: matchedFilter == .completed)
                .onTapGesture { matchedFilter = .completed }
            
            // 待分配 - 点击筛选未分配
            StatCardItem(title: "待分配", value: stats.totalPending, icon: "clock.fill", color: .orange,
                        percentage: stats.totalShooting > 0 ? Double(stats.totalPending) / Double(stats.totalShooting) * 100 : nil,
                        isSelected: matchedFilter == .unmatched)
                .onTapGesture { matchedFilter = .unmatched }
        }
    }
    
    // MARK: - 订单列表
    
    private var ordersSection: some View {
        VStack(alignment: .leading, spacing: TvtDesign.Spacing.md) {
            HStack {
                Text("拍摄订单")
                    .font(TvtDesign.Typography.title3)
                TvtCountBadge(count: totalCount, color: .blue)
                Spacer()
                Text("显示 \(min(orders.count, displayLimit)) / \(totalCount)")
                    .font(TvtDesign.Typography.caption)
                    .foregroundColor(.secondary)
            }
            
            if orders.isEmpty {
                Text("暂无数据")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                LazyVStack(spacing: TvtDesign.Spacing.sm) {
                    ForEach(orders.prefix(displayLimit), id: \.id) { order in
                        ShootingOrderRow(order: order)
                            .onTapGesture {
                                selectedOrder = order
                            }
                    }
                }
                
                // 加载更多按钮
                if orders.count > displayLimit || totalCount > displayLimit {
                    Button {
                        displayLimit += 20
                        if orders.count < displayLimit {
                            loadMoreOrders()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("加载更多")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top)
                }
            }
        }
        .padding()
        .background(TvtDesign.Colors.cardBackground)
        .cornerRadius(TvtDesign.CornerRadius.md)
    }
    
    // MARK: - 数据加载
    
    private func resetAndLoad() {
        displayLimit = 20
        loadData()
    }
    
    private func loadData() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                async let statsTask: ShootingStats = APIService.shared.request(
                    endpoint: "/api/shooting/stats?year=\(selectedYear)"
                )
                async let ordersTask: ShootingOrdersResponse = loadOrdersFromAPI(limit: displayLimit, offset: 0)
                
                let (statsData, ordersData) = try await (statsTask, ordersTask)
                
                await MainActor.run {
                    self.stats = statsData
                    self.orders = ordersData.orders
                    self.totalCount = ordersData.total
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadStats() {
        Task {
            if let statsData: ShootingStats = try? await APIService.shared.request(
                endpoint: "/api/shooting/stats?year=\(selectedYear)"
            ) {
                await MainActor.run {
                    self.stats = statsData
                }
            }
        }
    }
    
    private func loadMoreOrders() {
        Task {
            let response: ShootingOrdersResponse = try await loadOrdersFromAPI(limit: 20, offset: orders.count)
            await MainActor.run {
                self.orders.append(contentsOf: response.orders)
            }
        }
    }
    
    private func loadOrdersFromAPI(limit: Int, offset: Int) async throws -> ShootingOrdersResponse {
        var params = "year=\(selectedYear)&limit=\(limit)&offset=\(offset)"
        params += "&sort=\(sortAscending ? "asc" : "desc")"
        
        if matchedFilter == .matched {
            params += "&matched=true"
        } else if matchedFilter == .unmatched {
            params += "&matched=false"
        } else if matchedFilter == .completed {
            params += "&completed=true"
        }
        
        if !searchText.isEmpty {
            params += "&search=\(searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        
        return try await APIService.shared.request(endpoint: "/api/shooting/orders?\(params)")
    }
    
    private func exportToCSV() {
        var params = "year=\(selectedYear)"
        if matchedFilter == .matched { params += "&matched=true" }
        else if matchedFilter == .unmatched { params += "&matched=false" }
        if !searchText.isEmpty { params += "&search=\(searchText)" }
        
        let urlString = "\(APIService.shared.currentBaseURL)/api/shooting/orders/export?\(params)"
        if let url = URL(string: urlString) {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
    }
    
    private func syncMatches() {
        Task {
            do {
                struct SyncResponse: Codable {
                    let message: String
                    let totalMatched: Int?
                    let exactMatched: Int?
                    let fuzzyMatched: Int?
                    let prefixMatched: Int?
                    // 兼容旧版本
                    let matched: Int?
                }
                
                let response: SyncResponse = try await APIService.shared.request(
                    endpoint: "/api/shooting/sync-matches",
                    method: .post
                )
                
                let matchedCount = response.totalMatched ?? response.matched ?? 0
                
                await MainActor.run {
                    // 显示同步结果
                    if matchedCount > 0 {
                        // 刷新数据
                        loadData()
                    }
                }
            } catch {
                print("Sync failed: \(error)")
            }
        }
    }
}

// MARK: - 统计卡片项

struct StatCardItem: View {
    let title: String
    let value: Int
    let icon: String
    let color: Color
    let percentage: Double?
    var isSelected: Bool = false
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: TvtDesign.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
                if let pct = percentage {
                    Text(String(format: "%.0f%%", pct))
                        .font(TvtDesign.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text("\(value)")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(color)
            
            Text(title)
                .font(TvtDesign.Typography.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(isSelected ? color.opacity(0.15) : (isHovered ? TvtDesign.Colors.cardBackgroundHover : TvtDesign.Colors.cardBackground))
        .cornerRadius(TvtDesign.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: TvtDesign.CornerRadius.md)
                .stroke(isSelected ? color : .clear, lineWidth: 2)
        )
        .shadow(color: TvtDesign.Shadow.sm.color, radius: TvtDesign.Shadow.sm.radius)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(TvtDesign.Animation.fast, value: isHovered)
        .animation(TvtDesign.Animation.fast, value: isSelected)
        .onHover { hovering in isHovered = hovering }
        .contentShape(Rectangle())
    }
}

// MARK: - 拍摄订单行

struct ShootingOrderRow: View {
    let order: ShootingOrder
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: TvtDesign.Spacing.xxs) {
                Text(order.orderNumber)
                    .font(TvtDesign.Typography.headline)
                
                HStack(spacing: TvtDesign.Spacing.sm) {
                    Label(order.location, systemImage: "mappin")
                    Label("\(order.shootMonth)月\(order.shootDay)日", systemImage: "calendar")
                    if !order.photographer.isEmpty {
                        Label(order.photographer, systemImage: "camera")
                    }
                }
                .font(TvtDesign.Typography.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 右侧：分配状态 + 后期人员 + 归档月份
            VStack(alignment: .trailing, spacing: TvtDesign.Spacing.xxs) {
                if let matched = order.matchedOrder {
                    // 已分配 - 显示后期人员
                    HStack(spacing: TvtDesign.Spacing.xs) {
                if let user = matched.assignedUser, let name = user.nickname {
                            Text("后期: \(name)")
                                .font(TvtDesign.Typography.caption)
                                .foregroundColor(.secondary)
                        }
                        TvtBadge(text: "已分配", color: .green, style: .subtle)
                    }
                    
                    // 归档月份
                    if let archiveMonth = matched.archiveMonth, !archiveMonth.isEmpty {
                        Text("归档: \(archiveMonth)")
                            .font(TvtDesign.Typography.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    TvtBadge(text: "待分配", color: .orange, style: .subtle)
                }
            }
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(TvtDesign.Colors.tertiaryBackground)
        .cornerRadius(TvtDesign.CornerRadius.sm)
        .contentShape(Rectangle())
    }
}

// MARK: - 编辑弹窗

struct ShootingOrderEditSheet: View {
    let order: ShootingOrder
    let onSave: (ShootingOrder) -> Void
    
    @Environment(\.dismiss) var dismiss
    
    @State private var orderNumber: String
    @State private var shootYear: Int
    @State private var shootMonth: Int
    @State private var shootDay: String
    @State private var location: String
    @State private var country: String
    @State private var orderType: String
    @State private var photographer: String
    @State private var sales: String
    @State private var consultant: String
    @State private var selectedStaffIdString: String = ""
    
    @State private var staffList: [StaffInfo] = []
    @State private var isLoadingStaff: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    
    struct StaffInfo: Codable, Identifiable {
        let id: UUID
        let nickname: String
    }
    
    init(order: ShootingOrder, onSave: @escaping (ShootingOrder) -> Void) {
        self.order = order
        self.onSave = onSave
        _orderNumber = State(initialValue: order.orderNumber)
        _shootYear = State(initialValue: order.shootYear)
        _shootMonth = State(initialValue: order.shootMonth)
        _shootDay = State(initialValue: order.shootDay)
        _location = State(initialValue: order.location)
        _country = State(initialValue: order.country)
        _orderType = State(initialValue: order.orderType)
        _photographer = State(initialValue: order.photographer)
        _sales = State(initialValue: order.sales ?? "")
        _consultant = State(initialValue: order.consultant ?? "")
        _selectedStaffIdString = State(initialValue: order.matchedOrder?.assignedUser?.id?.uuidString ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("订单信息") {
                    LabeledContent("订单编号") {
                        TextField("", text: $orderNumber)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("年份", selection: $shootYear) {
                        ForEach(2020...2030, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    Picker("月份", selection: $shootMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text("\(month)月").tag(month)
                        }
                    }
                    LabeledContent("拍摄日期") {
                        TextField("如: 4 或 4-5", text: $shootDay)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("地点") {
                    LabeledContent("拍摄地点") {
                        TextField("", text: $location)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("国家/地区") {
                        TextField("", text: $country)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("人员") {
                    LabeledContent("摄影师") {
                        TextField("", text: $photographer)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("销售") {
                        TextField("", text: $sales)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("顾问") {
                        TextField("", text: $consultant)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("后期分配") {
                    if isLoadingStaff {
                        ProgressView("加载员工列表...")
                    } else {
                        Picker("后期人员", selection: $selectedStaffIdString) {
                            Text("未分配").tag("")
                            ForEach(staffList) { staff in
                                Text(staff.nickname).tag(staff.id.uuidString)
                            }
                        }
                    }
                }
                
                Section("类型") {
                    LabeledContent("拍摄类型") {
                        TextField("", text: $orderType)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("编辑拍摄订单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveOrder() }
                        .disabled(isSaving)
                }
            }
            .onAppear {
                loadStaffList()
            }
        }
        .frame(minWidth: 450, minHeight: 550)
    }
    
    private func loadStaffList() {
        isLoadingStaff = true
        Task {
            do {
                // API 返回用户数组而非对象
                let users: [StaffInfo] = try await APIService.shared.request(endpoint: "/api/users")
                await MainActor.run {
                    self.staffList = users
                    self.isLoadingStaff = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingStaff = false
                    print("Load staff failed: \(error)")
                }
            }
        }
    }
    
    private func saveOrder() {
        isSaving = true
        errorMessage = nil
        
        Task {
            do {
                struct UpdateRequest: Encodable {
                    let orderNumber: String
                    let shootYear: Int
                    let shootMonth: Int
                    let shootDay: String
                    let location: String
                    let country: String
                    let orderType: String
                    let photographer: String
                    let sales: String
                    let consultant: String
                    let assignedStaffId: String?
                }
                
                let request = UpdateRequest(
                    orderNumber: orderNumber,
                    shootYear: shootYear,
                    shootMonth: shootMonth,
                    shootDay: shootDay,
                    location: location,
                    country: country,
                    orderType: orderType,
                    photographer: photographer,
                    sales: sales,
                    consultant: consultant,
                    assignedStaffId: selectedStaffIdString.isEmpty ? nil : selectedStaffIdString
                )
                
                let updated: ShootingOrder = try await APIService.shared.request(
                    endpoint: "/api/shooting/orders/\(order.id)",
                    method: .put,
                    body: request
                )
                
                await MainActor.run {
                    onSave(updated)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "保存失败: \(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }
}

// MARK: - 数据模型

struct ShootingStats: Codable {
    let year: Int?
    let month: Int?
    let totalShooting: Int
    let totalAssigned: Int
    let totalCompleted: Int
    let totalPending: Int
}

struct ShootingOrder: Codable, Identifiable {
    let id: UUID
    let orderNumber: String
    let shootYear: Int
    let shootMonth: Int
    let shootDay: String
    let shootDate: Date?
    let location: String
    let country: String
    let orderType: String
    let photographer: String
    let sales: String?
    let consultant: String?
    let syncedAt: Date?
    let matchedOrderId: UUID?
    let matchedOrder: MatchedOrderInfo?
    
    // 嵌套的后期订单信息（只包含需要的字段）
    struct MatchedOrderInfo: Codable {
        let id: UUID?
        let archiveMonth: String?
        let isCompleted: Bool?
        let assignedUser: AssignedUserInfo?
        
        struct AssignedUserInfo: Codable {
            let id: UUID?
            let nickname: String?  // 后端返回 nickname 而非 name
        }
    }
}

struct ShootingOrdersResponse: Codable {
    let orders: [ShootingOrder]
    let total: Int
    let limit: Int?
    let offset: Int?
}

// MARK: - 预览

#Preview {
    ShootingStatsView()
        .environmentObject(AuthManager())
        .frame(width: 1000, height: 700)
}
