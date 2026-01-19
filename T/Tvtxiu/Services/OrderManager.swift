import Foundation
import SwiftUI

// MARK: - 订单管理器

@MainActor
class OrderManager: ObservableObject {
    @Published var orders: [Order] = []
    @Published var staffList: [User] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // 分页相关
    @Published var isLoadingMore: Bool = false
    @Published var hasMoreData: Bool = true
    private var currentOffset: Int = 0
    private let pageSize: Int = 500  // 一次加载 500 条，基本显示所有订单
    private var totalCount: Int = 0
    
    // 当前用户信息（用于权限控制）
    var currentUserId: UUID?
    var currentUserIsAdmin: Bool = false
    
    // 特殊筛选值：未分配
    static let unassignedFilterId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    
    // 筛选条件
    @Published var searchText: String = ""
    @Published var filterStaffId: UUID?
    @Published var filterMonth: String?
    @Published var showCompletedOnly: Bool = false
    @Published var showPendingOnly: Bool = false
    
    // 高级筛选
    @Published var filterLocation: String = ""
    @Published var filterPhotographer: String = ""
    @Published var filterConsultant: String = ""
    @Published var filterMinCount: Int?
    @Published var filterMaxCount: Int?
    
    init() {
        // 初始化时不加载数据，等待登录后调用 loadFromAPI
    }
    
    // MARK: - API 数据加载
    
    /// 从 API 加载订单和用户列表（首次加载）
    func loadFromAPI() async {
        isLoading = true
        errorMessage = nil
        currentOffset = 0
        hasMoreData = true
        
        // 1. 尝试加载用户列表（管理员功能，普通用户可能没有权限）
        do {
            let usersArray: [APIUser] = try await APIService.shared.request(
                endpoint: "/api/users"
            )
            staffList = usersArray.map { $0.toUser() }
        } catch {
            // 普通用户没有权限获取用户列表，这是正常的
        }
        
        // 2. 加载订单列表（带分页参数）
        do {
            let ordersResponse: OrdersResponse = try await APIService.shared.request(
                endpoint: "/api/orders?limit=\(pageSize)&offset=0"
            )
            orders = ordersResponse.orders.map { convertAPIOrder($0) }
            totalCount = ordersResponse.total
            hasMoreData = orders.count < totalCount
            currentOffset = orders.count
        } catch let error as APIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "加载订单失败: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// 刷新订单列表（重新从头加载）
    func refreshOrders() async {
        currentOffset = 0
        hasMoreData = true
        
        do {
            let ordersResponse: OrdersResponse = try await APIService.shared.request(
                endpoint: "/api/orders?limit=\(pageSize)&offset=0"
            )
            orders = ordersResponse.orders.map { convertAPIOrder($0) }
            totalCount = ordersResponse.total
            hasMoreData = orders.count < totalCount
            currentOffset = orders.count
        } catch {
            errorMessage = "刷新失败: \(error.localizedDescription)"
        }
    }
    
    /// 加载更多订单（无限滚动）
    func loadMore() async {
        guard hasMoreData, !isLoadingMore, !isLoading else { return }
        
        isLoadingMore = true
        defer { isLoadingMore = false }
        
        do {
            let ordersResponse: OrdersResponse = try await APIService.shared.request(
                endpoint: "/api/orders?limit=\(pageSize)&offset=\(currentOffset)"
            )
            let newOrders = ordersResponse.orders.map { convertAPIOrder($0) }
            
            // 追加新订单（去重）
            let existingIds = Set(orders.map { $0.id })
            let uniqueNewOrders = newOrders.filter { !existingIds.contains($0.id) }
            orders.append(contentsOf: uniqueNewOrders)
            
            totalCount = ordersResponse.total
            currentOffset += newOrders.count
            hasMoreData = currentOffset < totalCount
        } catch {
            print("加载更多失败: \(error.localizedDescription)")
        }
    }
    
    /// 检查是否需要加载更多（用于无限滚动）
    func loadMoreIfNeeded(currentItem: Order) {
        // 当显示到最后5个订单时预加载
        guard hasMoreData, !isLoadingMore else { return }
        
        let thresholdIndex = max(0, orders.count - 5)
        if let currentIndex = orders.firstIndex(where: { $0.id == currentItem.id }),
           currentIndex >= thresholdIndex {
            Task {
                await loadMore()
            }
        }
    }
    
    // MARK: - 筛选后的订单列表（根据权限和筛选条件）
    
    var filteredOrders: [Order] {
        // 首先根据权限筛选
        let baseOrders: [Order]
        if currentUserIsAdmin {
            // 管理员可以看到所有订单
            baseOrders = orders
        } else if let userId = currentUserId {
            // 普通用户只能看到自己负责的订单
            baseOrders = orders.filter { $0.assignedTo == userId }
        } else {
            // 未登录或无用户信息，返回空
            baseOrders = []
        }
        
        // 然后应用其他筛选条件
        return baseOrders.filter { order in
            // 搜索文本筛选
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                let matchesSearch = order.orderNumber.lowercased().contains(searchLower) ||
                    order.shootLocation.lowercased().contains(searchLower) ||
                    order.consultant.lowercased().contains(searchLower) ||
                    order.photographer.lowercased().contains(searchLower)
                if !matchesSearch { return false }
            }
            
            // 后期人员筛选
            if let staffId = filterStaffId {
                if staffId == Self.unassignedFilterId {
                    // 未分配：只显示没有分配的订单
                    if order.assignedTo != nil { return false }
                } else {
                    // 特定人员
                    if order.assignedTo != staffId { return false }
                }
            }
            
            // 月份筛选
            if let month = filterMonth {
                if order.assignedMonth != month { return false }
            }
            
            // 地点筛选
            if !filterLocation.isEmpty {
                if !order.shootLocation.lowercased().contains(filterLocation.lowercased()) {
                    return false
                }
            }
            
            // 摄影师筛选
            if !filterPhotographer.isEmpty {
                if !order.photographer.lowercased().contains(filterPhotographer.lowercased()) {
                    return false
                }
            }
            
            // 客服筛选
            if !filterConsultant.isEmpty {
                if !order.consultant.lowercased().contains(filterConsultant.lowercased()) {
                    return false
                }
            }
            
            // 张数范围筛选
            if let minCount = filterMinCount, order.totalCount < minCount {
                return false
            }
            if let maxCount = filterMaxCount, order.totalCount > maxCount {
                return false
            }
            
            // 完成状态筛选
            if showCompletedOnly && !order.isCompleted { return false }
            if showPendingOnly && order.isCompleted { return false }
            
            return true
        }
    }
    
    // MARK: - CRUD 操作
    
    /// 添加订单（同步调用 API）
    func addOrder(_ order: Order) {
        var newOrder = order
        newOrder.createdAt = Date()
        newOrder.updatedAt = Date()
        orders.insert(newOrder, at: 0)
        
        // 异步调用 API
        Task {
            await addOrderAPI(newOrder)
        }
    }
    
    /// 更新订单（同步调用 API）
    func updateOrder(_ order: Order) {
        if let index = orders.firstIndex(where: { $0.id == order.id }) {
            var updatedOrder = order
            updatedOrder.updatedAt = Date()
            orders[index] = updatedOrder
        }
        
        // 异步调用 API
        Task {
            await updateOrderAPI(order)
        }
    }
    
    /// 删除订单
    func deleteOrder(_ order: Order) {
        // 本地删除
        orders.removeAll { $0.id == order.id }
        
        // API 删除
        Task {
            await deleteOrderAPI(order)
        }
    }
    
    /// 删除订单 API
    func deleteOrderAPI(_ order: Order) async {
        do {
            let _: APIService.DeleteResponse = try await APIService.shared.request(
                endpoint: "/api/orders/\(order.id.uuidString)",
                method: .delete
            )
            print("订单删除成功: \(order.orderNumber)")
        } catch {
            print("删除订单失败: \(error)")
            // 失败时重新加载数据
            await loadFromAPI()
        }
    }
    
    /// 标记订单完成（调用 API）
    func markAsCompleted(_ order: Order) async {
        // 先更新本地状态
        if let index = orders.firstIndex(where: { $0.id == order.id }) {
            let completedDate = Date()
            orders[index].isCompleted = true
            orders[index].completedAt = completedDate
            orders[index].updatedAt = completedDate
        }
        
        // 调用 API
        do {
            try await APIService.shared.requestVoid(
                endpoint: "/api/orders/\(order.id.uuidString)/complete",
                method: .post
            )
            ToastManager.shared.success("已完成", message: "订单 \(order.orderNumber) 已标记完成")
        } catch {
            ToastManager.shared.error("操作失败", message: error.localizedDescription)
            // 失败时恢复本地状态
            if let index = orders.firstIndex(where: { $0.id == order.id }) {
                orders[index].isCompleted = false
                orders[index].completedAt = nil
            }
        }
    }
    
    /// 取消完成状态（仅管理员可操作，同时取消归档）
    func markAsIncomplete(_ order: Order) async {
        // 先更新本地状态
        if let index = orders.firstIndex(where: { $0.id == order.id }) {
            orders[index].isCompleted = false
            orders[index].completedAt = nil
            orders[index].updatedAt = Date()
            orders[index].isArchived = false
            orders[index].archiveMonth = nil
        }
        
        // 调用更新 API - 使用 PUT 更新订单状态
        do {
            try await APIService.shared.requestVoid(
                endpoint: "/api/orders/\(order.id.uuidString)",
                method: .put,
                body: ["isCompleted": false, "isArchived": false]
            )
        } catch {
            print("取消完成失败: \(error)")
            await loadFromAPI()
        }
    }
    
    /// 归档订单（调用 API）
    func archiveOrder(_ order: Order) async {
        // 先更新本地状态
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let archiveMonth = formatter.string(from: now)
        
        if let index = orders.firstIndex(where: { $0.id == order.id }) {
            orders[index].isArchived = true
            orders[index].archiveMonth = archiveMonth
            orders[index].updatedAt = now
        }
        
        // 调用 API
        do {
            try await APIService.shared.requestVoid(
                endpoint: "/api/orders/\(order.id.uuidString)/archive",
                method: .post
            )
            ToastManager.shared.success("已归档", message: "订单 \(order.orderNumber) 已归档到 \(archiveMonth)")
        } catch {
            ToastManager.shared.error("归档失败", message: error.localizedDescription)
            // 失败时恢复本地状态
            if let index = orders.firstIndex(where: { $0.id == order.id }) {
                orders[index].isArchived = false
                orders[index].archiveMonth = nil
            }
        }
    }
    
    /// 取消归档（调用 API）
    func unarchiveOrder(_ order: Order) async {
        // 先更新本地状态
        if let index = orders.firstIndex(where: { $0.id == order.id }) {
            orders[index].isArchived = false
            orders[index].archiveMonth = nil
            orders[index].updatedAt = Date()
        }
        
        // 调用 API
        do {
            try await APIService.shared.requestVoid(
                endpoint: "/api/orders/\(order.id.uuidString)/unarchive",
                method: .post
            )
        } catch {
            print("取消归档失败: \(error)")
            // 失败时恢复本地状态
            if let index = orders.firstIndex(where: { $0.id == order.id }) {
                orders[index].isArchived = true
            }
        }
    }
    
    /// 分配订单给后期人员（调用 API）
    func assignOrder(_ order: Order, to staff: User) async {
        // 先更新本地状态
        if let index = orders.firstIndex(where: { $0.id == order.id }) {
            orders[index].assignedTo = staff.id
            orders[index].assignedUserName = staff.displayName
            orders[index].assignedAt = Date()
            orders[index].updatedAt = Date()
        }
        
        // 调用 API
        do {
            try await APIService.shared.requestVoid(
                endpoint: "/api/orders/\(order.id.uuidString)",
                method: .put,
                body: ["assignedTo": staff.id.uuidString]
            )
        } catch {
            print("分配订单失败: \(error)")
            // 失败时恢复本地状态
            if let index = orders.firstIndex(where: { $0.id == order.id }) {
                orders[index].assignedTo = nil
                orders[index].assignedUserName = nil
                orders[index].assignedAt = nil
            }
        }
    }
    
    /// 取消订单分配（调用 API）
    func unassignOrder(_ order: Order) async {
        // 先更新本地状态
        if let index = orders.firstIndex(where: { $0.id == order.id }) {
            orders[index].assignedTo = nil
            orders[index].assignedUserName = nil
            orders[index].assignedAt = nil
            orders[index].updatedAt = Date()
        }
        
        // 调用 API - 使用空字符串表示取消分配
        do {
            try await APIService.shared.requestVoid(
                endpoint: "/api/orders/\(order.id.uuidString)",
                method: .put,
                body: ["assignedTo": ""]
            )
        } catch {
            print("取消分配失败: \(error)")
            await loadFromAPI()
        }
    }
    
    /// 删除用户（同时清除订单分配）
    func deleteStaff(_ staff: User) {
        // 清除该用户相关订单的分配
        for index in orders.indices {
            if orders[index].assignedTo == staff.id {
                orders[index].assignedTo = nil
                orders[index].assignedAt = nil
                orders[index].updatedAt = Date()
            }
        }
        // 从人员列表中删除
        staffList.removeAll { $0.id == staff.id }
    }
    
    /// 删除用户 (通过索引)
    func deleteStaff(at offsets: IndexSet) {
        for index in offsets {
            let staff = staffList[index]
            // 清除该用户相关订单的分配
            for orderIndex in orders.indices {
                if orders[orderIndex].assignedTo == staff.id {
                    orders[orderIndex].assignedTo = nil
                    orders[orderIndex].assignedAt = nil
                    orders[orderIndex].updatedAt = Date()
                }
            }
        }
        staffList.remove(atOffsets: offsets)
    }
    
    // MARK: - 统计数据
    
    /// 获取指定后期人员在指定月份的订单
    func orders(for staffId: UUID, month: String) -> [Order] {
        orders.filter { $0.assignedTo == staffId && $0.assignedMonth == month }
    }
    
    /// 获取指定月份的所有订单
    func orders(for month: String) -> [Order] {
        orders.filter { $0.assignedMonth == month }
    }
    
    /// 按日期分组的订单 (用于日历视图)
    func ordersGroupedByDeadline() -> [Date: [Order]] {
        let calendar = Calendar.current
        var grouped: [Date: [Order]] = [:]
        
        for order in orders where !order.isCompleted {
            if let deadline = order.finalDeadline {
                let day = calendar.startOfDay(for: deadline)
                grouped[day, default: []].append(order)
            }
        }
        
        return grouped
    }
    
    /// 获取今日待交付订单
    var todayOrders: [Order] {
        let today = Calendar.current.startOfDay(for: Date())
        return orders.filter { order in
            guard let deadline = order.finalDeadline, !order.isCompleted else { return false }
            return Calendar.current.startOfDay(for: deadline) == today
        }
    }
    
    /// 获取逾期订单
    var overdueOrders: [Order] {
        orders.filter { $0.isOverdue }
    }
    
    /// 获取即将到期的订单 (指定天数内)
    func upcomingOrders(within days: Int) -> [Order] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let futureDate = calendar.date(byAdding: .day, value: days, to: today) else {
            return []
        }
        
        return orders.filter { order in
            guard let deadline = order.finalDeadline, !order.isCompleted else { return false }
            let deadlineDay = calendar.startOfDay(for: deadline)
            return deadlineDay >= today && deadlineDay <= futureDate
        }
    }
    
    // MARK: - API 转换方法
    
    private func convertAPIOrder(_ apiOrder: APIOrder) -> Order {
        // 使用灵活的日期解析器，支持多种格式
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        // 备用格式器（带微秒）
        let dateFormatterWithFractional = ISO8601DateFormatter()
        dateFormatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // 解析日期的辅助函数
        func parseDate(_ string: String?) -> Date? {
            guard let s = string, !s.isEmpty else { return nil }
            return dateFormatter.date(from: s) ?? dateFormatterWithFractional.date(from: s)
        }
        
        let shootType: ShootType
        if apiOrder.shootType == "婚礼" {
            shootType = .ceremony
        } else {
            shootType = .wedding
        }
        
        return Order(
            id: UUID(uuidString: apiOrder.id) ?? UUID(),
            orderNumber: apiOrder.orderNumber,
            shootDate: apiOrder.shootDate ?? "",
            shootLocation: apiOrder.shootLocation ?? "",
            photographer: apiOrder.photographer ?? "",
            consultant: apiOrder.consultant ?? "",
            totalCount: apiOrder.totalCount,
            extraCount: apiOrder.extraCount,
            hasProduct: apiOrder.hasProduct,
            trialDeadline: parseDate(apiOrder.trialDeadline),
            finalDeadline: parseDate(apiOrder.finalDeadline),
            weddingDate: apiOrder.weddingDate ?? "",
            isRepeatCustomer: apiOrder.isRepeatCustomer,
            requirements: apiOrder.requirements ?? "",
            panLink: apiOrder.panLink ?? "",
            panCode: apiOrder.panCode ?? "",
            assignedTo: apiOrder.assignedTo.flatMap { UUID(uuidString: $0) },
            assignedUserName: {
                if let user = apiOrder.assignedUser {
                    return user.realName?.isEmpty == false ? user.realName : user.nickname
                }
                return nil
            }(),
            assignedAt: parseDate(apiOrder.assignedAt),
            remarks: apiOrder.remarks ?? "",
            isCompleted: apiOrder.isCompleted,
            completedAt: parseDate(apiOrder.completedAt),
            shootType: shootType,
            isInGroup: apiOrder.isInGroup,
            isUrgent: apiOrder.isUrgent,
            isComplaint: apiOrder.isComplaint,
            isArchived: apiOrder.isArchived,
            archiveMonth: apiOrder.archiveMonth ?? ""
        )
    }
    
    // MARK: - API 操作方法
    
    /// 添加订单 (通过 API)
    func addOrderAPI(_ order: Order) async {
        do {
            let request = CreateOrderRequest(
                orderNumber: order.orderNumber,
                shootDate: order.shootDate,
                shootLocation: order.shootLocation,
                photographer: order.photographer,
                consultant: order.consultant,
                totalCount: order.totalCount,
                extraCount: order.extraCount,
                hasProduct: order.hasProduct,
                trialDeadline: order.trialDeadline?.ISO8601Format(),
                finalDeadline: order.finalDeadline?.ISO8601Format(),
                weddingDate: order.weddingDate,
                isRepeatCustomer: order.isRepeatCustomer,
                requirements: order.requirements,
                panLink: order.panLink,
                panCode: order.panCode,
                assignedTo: order.assignedTo?.uuidString,
                remarks: order.remarks,
                shootType: order.shootType.rawValue,
                isInGroup: order.isInGroup,
                isUrgent: order.isUrgent,
                isComplaint: order.isComplaint
            )
            
            let _: APIOrder = try await APIService.shared.request(
                endpoint: "/api/orders",
                method: .post,
                body: request
            )
            
            await refreshOrders()
        } catch {
            errorMessage = "创建订单失败: \(error.localizedDescription)"
        }
    }
    
    /// 更新订单 (通过 API)
    func updateOrderAPI(_ order: Order) async {
        do {
            let request = UpdateOrderRequest(
                orderNumber: order.orderNumber,
                shootDate: order.shootDate,
                shootLocation: order.shootLocation,
                photographer: order.photographer,
                consultant: order.consultant,
                totalCount: order.totalCount,
                extraCount: order.extraCount,
                hasProduct: order.hasProduct,
                trialDeadline: order.trialDeadline?.ISO8601Format(),
                finalDeadline: order.finalDeadline?.ISO8601Format(),
                weddingDate: order.weddingDate,
                isRepeatCustomer: order.isRepeatCustomer,
                requirements: order.requirements,
                panLink: order.panLink,
                panCode: order.panCode,
                assignedTo: order.assignedTo?.uuidString,
                remarks: order.remarks,
                shootType: order.shootType.rawValue,
                isInGroup: order.isInGroup,
                isUrgent: order.isUrgent,
                isComplaint: order.isComplaint
            )
            
            let _: APIOrder = try await APIService.shared.request(
                endpoint: "/api/orders/\(order.id.uuidString)",
                method: .put,
                body: request
            )
            
            await refreshOrders()
        } catch {
            errorMessage = "更新订单失败: \(error.localizedDescription)"
        }
    }
    
    /// 完成订单 (通过 API)
    func completeOrderAPI(_ order: Order) async {
        do {
            let _: MessageResponse = try await APIService.shared.request(
                endpoint: "/api/orders/\(order.id.uuidString)/complete",
                method: .put
            )
            await refreshOrders()
        } catch {
            errorMessage = "完成订单失败: \(error.localizedDescription)"
        }
    }
    
    /// 归档订单 (通过 API)
    func archiveOrderAPI(_ order: Order) async {
        do {
            let _: MessageResponse = try await APIService.shared.request(
                endpoint: "/api/orders/\(order.id.uuidString)/archive",
                method: .put
            )
            await refreshOrders()
        } catch {
            errorMessage = "归档订单失败: \(error.localizedDescription)"
        }
    }
    
    /// 取消归档 (通过 API)
    func unarchiveOrderAPI(_ order: Order) async {
        do {
            let _: MessageResponse = try await APIService.shared.request(
                endpoint: "/api/orders/\(order.id.uuidString)/unarchive",
                method: .put
            )
            await refreshOrders()
        } catch {
            errorMessage = "取消归档失败: \(error.localizedDescription)"
        }
    }
}
