import SwiftUI

@main
struct TvtxiuApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var orderManager = OrderManager()
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var performanceManager = PerformanceManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(orderManager)
                .environmentObject(settingsManager)
                .environmentObject(performanceManager)
                .onAppear {
                    // 应用服务器地址配置
                    APIService.shared.configure(baseURL: settingsManager.serverAddress)
                    
                    // 建立 AuthManager 和 OrderManager 的引用
                    authManager.orderManager = orderManager
                    // 确保权限信息在启动时就初始化
                    if authManager.isAuthenticated {
                        orderManager.currentUserId = authManager.currentUser?.id
                        orderManager.currentUserIsAdmin = authManager.hasAdminPrivilege
                    }
                }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        #endif
        
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(authManager)
                .environmentObject(settingsManager)
                .environmentObject(orderManager)
                .environmentObject(performanceManager)
        }
        #endif
    }
}

