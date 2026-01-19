import Foundation

// MARK: - 订单服务

/// 处理订单相关的 API 调用
@MainActor
class OrderService {
    static let shared = OrderService()
    
    private init() {}
    
    // MARK: - 订单列表
    
    /// 获取订单列表（支持分页）
    func getOrders(
        limit: Int = 50,
        offset: Int = 0,
        completed: Bool? = nil,
        archived: Bool? = nil,
        month: String? = nil
    ) async throws -> OrdersResponse {
        var endpoint = "/api/orders?limit=\(limit)&offset=\(offset)"
        
        if let completed = completed {
            endpoint += "&completed=\(completed)"
        }
        if let archived = archived {
            endpoint += "&archived=\(archived)"
        }
        if let month = month {
            endpoint += "&month=\(month)"
        }
        
        return try await APIService.shared.request(endpoint: endpoint)
    }
    
    /// 获取单个订单
    func getOrder(id: UUID) async throws -> APIOrder {
        return try await APIService.shared.request(
            endpoint: "/api/orders/\(id.uuidString)"
        )
    }
    
    // MARK: - 订单操作
    
    /// 创建订单
    func createOrder(_ request: CreateOrderRequest) async throws -> APIOrder {
        return try await APIService.shared.request(
            endpoint: "/api/orders",
            method: .post,
            body: request
        )
    }
    
    /// 更新订单
    func updateOrder(id: UUID, request: UpdateOrderRequest) async throws -> APIOrder {
        return try await APIService.shared.request(
            endpoint: "/api/orders/\(id.uuidString)",
            method: .put,
            body: request
        )
    }
    
    /// 删除订单
    func deleteOrder(id: UUID) async throws {
        let _: APIService.DeleteResponse = try await APIService.shared.request(
            endpoint: "/api/orders/\(id.uuidString)",
            method: .delete
        )
    }
    
    // MARK: - 订单状态
    
    /// 标记订单完成
    func completeOrder(id: UUID) async throws {
        try await APIService.shared.requestVoid(
            endpoint: "/api/orders/\(id.uuidString)/complete",
            method: .post
        )
    }
    
    /// 归档订单
    func archiveOrder(id: UUID) async throws {
        try await APIService.shared.requestVoid(
            endpoint: "/api/orders/\(id.uuidString)/archive",
            method: .post
        )
    }
    
    /// 取消归档
    func unarchiveOrder(id: UUID) async throws {
        try await APIService.shared.requestVoid(
            endpoint: "/api/orders/\(id.uuidString)/unarchive",
            method: .post
        )
    }
    
    // MARK: - 历史订单
    
    /// 获取历史订单
    func getHistoryOrders(year: String? = nil) async throws -> [Order] {
        return try await APIService.shared.getHistoryOrders(year: year)
    }
}
