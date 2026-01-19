import Foundation

// MARK: - 用户服务

/// 处理用户管理相关的 API 调用
@MainActor
class UserService {
    static let shared = UserService()
    
    private init() {}
    
    // MARK: - 用户列表
    
    /// 获取所有用户（仅管理员）
    func getUsers() async throws -> [User] {
        let usersArray: [APIUser] = try await APIService.shared.request(
            endpoint: "/api/users"
        )
        return usersArray.map { $0.toUser() }
    }
    
    /// 获取单个用户
    func getUser(id: UUID) async throws -> User {
        let apiUser: APIUser = try await APIService.shared.request(
            endpoint: "/api/users/\(id.uuidString)"
        )
        return apiUser.toUser()
    }
    
    // MARK: - 用户操作
    
    /// 创建用户
    func createUser(username: String, password: String, role: String, basePrice: Double = 8.0) async throws -> User {
        struct CreateUserRequest: Encodable {
            let username: String
            let password: String
            let role: String
            let basePrice: Double
        }
        
        let request = CreateUserRequest(
            username: username,
            password: password,
            role: role,
            basePrice: basePrice
        )
        
        let apiUser: APIUser = try await APIService.shared.request(
            endpoint: "/api/users",
            method: .post,
            body: request
        )
        return apiUser.toUser()
    }
    
    /// 更新用户
    func updateUser(id: UUID, updates: [String: Any]) async throws -> User {
        struct UpdateUserRequest: Encodable {
            let username: String?
            let nickname: String?
            let role: String?
            let basePrice: Double?
            let groupBonus: Double?
            let urgentBonus: Double?
            let complaintBonus: Double?
            let weddingMultiplier: Double?
        }
        
        let request = UpdateUserRequest(
            username: updates["username"] as? String,
            nickname: updates["nickname"] as? String,
            role: updates["role"] as? String,
            basePrice: updates["basePrice"] as? Double,
            groupBonus: updates["groupBonus"] as? Double,
            urgentBonus: updates["urgentBonus"] as? Double,
            complaintBonus: updates["complaintBonus"] as? Double,
            weddingMultiplier: updates["weddingMultiplier"] as? Double
        )
        
        let apiUser: APIUser = try await APIService.shared.request(
            endpoint: "/api/users/\(id.uuidString)",
            method: .put,
            body: request
        )
        return apiUser.toUser()
    }
    
    /// 删除用户
    func deleteUser(id: UUID) async throws {
        try await APIService.shared.deleteUser(id: id)
    }
    
    // MARK: - 头像
    
    /// 上传头像
    func uploadAvatar(userId: UUID, imageData: Data) async throws -> String {
        return try await APIService.shared.uploadAvatar(
            userId: userId.uuidString,
            imageData: imageData
        )
    }
    
    // MARK: - 人员状态
    
    /// 隐藏用户（离职）
    func hideUser(id: UUID) async throws -> User {
        struct HideResponse: Decodable {
            let message: String
            let user: APIUser
        }
        
        let response: HideResponse = try await APIService.shared.request(
            endpoint: "/api/users/\(id.uuidString)/hide",
            method: .post
        )
        return response.user.toUser()
    }
    
    /// 取消隐藏用户
    func unhideUser(id: UUID) async throws -> User {
        struct UnhideResponse: Decodable {
            let message: String
            let user: APIUser
        }
        
        let response: UnhideResponse = try await APIService.shared.request(
            endpoint: "/api/users/\(id.uuidString)/unhide",
            method: .post
        )
        return response.user.toUser()
    }
}
