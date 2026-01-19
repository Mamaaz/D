import SwiftUI

// MARK: - 数据管理区域

/// 数据管理设置（从 SettingsView 提取）
struct DataManagementSection: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var orderManager: OrderManager
    
    @State private var showImportSheet: Bool = false
    @State private var showPerformanceConfig: Bool = false
    @State private var showMonthlyPerformance: Bool = false
    @State private var showExportFormatDialog: Bool = false
    @State private var showDeleteConfirmSheet: Bool = false
    @State private var deleteConfirmText: String = ""
    @State private var isExporting: Bool = false
    
    var body: some View {
        Group {
            if authManager.hasAdminPrivilege {
                deliveryRulesSection
                performanceSection
                dataManagementSection
                dangerZoneSection
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ImportDataView()
        }
        .sheet(isPresented: $showPerformanceConfig) {
            StaffPerformanceConfigView()
        }
        .sheet(isPresented: $showMonthlyPerformance) {
            MonthlyPerformanceView()
        }
        .confirmationDialog("选择导出格式", isPresented: $showExportFormatDialog) {
            Button("导出 CSV") { selectCSVExportType() }
            Button("导出 JSON") { performJSONExport() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前订单数: \(orderManager.orders.count)，人员数: \(orderManager.staffList.count)")
        }
        .sheet(isPresented: $showDeleteConfirmSheet) {
            DeleteConfirmationSheet(
                isPresented: $showDeleteConfirmSheet,
                confirmText: $deleteConfirmText,
                onConfirm: { Task { await deleteAllData() } }
            )
        }
    }
    
    // MARK: - 交付规则
    
    private var deliveryRulesSection: some View {
        Section("交付规则") {
            Stepper(
                "提前 \(settingsManager.advanceDays) 天",
                value: $settingsManager.advanceDays,
                in: 0...30
            )
            
            Text("设置后，解析订单时会自动将交付日期提前相应天数")
                .font(TvtDesign.Typography.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - 绩效管理
    
    private var performanceSection: some View {
        Section("绩效管理") {
            Button {
                showPerformanceConfig = true
            } label: {
                SettingsNavigationRow(
                    title: "绩效配置",
                    icon: "chart.bar.fill"
                )
            }
            .buttonStyle(.plain)
            
            Button {
                showMonthlyPerformance = true
            } label: {
                SettingsNavigationRow(
                    title: "月度工资社保",
                    icon: "dollarsign.circle.fill"
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - 数据管理
    
    private var dataManagementSection: some View {
        Section("数据管理") {
            Button {
                showImportSheet = true
            } label: {
                Label("导入 Excel 数据", systemImage: "square.and.arrow.down.fill")
            }
            
            Button {
                showExportFormatDialog = true
            } label: {
                if isExporting {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Label("导出所有数据", systemImage: "square.and.arrow.up.fill")
                }
            }
            .disabled(isExporting)
            
            Button { exportFullBackup() } label: {
                Label("完整备份（含头像）", systemImage: "arrow.down.doc.fill")
            }
            
            Button { importFullBackup() } label: {
                Label("恢复完整备份", systemImage: "arrow.up.doc.fill")
            }
            
            Text("完整备份包含 JSON 数据和头像文件（ZIP 格式）")
                .font(TvtDesign.Typography.caption)
                .foregroundColor(.secondary)
            
            Button { importMigrationData() } label: {
                Label("导入旧版迁移数据", systemImage: "clock.arrow.circlepath")
            }
            
            Text("从旧版 JSON 备份文件恢复数据")
                .font(TvtDesign.Typography.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - 危险操作
    
    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmSheet = true
            } label: {
                Label("删除所有数据", systemImage: "trash.fill")
            }
        }
    }
    
    // MARK: - 方法 (这些函数需要从原 SettingsView 中保留)
    
    private func selectCSVExportType() {
        // TODO: 调用原有逻辑
    }
    
    private func performJSONExport() {
        // TODO: 调用原有逻辑
    }
    
    private func exportFullBackup() {
        // TODO: 调用原有逻辑
    }
    
    private func importFullBackup() {
        // TODO: 调用原有逻辑
    }
    
    private func importMigrationData() {
        // TODO: 调用原有逻辑
    }
    
    private func deleteAllData() async {
        // TODO: 调用原有逻辑
    }
}

// MARK: - 辅助视图

/// 设置导航行
struct SettingsNavigationRow: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 预览

#Preview {
    Form {
        DataManagementSection()
    }
    .environmentObject(AuthManager())
    .environmentObject(SettingsManager())
    .environmentObject(OrderManager())
    .frame(width: 500)
}
