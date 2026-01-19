import SwiftUI

struct MonthlyPerformanceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var performanceManager: PerformanceManager
    @EnvironmentObject var orderManager: OrderManager
    
    @State private var selectedMonth: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }()
    
    @State private var editingUserId: UUID?
    @State private var editValue: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 月份选择器
                monthSelector
                
                // 统计概览
                overviewSection
                
                // 人员列表
                staffList
            }
            .navigationTitle("月度工资社保")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 500)
        #endif
    }
    
    // MARK: - 月份选择器
    
    private var monthSelector: some View {
        HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            
            Text(formatMonth(selectedMonth))
                .font(.title2)
                .fontWeight(.semibold)
                .frame(minWidth: 120)
            
            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(isCurrentMonth)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
    }
    
    private func moveMonth(by offset: Int) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: selectedMonth),
              let newDate = Calendar.current.date(byAdding: .month, value: offset, to: date) else {
            return
        }
        selectedMonth = formatter.string(from: newDate)
    }
    
    private var isCurrentMonth: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return selectedMonth == formatter.string(from: Date())
    }
    
    private func formatMonth(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2 else { return month }
        return "\(parts[0])年\(parts[1])月"
    }
    
    // MARK: - 统计概览
    
    private var overviewSection: some View {
        HStack(spacing: 16) {
            overviewCard(
                title: "总完成张数",
                value: "\(totalCompletedPhotos)",
                icon: "photo.stack.fill",
                color: .purple
            )
            
            overviewCard(
                title: "总修图绩效",
                value: String(format: "¥%.0f", totalPerformance),
                icon: "dollarsign.circle.fill",
                color: .green
            )
            
            overviewCard(
                title: "已配置人数",
                value: "\(configuredCount)/\(orderManager.staffList.count)",
                icon: "person.fill.checkmark",
                color: .blue
            )
        }
        .padding()
    }
    
    private func overviewCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var totalCompletedPhotos: Int {
        orderManager.staffList.reduce(0) { sum, staff in
            sum + performanceManager.completedPhotos(for: staff, month: selectedMonth, orders: orderManager.orders)
        }
    }
    
    private var totalPerformance: Double {
        orderManager.staffList.reduce(0) { sum, staff in
            sum + performanceManager.calculateMonthlyPerformance(for: staff, month: selectedMonth, orders: orderManager.orders)
        }
    }
    
    private var configuredCount: Int {
        orderManager.staffList.filter { staff in
            let config = performanceManager.monthlyConfig(for: staff.id, month: selectedMonth)
            return config.salarySocialTotal > 0
        }.count
    }
    
    // MARK: - 人员列表
    
    private var staffList: some View {
        VStack(spacing: 0) {
            // 表头
            HStack {
                Text("人员")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("角色")
                    .frame(width: 60)
                Text("工资社保")
                    .frame(width: 120)
                Text("完成张数")
                    .frame(width: 80)
                Text("修图绩效")
                    .frame(width: 100)
                Text("单张成本")
                    .frame(width: 100)
            }
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .padding()
            .background(Color.gray.opacity(0.1))
            
            // 数据行
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(orderManager.staffList) { staff in
                        staffRow(staff)
                        Divider()
                    }
                }
            }
        }
    }
    
    private func staffRow(_ staff: User) -> some View {
        let config = performanceManager.monthlyConfig(for: staff.id, month: selectedMonth)
        let completedPhotos = performanceManager.completedPhotos(for: staff, month: selectedMonth, orders: orderManager.orders)
        let performance = performanceManager.calculateMonthlyPerformance(for: staff, month: selectedMonth, orders: orderManager.orders)
        let costPerPhoto = performanceManager.calculateCostPerPhoto(for: staff, month: selectedMonth, orders: orderManager.orders)
        
        return HStack {
            // 人员信息
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
                
                Text(staff.displayName)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 角色
            Text(staff.role.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60)
            
            // 工资社保（可编辑）
            if editingUserId == staff.id {
                HStack(spacing: 4) {
                    TextField("", text: $editValue)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    
                    Button {
                        saveSalarySocial(for: staff)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        editingUserId = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 120)
            } else {
                HStack(spacing: 4) {
                    if config.salarySocialTotal > 0 {
                        Text(String(format: "¥%.0f", config.salarySocialTotal))
                            .font(.subheadline)
                    } else {
                        Text("未填写")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        editValue = config.salarySocialTotal > 0 ? String(format: "%.0f", config.salarySocialTotal) : ""
                        editingUserId = staff.id
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
                .frame(width: 120)
            }
            
            // 完成张数
            Text("\(completedPhotos)")
                .font(.subheadline)
                .foregroundColor(completedPhotos > 0 ? .primary : .secondary)
                .frame(width: 80)
            
            // 修图绩效
            Text(String(format: "¥%.0f", performance))
                .font(.subheadline)
                .foregroundColor(.green)
                .frame(width: 100)
            
            // 单张成本
            if let cost = costPerPhoto {
                Text(String(format: "¥%.2f", cost))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    .frame(width: 100)
            } else {
                Text("-")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(width: 100)
            }
        }
        .padding()
    }
    
    private func roleColor(for role: UserRole) -> Color {
        switch role {
        case .admin: return .purple
        case .subAdmin: return .blue
        case .staff: return .green
        case .outsource: return .orange
        }
    }
    
    private func saveSalarySocial(for staff: User) {
        if let value = Double(editValue), value >= 0 {
            performanceManager.setSalarySocial(for: staff.id, month: selectedMonth, amount: value)
        }
        editingUserId = nil
    }
}

#Preview {
    MonthlyPerformanceView()
        .environmentObject(PerformanceManager())
        .environmentObject(OrderManager())
}
