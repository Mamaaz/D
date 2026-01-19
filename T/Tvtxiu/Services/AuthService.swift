import Foundation

// MARK: - 认证服务

/// 处理登录、登出、用户认证相关的 API 调用
@MainActor
class AuthService {
    static let shared = AuthService()
    
    private init() {}
    
    /// 登录
    func login(username: String, password: String) async throws -> LoginResponse {
        return try await APIService.shared.request(
            endpoint: "/api/auth/login",
            method: .post,
            body: LoginRequest(username: username, password: password),
            requiresAuth: false
        )
    }
    
    /// 获取当前用户信息
    func getCurrentUser() async throws -> User {
        let apiUser: APIUser = try await APIService.shared.request(
            endpoint: "/api/auth/me"
        )
        return apiUser.toUser()
    }
    
    /// 测试连接
    func testConnection() async -> Bool {
        return await APIService.shared.testConnection()
    }
}
