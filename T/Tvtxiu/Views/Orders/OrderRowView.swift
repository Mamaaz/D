import SwiftUI

struct OrderRowView: View {
    let order: Order
    @EnvironmentObject var orderManager: OrderManager
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        HStack(spacing: 16) {
            // 归档勾选框（仅已完成且未归档时显示）
            if order.isCompleted && !order.isArchived && canArchive {
                Button {
                    Task { await orderManager.archiveOrder(order) }
                } label: {
                    Image(systemName: "square")
                        .font(.title3)
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                .help("点击归档")
            } else if order.isArchived {
                Image(systemName: "checkmark.square.fill")
                    .font(.title3)
                    .foregroundColor(.green)
                    .help("已归档")
            }
            
            // 完成状态指示
            statusIndicator
            
            // 主要信息
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // 订单编号 · 地点 · 拍摄时间
                    Text(orderTitleText)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    // 标签区域
                    tagArea
                    
                    Spacer()
                    
                    // 交付日期 (中文格式)
                    if let deadline = order.finalDeadline {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                            Text(formatChineseDate(deadline))
                        }
                        .font(.caption)
                        .foregroundColor(order.isOverdue ? .red : .secondary)
                    }
                }
                
                HStack(spacing: 16) {
                    // 拍摄类型
                    Text(order.shootType.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(order.shootType == .wedding ? Color.pink.opacity(0.2) : Color.purple.opacity(0.2))
                        .foregroundColor(order.shootType == .wedding ? .pink : .purple)
                        .cornerRadius(4)
                    
                    // 张数
                    Label("\(order.totalCount) 张", systemImage: "photo.stack.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // 客服和后期人员
                    HStack(spacing: 8) {
                        // 客服
                        if !order.consultant.isEmpty {
                            HStack(spacing: 4) {
                                Text("客服:")
                                    .foregroundColor(.secondary)
                                Text(order.consultant)
                            }
                            .font(.subheadline)
                        }
                        
                        // 分隔符
                        if !order.consultant.isEmpty && order.assignedTo != nil {
                            Text("|")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                        
                        // 后期人员
                        if let assignedTo = order.assignedTo {
                            // 优先使用 API 返回的人员名称
                            if let userName = order.assignedUserName, !userName.isEmpty {
                                HStack(spacing: 4) {
                                    Text("后期:")
                                        .foregroundColor(.secondary)
                                    Text(userName)
                                        .foregroundColor(.blue)
                                }
                                .font(.subheadline)
                            } else if let staff = orderManager.staffList.first(where: { $0.id == assignedTo }) {
                                // 回退到从 staffList 查找
                                HStack(spacing: 4) {
                                    Text("后期:")
                                        .foregroundColor(.secondary)
                                    Circle()
                                        .fill(Color(red: staff.calendarColorRed, green: staff.calendarColorGreen, blue: staff.calendarColorBlue))
                                        .frame(width: 8, height: 8)
                                    Text(staff.displayName)
                                        .foregroundColor(.blue)
                                }
                                .font(.subheadline)
                            } else if assignedTo == authManager.currentUser?.id {
                                // 分配给自己，显示当前用户名称
                                HStack(spacing: 4) {
                                    Text("后期:")
                                        .foregroundColor(.secondary)
                                    Text(authManager.currentUser?.nickname ?? authManager.currentUser?.username ?? "我")
                                        .foregroundColor(.blue)
                                }
                                .font(.subheadline)
                            } else {
                                // 有分配但找不到名称
                                HStack(spacing: 4) {
                                    Text("后期:")
                                        .foregroundColor(.secondary)
                                    Text("已分配")
                                        .foregroundColor(.blue)
                                }
                                .font(.subheadline)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Text("后期:")
                                    .foregroundColor(.secondary)
                                Text("未分配")
                                    .foregroundColor(.orange)
                            }
                            .font(.subheadline)
                        }
                    }
                    
                    // 备注预览（前20字符）
                    if !order.remarks.isEmpty {
                        Text("💬 \(String(order.remarks.prefix(20)))\(order.remarks.count > 20 ? "..." : "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            // 操作按钮
            if canToggleComplete {
                Button {
                    toggleComplete()
                } label: {
                    Image(systemName: order.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(order.isCompleted ? .green : .gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 2)
        )
    }
    
    // MARK: - 标签区域
    
    @ViewBuilder
    private var tagArea: some View {
        HStack(spacing: 4) {
            // 加急标签 (橙色)
            if order.isUrgent {
                Label("加急", systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .cornerRadius(4)
            }
            
            // 投诉标签 (深红色)
            if order.isComplaint {
                Label("投诉单", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.6, green: 0.1, blue: 0.1))
                    .cornerRadius(4)
            }
            
            // 逾期标签
            if order.isOverdue {
                Label("逾期", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .cornerRadius(4)
            }
        }
    }
    
    // MARK: - 背景色
    
    private var backgroundColor: Color {
        if order.isComplaint {
            return Color(red: 0.3, green: 0.1, blue: 0.1).opacity(0.3)
        } else if order.isUrgent {
            return Color.orange.opacity(0.1)
        } else {
            return Color.gray.opacity(0.05)
        }
    }
    
    private var borderColor: Color {
        if order.isComplaint {
            return Color(red: 0.6, green: 0.1, blue: 0.1).opacity(0.5)
        } else if order.isUrgent {
            return Color.orange.opacity(0.3)
        } else if order.isOverdue {
            return Color.red.opacity(0.3)
        } else {
            return Color.clear
        }
    }
    
    // MARK: - 状态指示器
    
    private var statusIndicator: some View {
        Rectangle()
            .fill(statusColor)
            .frame(width: 4)
            .cornerRadius(2)
    }
    
    private var statusColor: Color {
        if order.isComplaint {
            return Color(red: 0.6, green: 0.1, blue: 0.1)
        } else if order.isUrgent {
            return .orange
        } else if order.isCompleted {
            return .green
        } else if order.isOverdue {
            return .red
        } else if let days = order.daysUntilDeadline, days <= 3 {
            return .orange
        } else {
            return .blue
        }
    }
    
    // MARK: - 权限判断
    
    private var canToggleComplete: Bool {
        if authManager.hasAdminPrivilege {
            return true
        }
        return order.assignedTo == authManager.currentUser?.id
    }
    
    private func toggleComplete() {
        Task {
            if order.isCompleted {
                await orderManager.markAsIncomplete(order)
            } else {
                await orderManager.markAsCompleted(order)
            }
        }
    }
    
    // MARK: - 格式化
    
    /// 订单标题：编号 · 地点 · 拍摄时间
    private var orderTitleText: String {
        var parts = [order.orderNumber]
        
        if !order.shootLocation.isEmpty {
            parts.append(order.shootLocation)
        }
        
        if !order.shootDate.isEmpty {
            let formattedShootDate = formatShootDateToChinese(order.shootDate)
            parts.append(formattedShootDate)
        }
        
        return parts.joined(separator: " · ")
    }
    
    /// 将拍摄时间转换为中文格式，支持多种格式
    private func formatShootDateToChinese(_ dateString: String) -> String {
        // 移除所有空格
        let cleaned = dateString.trimmingCharacters(in: .whitespaces)
        
        // 尝试解析 "25/9/6-7" 或 "25/9/6" 格式
        if cleaned.contains("/") {
            let parts = cleaned.split(separator: "/")
            if parts.count >= 3 {
                if let year = Int(parts[0]), let month = Int(parts[1]) {
                    let fullYear = year < 50 ? 2000 + year : (year < 100 ? 1900 + year : year)
                    
                    // 检查日期部分是否包含范围 (如 "6-7")
                    let dayPart = String(parts[2])
                    if dayPart.contains("-") {
                        let dayRange = dayPart.split(separator: "-")
                        if dayRange.count == 2 {
                            return "\(fullYear)年\(month)月\(dayRange[0])-\(dayRange[1])日"
                        }
                    } else if let day = Int(dayPart) {
                        return "\(fullYear)年\(month)月\(day)日"
                    }
                }
            }
        }
        
        // 尝试解析 "250906-07" 或 "250906" 格式
        let digits = cleaned.filter { $0.isNumber || $0 == "-" }
        if digits.count >= 6 {
            let prefix = String(digits.prefix(6))
            if let year = Int(prefix.prefix(2)),
               let month = Int(prefix.dropFirst(2).prefix(2)),
               let day = Int(prefix.dropFirst(4).prefix(2)) {
                let fullYear = year < 50 ? 2000 + year : 1900 + year
                
                // 检查是否有范围 (如 "-07")
                if digits.count > 6 && digits.contains("-") {
                    let rangePart = digits.dropFirst(6)
                    if rangePart.hasPrefix("-"), let endDay = Int(rangePart.dropFirst().prefix(2)) {
                        return "\(fullYear)年\(month)月\(day)-\(endDay)日"
                    }
                }
                
                return "\(fullYear)年\(month)月\(day)日"
            }
        }
        
        // 如果无法解析，返回原始字符串
        return dateString
    }
    
    /// 将 Date 转换为中文格式
    private func formatChineseDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
    
    /// 是否可以归档（管理员或订单负责人）
    private var canArchive: Bool {
        if authManager.hasAdminPrivilege {
            return true
        }
        return order.assignedTo == authManager.currentUser?.id
    }
}

#Preview {
    VStack {
        OrderRowView(order: .preview)
        OrderRowView(order: Order.previewList[1])
        OrderRowView(order: Order.previewList[2])
    }
    .padding()
    .environmentObject(OrderManager())
    .environmentObject(AuthManager())
}
