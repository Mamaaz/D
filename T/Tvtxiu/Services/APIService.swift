import Foundation

// MARK: - API 服务

@MainActor
class APIService: ObservableObject {
    static let shared = APIService()
    
    @Published var isConnected: Bool = false
    @Published var connectionError: String?
    
    private(set) var baseURL: String = "http://localhost:8080"
    private var authToken: String?
    
    private init() {}
    
    // MARK: - 配置
    
    func configure(baseURL: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    
    func setAuthToken(_ token: String?) {
        self.authToken = token
    }
    
    var currentBaseURL: String {
        baseURL
    }
    
    var currentAuthToken: String? {
        authToken
    }
    
    // MARK: - 通用请求方法
    
    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if requiresAuth, let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        // 检查连接状态
        isConnected = true
        connectionError = nil
        
        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 422:
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw APIError.validationError(errorResponse.error)
            }
            throw APIError.validationError("验证失败")
        case 500...599:
            throw APIError.serverError
        default:
            throw APIError.unknown(httpResponse.statusCode)
        }
    }
    
    // 无返回值的请求
    func requestVoid(
        endpoint: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if requiresAuth, let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        isConnected = true
        connectionError = nil
        
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 422:
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw APIError.validationError(errorResponse.error)
            }
            throw APIError.validationError("验证失败")
        case 500...599:
            throw APIError.serverError
        default:
            throw APIError.unknown(httpResponse.statusCode)
        }
    }
    
    // MARK: - 连接测试
    
    func testConnection() async -> Bool {
        do {
            let _: LoginResponse = try await request(
                endpoint: "/api/auth/login",
                method: .post,
                body: LoginRequest(username: "admin", password: "admin"),
                requiresAuth: false
            )
            isConnected = true
            connectionError = nil
            return true
        } catch {
            isConnected = false
            connectionError = error.localizedDescription
            return false
        }
    }
    
    // MARK: - 头像上传
    
    func uploadAvatar(userId: String, imageData: Data) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/users/\(userId)/avatar") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // 添加认证头
        if let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // 创建 multipart/form-data 请求
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        
        struct AvatarResponse: Decodable {
            let message: String
            let avatarUrl: String
        }
        
        let result = try JSONDecoder().decode(AvatarResponse.self, from: data)
        return result.avatarUrl
    }
    
    // MARK: - 历史订单
    
    /// 获取历史订单（归档超过12个月的订单）
    func getHistoryOrders(year: String? = nil) async throws -> [Order] {
        var endpoint = "/api/orders/history"
        if let year = year {
            endpoint += "?year=\(year)"
        }
        
        struct HistoryResponse: Decodable {
            let orders: [APIHistoryOrder]
            let total: Int
        }
        
        struct APIHistoryOrder: Decodable {
            let id: String
            let orderNumber: String
            let shootDate: String?
            let shootLocation: String?
            let photographer: String?
            let consultant: String?
            let totalCount: Int
            let extraCount: Int
            let hasProduct: Bool
            let trialDeadline: String?
            let finalDeadline: String?
            let weddingDate: String?
            let isRepeatCustomer: Bool
            let requirements: String?
            let panLink: String?
            let panCode: String?
            let assignedTo: String?
            let assignedAt: String?
            let remarks: String?
            let isCompleted: Bool
            let completedAt: String?
            let shootType: String
            let isInGroup: Bool
            let isUrgent: Bool
            let isComplaint: Bool
            let isArchived: Bool
            let archiveMonth: String?
        }
        
        let response: HistoryResponse = try await request(endpoint: endpoint)
        
        // 转换为本地 Order 模型
        return response.orders.map { apiOrder in
            let shootType: ShootType = apiOrder.shootType == "婚礼" ? .ceremony : .wedding
            
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
                trialDeadline: nil,
                finalDeadline: nil,
                weddingDate: apiOrder.weddingDate ?? "",
                isRepeatCustomer: apiOrder.isRepeatCustomer,
                requirements: apiOrder.requirements ?? "",
                panLink: apiOrder.panLink ?? "",
                panCode: apiOrder.panCode ?? "",
                assignedTo: apiOrder.assignedTo.flatMap { UUID(uuidString: $0) },
                assignedUserName: nil,
                assignedAt: nil,
                remarks: apiOrder.remarks ?? "",
                isCompleted: apiOrder.isCompleted,
                completedAt: nil,
                shootType: shootType,
                isInGroup: apiOrder.isInGroup,
                isUrgent: apiOrder.isUrgent,
                isComplaint: apiOrder.isComplaint,
                isArchived: apiOrder.isArchived,
                archiveMonth: apiOrder.archiveMonth ?? ""
            )
        }
    }
    
    // MARK: - 迁移数据导入
    
    func importMigrationData(data: Data) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/import/migration") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // 添加认证头
        if let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // 创建 multipart/form-data 请求
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"migration.json\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        
        if httpResponse.statusCode >= 400 {
            // 尝试解析错误信息
            struct ErrorMsg: Codable {
                let error: String
            }
            if let errorMsg = try? JSONDecoder().decode(ErrorMsg.self, from: responseData) {
                throw APIError.validationError(errorMsg.error)
            }
            throw APIError.unknown(httpResponse.statusCode)
        }
        
        struct MigrationResponse: Codable {
            let message: String
            let usersImported: Int
            let usersFailed: Int
            let ordersImported: Int
            let ordersFailed: Int
        }
        
        let result = try JSONDecoder().decode(MigrationResponse.self, from: responseData)
        return result.message
    }
    
    // MARK: - 完整备份（含头像）
    
    /// 下载完整备份 ZIP
    func downloadBackup() async throws -> Data {
        guard let url = URL(string: "\(baseURL)/api/data/backup") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // 添加认证
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        
        if httpResponse.statusCode >= 400 {
            throw APIError.validationError("下载备份失败")
        }
        
        return data
    }
    
    /// 恢复完整备份 ZIP
    func restoreBackup(data: Data) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/data/restore") else {
            throw APIError.invalidURL
        }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // 添加认证
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // 构建 multipart body
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"backup.zip\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/zip\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        
        if httpResponse.statusCode >= 400 {
            if let errorStr = String(data: responseData, encoding: .utf8) {
                throw APIError.validationError(errorStr)
            }
            throw APIError.validationError("恢复失败")
        }
        
        struct RestoreResponse: Codable {
            let message: String
            let usersImported: Int
            let usersFailed: Int
            let ordersImported: Int
            let ordersFailed: Int
            let avatarsRestored: Int
        }
        
        let result = try JSONDecoder().decode(RestoreResponse.self, from: responseData)
        return "导入用户: \(result.usersImported)\n导入订单: \(result.ordersImported)\n恢复头像: \(result.avatarsRestored)"
    }
    
    // MARK: - 删除所有数据
    
    struct DeleteResponse: Codable {
        let message: String
        let deleted: Int
    }
    
    func deleteAllData() async throws {
        let _: DeleteResponse = try await request(
            endpoint: "/api/data/delete-all",
            method: .delete
        )
    }
    
    // MARK: - 删除用户
    
    func deleteUser(id: UUID) async throws {
        let _: DeleteResponse = try await request(
            endpoint: "/api/users/\(id.uuidString)",
            method: .delete
        )
    }
    
    // MARK: - Excel 导入
    
    func importExcel(data: Data, filename: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/import/excel") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var bodyData = Data()
        bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        bodyData.append("Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n\r\n".data(using: .utf8)!)
        bodyData.append(data)
        bodyData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = bodyData
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let message = json["message"] as? String {
                return message
            }
            return "导入成功"
        } else {
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let error = json["error"] as? String {
                throw APIError.validationError(error)
            }
            throw APIError.unknown(httpResponse.statusCode)
        }
    }
}

// MARK: - HTTP 方法

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

// MARK: - API 错误

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case validationError(String)
    case serverError
    case networkError(Error)
    case decodingError(Error)
    case unknown(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .invalidResponse:
            return "无效的响应"
        case .unauthorized:
            return "未授权，请重新登录"
        case .forbidden:
            return "没有权限执行此操作"
        case .notFound:
            return "资源不存在"
        case .validationError(let message):
            return message
        case .serverError:
            return "服务器错误"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .decodingError(let error):
            return "数据解析错误: \(error.localizedDescription)"
        case .unknown(let code):
            return "未知错误 (\(code))"
        }
    }
}

// MARK: - API 响应模型

struct APIErrorResponse: Decodable {
    let error: String
}

struct LoginRequest: Encodable {
    let username: String
    let password: String
}

struct LoginResponse: Decodable {
    let token: String
    let user: APIUser
}

struct APIUser: Decodable {
    let id: String
    let username: String
    let nickname: String
    let realName: String?
    let role: String
    
    // 绩效配置
    let basePrice: Double?
    let groupBonus: Double?
    let urgentBonus: Double?
    let complaintBonus: Double?
    let weddingMultiplier: Double?
    
    // 日历颜色
    let calendarColorRed: Double?
    let calendarColorGreen: Double?
    let calendarColorBlue: Double?
    let avatarUrl: String?
    
    // 人员状态
    let isHidden: Bool?
    let leftAt: String?
    
    let createdAt: String
    
    /// 转换为本地 User 模型
    func toUser() -> User {
        let userRole: UserRole
        switch role {
        case "admin":
            userRole = .admin
        case "sub_admin":
            userRole = .subAdmin
        case "outsource":
            userRole = .outsource
        default:
            userRole = .staff
        }
        
        // 解析离职时间
        var leftAtDate: Date? = nil
        if let leftAtStr = leftAt {
            let formatter = ISO8601DateFormatter()
            leftAtDate = formatter.date(from: leftAtStr)
        }
        
        return User(
            id: UUID(uuidString: id) ?? UUID(),
            username: username,
            nickname: nickname,
            realName: realName ?? "",
            role: userRole,
            isHidden: isHidden ?? false,
            leftAt: leftAtDate,
            basePrice: basePrice ?? 8.0,
            groupBonus: groupBonus ?? 2.0,
            urgentBonus: urgentBonus ?? 5.0,
            complaintBonus: complaintBonus ?? 8.0,
            weddingMultiplier: weddingMultiplier ?? 0.8,
            calendarColorRed: calendarColorRed ?? 0.5,
            calendarColorGreen: calendarColorGreen ?? 0.5,
            calendarColorBlue: calendarColorBlue ?? 0.5,
            avatarUrl: avatarUrl
        )
    }
}

struct APIOrder: Decodable {
    let id: String
    let orderNumber: String
    let shootDate: String?
    let shootLocation: String?
    let photographer: String?
    let consultant: String?
    let totalCount: Int
    let extraCount: Int
    let hasProduct: Bool
    let trialDeadline: String?
    let finalDeadline: String?
    let weddingDate: String?
    let isRepeatCustomer: Bool
    let requirements: String?
    let panLink: String?
    let panCode: String?
    let assignedTo: String?
    let assignedAt: String?
    let remarks: String?
    let remarksHistory: String? // JSON array of timestamps
    let isCompleted: Bool
    let completedAt: String?
    let shootType: String?
    let isInGroup: Bool
    let isUrgent: Bool
    let isComplaint: Bool
    let isArchived: Bool
    let archiveMonth: String?
    let createdBy: String?
    let createdAt: String
    let updatedAt: String
    let assignedUser: APIUser?
}

struct CreateOrderRequest: Encodable {
    let orderNumber: String
    let shootDate: String?
    let shootLocation: String?
    let photographer: String?
    let consultant: String?
    let totalCount: Int
    let extraCount: Int
    let hasProduct: Bool
    let trialDeadline: String?
    let finalDeadline: String?
    let weddingDate: String?
    let isRepeatCustomer: Bool
    let requirements: String?
    let panLink: String?
    let panCode: String?
    let assignedTo: String?
    let remarks: String?
    let shootType: String?
    let isInGroup: Bool
    let isUrgent: Bool
    let isComplaint: Bool
}

struct UpdateOrderRequest: Encodable {
    let orderNumber: String?
    let shootDate: String?
    let shootLocation: String?
    let photographer: String?
    let consultant: String?
    let totalCount: Int?
    let extraCount: Int?
    let hasProduct: Bool?
    let trialDeadline: String?
    let finalDeadline: String?
    let weddingDate: String?
    let isRepeatCustomer: Bool?
    let requirements: String?
    let panLink: String?
    let panCode: String?
    let assignedTo: String?
    let remarks: String?
    let shootType: String?
    let isInGroup: Bool?
    let isUrgent: Bool?
    let isComplaint: Bool?
}

struct OrdersResponse: Decodable {
    let orders: [APIOrder]
    let total: Int
}

struct UsersResponse: Decodable {
    let users: [APIUser]
}

struct MessageResponse: Decodable {
    let message: String
}
