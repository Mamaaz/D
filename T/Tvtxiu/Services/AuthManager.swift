import Foundation
import SwiftUI

// MARK: - 认证管理器

@MainActor
class AuthManager: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // JWT Token
    private var authToken: String?
    
    // 引用 OrderManager 用于查找用户
    weak var orderManager: OrderManager?
    
    // MARK: - API 登录
    
    /// 使用 API 登录
    func login(username: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response: LoginResponse = try await APIService.shared.request(
                endpoint: "/api/auth/login",
                method: .post,
                body: LoginRequest(username: username, password: password),
                requiresAuth: false
            )
            
            // 保存 Token
            authToken = response.token
            APIService.shared.setAuthToken(response.token)
            
            // 转换 API 用户为本地用户模型
            currentUser = response.user.toUser()
            isAuthenticated = true
            
            // 登录成功后立即同步权限到 OrderManager
            if let orderManager = orderManager {
                orderManager.currentUserId = currentUser?.id
                orderManager.currentUserIsAdmin = currentUser?.role.hasAdminPrivilege ?? false
                
                // 加载订单和用户列表
                await orderManager.loadFromAPI()
            }
            
        } catch let error as APIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "网络错误: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// 登出
    func logout() {
        currentUser = nil
        isAuthenticated = false
        authToken = nil
        APIService.shared.setAuthToken(nil)
    }
    
    /// 当前用户是否有管理权限
    var hasAdminPrivilege: Bool {
        currentUser?.role.hasAdminPrivilege ?? false
    }
}

