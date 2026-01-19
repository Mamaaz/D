import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var orderManager: OrderManager
    
    @State private var selectedTab: Tab = .dashboard
    
    enum Tab: String, CaseIterable {
        case dashboard = "工作台"
        case orders = "订单"
        case calendar = "日历"
        case team = "团队"
        case stats = "统计"
        case archive = "归档"
        case settlement = "结算"
        case settings = "设置"
        
        /// 系统图标（备用）
        var systemIcon: String {
            switch self {
            case .dashboard: return "square.grid.2x2.fill"
            case .orders: return "list.clipboard.fill"
            case .calendar: return "calendar"
            case .team: return "person.2.fill"
            case .stats: return "chart.bar.fill"
            case .archive: return "archivebox.fill"
            case .settlement: return "banknote.fill"
            case .settings: return "gearshape.fill"
            }
        }
        
        /// 自定义图标名称（Assets 中）
        var customIcon: String? {
            switch self {
            case .dashboard: return "icon_工作台"
            case .orders: return "icon_订单"
            case .calendar: return "icon_日历"
            case .team: return "icon_团队"
            case .stats: return "icon_统计"
            case .archive: return "icon_归档"
            case .settlement: return "icon_结算"
            case .settings: return "icon_设置"
            }
        }
    }
    
    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            // 侧边栏
            VStack(spacing: 0) {
                List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                    HStack(spacing: 12) {
                        // 优先使用自定义图标，否则使用系统图标
                        if let customIcon = tab.customIcon {
                            Image(customIcon)
                                .resizable()
                                .renderingMode(.original)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: tab.systemIcon)
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 20, height: 20)
                        }
                        
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.vertical, 8)
                    .tag(tab)
                }
                .listStyle(.sidebar)
                
                // 底部用户信息
                userInfoView
                    .padding()
            }
            .frame(minWidth: 200)
        } detail: {
            // 主内容区
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView()
                case .orders:
                    OrderListView()
                case .calendar:
                    CalendarView()
                case .team:
                    StaffView()
                case .stats:
                    StatsView()
                case .archive:
                    ArchiveView()
                case .settlement:
                    SettlementView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        #else
        TabView(selection: $selectedTab) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Group {
                    switch tab {
                    case .dashboard:
                        DashboardView()
                    case .orders:
                        OrderListView()
                    case .calendar:
                        CalendarView()
                    case .team:
                        StaffView()
                    case .stats:
                        StatsView()
                    case .archive:
                        ArchiveView()
                    case .settlement:
                        SettlementView()
                    case .settings:
                        SettingsView()
                    }
                }
                .tabItem {
                    Label(tab.rawValue, systemImage: tab.systemIcon)
                }
                .tag(tab)
            }
        }
        #endif
    }
    
    private var userInfoView: some View {
        HStack {
            // 头像
            Group {
                if let avatarUrl = authManager.currentUser?.avatarUrl, !avatarUrl.isEmpty {
                    AsyncImage(url: URL(string: "\(APIService.shared.baseURL)\(avatarUrl)")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                        case .failure(_), .empty:
                            userAvatarFallback
                        @unknown default:
                            userAvatarFallback
                        }
                    }
                } else {
                    userAvatarFallback
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(authManager.currentUser?.displayName ?? "用户")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(authManager.currentUser?.role.displayName ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                authManager.logout()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("退出登录")
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var userAvatarFallback: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 36, height: 36)
            .overlay(
                Text(String(authManager.currentUser?.displayName.prefix(1) ?? "U"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            )
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthManager())
        .environmentObject(OrderManager())
        .environmentObject(SettingsManager())
}
