import SwiftUI

struct StaffPerformanceConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var orderManager: OrderManager
    
    var body: some View {
        NavigationStack {
            Form {
                // 绩效规则说明
                rulesSection
                
                // 人员列表（显示配置）
                staffListSection
            }
            .formStyle(.grouped)
            .navigationTitle("绩效配置说明")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }
    
    // MARK: - 规则说明
    
    private var rulesSection: some View {
        Section("绩效计算规则") {
            VStack(alignment: .leading, spacing: 12) {
                Text("每个用户有独立的绩效配置")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ruleRow(icon: "person.fill", title: "基础单价", desc: "用户个人设置 元/张")
                
                Divider()
                
                Text("加项规则（互斥优先级：投诉 > 加急 > 进群）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ruleRow(icon: "person.2.fill", title: "进群加项", desc: "用户个人设置 元/张", color: .blue)
                ruleRow(icon: "bolt.fill", title: "加急加项", desc: "用户个人设置 元/张（进群失效）", color: .orange)
                ruleRow(icon: "exclamationmark.triangle.fill", title: "投诉加项", desc: "用户个人设置 元/张（进群失效）", color: Color(red: 0.6, green: 0.1, blue: 0.1))
                
                Divider()
                
                Text("类型系数")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ruleRow(icon: "camera.fill", title: "婚纱", desc: "×1.0")
                ruleRow(icon: "video.fill", title: "婚礼", desc: "用户个人设置 ×婚礼系数")
            }
            .padding(.vertical, 8)
        }
    }
    
    private func ruleRow(icon: String, title: String, desc: String, color: Color = .primary) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .foregroundColor(color)
            
            Spacer()
            
            Text(desc)
                .foregroundColor(.secondary)
                .font(.subheadline)
        }
    }
    
    // MARK: - 人员列表
    
    private var staffListSection: some View {
        Section {
            ForEach(orderManager.staffList) { staff in
                HStack {
                    Circle()
                        .fill(roleColor(for: staff.role))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String(staff.displayName.prefix(1)))
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(staff.displayName)
                                .font(.subheadline)
                            
                            if staff.role == .outsource {
                                Image(systemName: "person.badge.shield.checkmark.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Text(staff.role.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // 显示当前配置（只读）
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("¥\(String(format: "%.1f", staff.basePrice))/张")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        
                        HStack(spacing: 4) {
                            Text("进群+\(String(format: "%.0f", staff.groupBonus))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("加急+\(String(format: "%.0f", staff.urgentBonus))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("人员绩效配置")
        } footer: {
            Text("点击人员详情可修改个人绩效配置")
        }
    }
    
    private func roleColor(for role: UserRole) -> Color {
        switch role {
        case .admin: return .purple
        case .subAdmin: return .blue
        case .staff: return .green
        case .outsource: return .orange
        }
    }
}

#Preview {
    StaffPerformanceConfigView()
        .environmentObject(OrderManager())
}
