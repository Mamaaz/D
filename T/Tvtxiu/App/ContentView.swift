import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var orderManager: OrderManager
    @StateObject private var toastManager = ToastManager.shared
    
    var body: some View {
        ZStack {
            Group {
                if authManager.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .animation(.easeInOut, value: authManager.isAuthenticated)
            
            // Toast 显示层
            VStack {
                if let toast = toastManager.currentToast {
                    ToastView(toast: toast) {
                        toastManager.dismiss()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toastManager.currentToast)
        }
        .onChange(of: authManager.isAuthenticated) { isAuthenticated in
            // 登录状态变化时更新 OrderManager 的权限信息
            if isAuthenticated {
                orderManager.currentUserId = authManager.currentUser?.id
                orderManager.currentUserIsAdmin = authManager.hasAdminPrivilege
            } else {
                orderManager.currentUserId = nil
                orderManager.currentUserIsAdmin = false
            }
        }
        .onChange(of: authManager.currentUser) { user in
            // 用户变化时也更新权限
            orderManager.currentUserId = user?.id
            orderManager.currentUserIsAdmin = user?.role.hasAdminPrivilege ?? false
        }
        .onAppear {
            // 初始化时如果已登录，同步权限信息
            if authManager.isAuthenticated {
                orderManager.currentUserId = authManager.currentUser?.id
                orderManager.currentUserIsAdmin = authManager.hasAdminPrivilege
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
        .environmentObject(OrderManager())
        .environmentObject(SettingsManager())
}
