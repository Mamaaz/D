import SwiftUI

struct OrderDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var orderManager: OrderManager
    @EnvironmentObject var authManager: AuthManager
    
    let order: Order
    @State private var editedOrder: Order
    @State private var isEditing: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    
    // 编辑用的临时变量（用于数字输入）
    @State private var totalCountText: String = ""
    @State private var extraCountText: String = ""
    
    // 备注编辑状态
    @State private var isEditingRemarks: Bool = false
    @State private var originalRemarks: String = ""
    
    init(order: Order) {
        self.order = order
        self._editedOrder = State(initialValue: order)
        self._totalCountText = State(initialValue: "\(order.totalCount)")
        self._extraCountText = State(initialValue: "\(order.extraCount)")
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 状态卡片
                    statusCard
                    
                    // 基本信息
                    if isEditing && authManager.hasAdminPrivilege {
                        editableBasicInfoSection
                    } else {
                        infoSection(title: "基本信息") {
                            InfoRow(label: "订单编号", value: editedOrder.orderNumber)
                            InfoRow(label: "拍摄时间", value: editedOrder.shootDate)
                            InfoRow(label: "拍摄地点", value: editedOrder.shootLocation)
                            InfoRow(label: "摄影师", value: editedOrder.photographer)
                            InfoRow(label: "顾问", value: editedOrder.consultant)
                        }
                    }
                    
                    // 数量信息
                    if isEditing && authManager.hasAdminPrivilege {
                        editableCountSection
                    } else {
                        infoSection(title: "数量信息") {
                            InfoRow(label: "总张数", value: "\(editedOrder.totalCount) 张")
                            InfoRow(label: "加选数量", value: "\(editedOrder.extraCount) 张")
                            InfoRow(label: "是否有产品", value: editedOrder.hasProduct ? "是" : "否")
                        }
                    }
                    
                    // 时间信息
                    if isEditing && authManager.hasAdminPrivilege {
                        editableTimeSection
                    } else {
                        infoSection(title: "时间信息") {
                            InfoRow(
                                label: "分配时间",
                                value: formatChineseDate(editedOrder.assignedAt)
                            )
                            InfoRow(
                                label: "试修交付",
                                value: formatChineseDate(editedOrder.trialDeadline)
                            )
                            InfoRow(
                                label: "结片时间",
                                value: formatChineseDate(editedOrder.finalDeadline),
                                isHighlighted: editedOrder.isOverdue
                            )
                            InfoRow(
                                label: "客人婚期",
                                value: editedOrder.weddingDate.isEmpty ? "-" : editedOrder.weddingDate
                            )
                            InfoRow(label: "是否复购", value: editedOrder.isRepeatCustomer ? "是" : "否")
                        }
                    }
                    
                    // 客人要求
                    if isEditing && authManager.hasAdminPrivilege {
                        editableRequirementsSection
                    } else {
                        infoSection(title: "客人要求") {
                            Text(editedOrder.requirements.isEmpty ? "无特殊要求" : editedOrder.requirements)
                                .font(.subheadline)
                                .foregroundColor(editedOrder.requirements.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    // 网盘信息
                    if isEditing && authManager.hasAdminPrivilege {
                        editablePanSection
                    } else {
                        infoSection(title: "网盘信息") {
                            HStack {
                                if !editedOrder.panLink.isEmpty {
                                    Link(destination: URL(string: editedOrder.panLink)!) {
                                        Label("打开网盘", systemImage: "link")
                                    }
                                    .buttonStyle(.bordered)
                                }
                                
                                if !editedOrder.panCode.isEmpty {
                                    HStack {
                                        Text("提取码：")
                                            .foregroundColor(.secondary)
                                        Text(editedOrder.panCode)
                                            .font(.system(.body, design: .monospaced))
                                            .fontWeight(.bold)
                                        
                                        Button {
                                            #if os(macOS)
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(editedOrder.panCode, forType: .string)
                                            #else
                                            UIPasteboard.general.string = editedOrder.panCode
                                            #endif
                                        } label: {
                                            Image(systemName: "doc.on.clipboard")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(.blue)
                                    }
                                }
                                
                                if editedOrder.panLink.isEmpty && editedOrder.panCode.isEmpty {
                                    Text("暂无网盘信息")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    
                    // 备注（所有人可编辑）
                    remarksSection
                    
                    // 管理员删除按钮
                    if authManager.hasAdminPrivilege && !isEditing {
                        deleteSection
                    }
                }
                .padding()
            }
            .navigationTitle("订单详情")
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 600)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEditing ? "取消" : "关闭") {
                        if isEditing {
                            // 取消编辑，恢复原始数据
                            editedOrder = order
                            totalCountText = "\(order.totalCount)"
                            extraCountText = "\(order.extraCount)"
                            isEditing = false
                        } else {
                            dismiss()
                        }
                    }
                }
                
                if authManager.hasAdminPrivilege || (!editedOrder.isArchived && !editedOrder.isCompleted) {
                    ToolbarItem(placement: .primaryAction) {
                        if isEditing {
                            Button("保存") {
                                saveChanges()
                            }
                        } else {
                            // 归档订单只有管理员能编辑
                            if !editedOrder.isArchived || authManager.hasAdminPrivilege {
                                Button("编辑") {
                                    isEditing = true
                                }
                            }
                        }
                    }
                }
            }
            .alert("确认删除", isPresented: $showDeleteConfirmation) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    deleteOrder()
                }
            } message: {
                Text("确定要删除订单「\(editedOrder.orderNumber)」吗？此操作不可恢复。")
            }
        }
    }
    
    // MARK: - 可编辑的基本信息
    
    private var editableBasicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基本信息")
                .font(.headline)
            
            VStack(spacing: 12) {
                EditableRow(label: "订单编号", text: $editedOrder.orderNumber)
                EditableRow(label: "拍摄时间", text: $editedOrder.shootDate)
                EditableRow(label: "拍摄地点", text: $editedOrder.shootLocation)
                EditableRow(label: "摄影师", text: $editedOrder.photographer)
                EditableRow(label: "顾问", text: $editedOrder.consultant)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    // MARK: - 可编辑的数量信息
    
    private var editableCountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("数量信息")
                .font(.headline)
            
            VStack(spacing: 12) {
                HStack {
                    Text("总张数")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    TextField("总张数", text: $totalCountText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .onChange(of: totalCountText) { newValue in
                            if let count = Int(newValue) {
                                editedOrder.totalCount = count
                            }
                        }
                }
                
                HStack {
                    Text("加选数量")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    TextField("加选数量", text: $extraCountText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .onChange(of: extraCountText) { newValue in
                            if let count = Int(newValue) {
                                editedOrder.extraCount = count
                            }
                        }
                }
                
                Toggle("是否有产品", isOn: $editedOrder.hasProduct)
                    .font(.subheadline)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    // MARK: - 可编辑的时间信息
    
    private var editableTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("时间信息")
                .font(.headline)
            
            VStack(spacing: 12) {
                // 分配时间
                HStack {
                    Text("分配时间")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    OptionalDatePicker(date: $editedOrder.assignedAt, label: "分配时间")
                }
                
                // 试修交付
                HStack {
                    Text("试修交付")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    OptionalDatePicker(date: $editedOrder.trialDeadline, label: "试修交付")
                }
                
                // 结片时间
                HStack {
                    Text("结片时间")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    OptionalDatePicker(date: $editedOrder.finalDeadline, label: "结片时间")
                }
                
                // 婚期
                EditableRow(label: "客人婚期", text: $editedOrder.weddingDate)
                
                Toggle("是否复购", isOn: $editedOrder.isRepeatCustomer)
                    .font(.subheadline)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    // MARK: - 可编辑的客人要求
    
    private var editableRequirementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("客人要求")
                .font(.headline)
            
            TextEditor(text: $editedOrder.requirements)
                .frame(minHeight: 80)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
        }
    }
    
    // MARK: - 可编辑的网盘信息
    
    private var editablePanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("网盘信息")
                .font(.headline)
            
            VStack(spacing: 12) {
                EditableRow(label: "网盘链接", text: $editedOrder.panLink)
                EditableRow(label: "提取码", text: $editedOrder.panCode)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    // MARK: - 备注区域（所有人可编辑）
    
    private var remarksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("备注")
                    .font(.headline)
                
                Spacer()
                
                // 编辑按钮
                if !isEditingRemarks {
                    Button {
                        isEditingRemarks = true
                        originalRemarks = editedOrder.remarks
                    } label: {
                        Text("编辑")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if isEditingRemarks {
                    TextEditor(text: $editedOrder.remarks)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    
                    HStack {
                        Button("取消") {
                            editedOrder.remarks = originalRemarks
                            isEditingRemarks = false
                        }
                        .buttonStyle(.bordered)
                        
                        Button("保存备注") {
                            saveRemarks()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Text(editedOrder.remarks.isEmpty ? "无备注" : editedOrder.remarks)
                        .font(.subheadline)
                        .foregroundColor(editedOrder.remarks.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // 修改历史
                if !editedOrder.remarksHistory.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("修改记录")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(editedOrder.remarksHistory.suffix(5), id: \.self) { date in
                            Text("• \(formatHistoryDate(date))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    private func formatHistoryDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
    
    private func saveRemarks() {
        // 只有当备注内容有变化时才添加历史记录
        if editedOrder.remarks != originalRemarks {
            editedOrder.remarksHistory.append(Date())
        }
        orderManager.updateOrder(editedOrder)
        isEditingRemarks = false
    }
    
    // MARK: - 删除区域
    
    private var deleteSection: some View {
        VStack(spacing: 12) {
            Divider()
            
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("删除订单")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - 状态卡片
    
    private var statusCard: some View {
        VStack(spacing: 12) {
            // 顶部状态行
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 12, height: 12)
                        
                        Text(statusText)
                            .font(.headline)
                        
                        // 拍摄类型标签
                        Text(editedOrder.shootType.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(editedOrder.shootType == .wedding ? Color.pink.opacity(0.2) : Color.purple.opacity(0.2))
                            .foregroundColor(editedOrder.shootType == .wedding ? .pink : .purple)
                            .cornerRadius(4)
                        
                        // 加急标签
                        if editedOrder.isUrgent {
                            Label("加急", systemImage: "bolt.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .cornerRadius(4)
                        }
                        
                        // 投诉标签
                        if editedOrder.isComplaint {
                            Label("投诉单", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.6, green: 0.1, blue: 0.1))
                                .cornerRadius(4)
                        }
                    }
                    
                    if let days = editedOrder.daysUntilDeadline {
                        Text(daysText(days))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // 切换完成状态
                if canToggleComplete {
                    Button {
                        toggleComplete()
                    } label: {
                        HStack {
                            Image(systemName: editedOrder.isCompleted ? "checkmark.circle.fill" : "circle")
                            Text(editedOrder.isCompleted ? "已完成" : "标记完成")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(editedOrder.isCompleted ? Color.green : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // 管理员标签操作区
            if authManager.hasAdminPrivilege {
                Divider()
                
                HStack(spacing: 12) {
                    // 拍摄类型切换
                    Picker("拍摄类型", selection: $editedOrder.shootType) {
                        ForEach(ShootType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .onChange(of: editedOrder.shootType) { _ in
                        orderManager.updateOrder(editedOrder)
                    }
                    
                    Divider()
                        .frame(height: 24)
                    
                    // 进群标签
                    Toggle(isOn: $editedOrder.isInGroup) {
                        Label("进群", systemImage: "person.3.fill")
                            .font(.caption)
                    }
                    .toggleStyle(.button)
                    .onChange(of: editedOrder.isInGroup) { _ in
                        orderManager.updateOrder(editedOrder)
                    }
                    
                    // 加急标签
                    Button {
                        editedOrder.isUrgent.toggle()
                        orderManager.updateOrder(editedOrder)
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("加急")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(editedOrder.isUrgent ? Color.orange : Color.gray.opacity(0.2))
                        .foregroundColor(editedOrder.isUrgent ? .white : .primary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    // 投诉标签
                    Button {
                        toggleComplaint()
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("投诉")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(editedOrder.isComplaint ? Color(red: 0.6, green: 0.1, blue: 0.1) : Color.gray.opacity(0.2))
                        .foregroundColor(editedOrder.isComplaint ? .white : .primary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                
                Divider()
                
                // 后期人员分配
                HStack {
                    Text("后期人员:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: Binding(
                        get: { editedOrder.assignedTo },
                        set: { newValue in
                            editedOrder.assignedTo = newValue
                            if newValue != nil {
                                editedOrder.assignedAt = Date()
                            } else {
                                editedOrder.assignedAt = nil
                            }
                            orderManager.updateOrder(editedOrder)
                        }
                    )) {
                        Text("未分配").tag(UUID?.none)
                        ForEach(orderManager.staffList) { staff in
                            HStack {
                                Circle()
                                    .fill(Color(red: staff.calendarColorRed, green: staff.calendarColorGreen, blue: staff.calendarColorBlue))
                                    .frame(width: 10, height: 10)
                                Text(staff.displayName)
                            }
                            .tag(UUID?.some(staff.id))
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Spacer()
                    
                    if let assignedTo = editedOrder.assignedTo,
                       let staff = orderManager.staffList.first(where: { $0.id == assignedTo }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(red: staff.calendarColorRed, green: staff.calendarColorGreen, blue: staff.calendarColorBlue))
                                .frame(width: 12, height: 12)
                            Text(staff.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
        .padding()
        .background(statusColor.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - 信息区块
    
    private func infoSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            VStack(spacing: 0) {
                content()
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    // MARK: - 辅助
    
    private var statusColor: Color {
        if editedOrder.isComplaint {
            return Color(red: 0.6, green: 0.1, blue: 0.1)
        } else if editedOrder.isCompleted {
            return .green
        } else if editedOrder.isOverdue {
            return .red
        } else if let days = editedOrder.daysUntilDeadline, days <= 3 {
            return .orange
        } else {
            return .blue
        }
    }
    
    private var statusText: String {
        if editedOrder.isComplaint {
            return "投诉处理中"
        } else if editedOrder.isCompleted {
            return "已完成"
        } else if editedOrder.isOverdue {
            return "已逾期"
        } else if let days = editedOrder.daysUntilDeadline, days <= 3 {
            return "即将到期"
        } else {
            return "进行中"
        }
    }
    
    private func daysText(_ days: Int) -> String {
        if days < 0 {
            return "已逾期 \(-days) 天"
        } else if days == 0 {
            return "今日交付"
        } else {
            return "距离交付还有 \(days) 天"
        }
    }
    
    private var canToggleComplete: Bool {
        if authManager.hasAdminPrivilege {
            return true
        }
        return editedOrder.assignedTo == authManager.currentUser?.id
    }
    
    private func toggleComplete() {
        if editedOrder.isCompleted {
            editedOrder.isCompleted = false
            editedOrder.completedAt = nil
            Task { await orderManager.markAsIncomplete(order) }
        } else {
            editedOrder.isCompleted = true
            editedOrder.completedAt = Date()
            Task { await orderManager.markAsCompleted(order) }
        }
    }
    
    private func toggleComplaint() {
        editedOrder.isComplaint.toggle()
        orderManager.updateOrder(editedOrder)
    }
    
    private func saveChanges() {
        orderManager.updateOrder(editedOrder)
        isEditing = false
    }
    
    private func deleteOrder() {
        orderManager.deleteOrder(editedOrder)
        dismiss()
    }
}

// MARK: - 可编辑行

struct EditableRow: View {
    let label: String
    @Binding var text: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            TextField(label, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - 可选日期选择器

struct OptionalDatePicker: View {
    @Binding var date: Date?
    let label: String
    
    @State private var hasDate: Bool = false
    @State private var selectedDate: Date = Date()
    
    init(date: Binding<Date?>, label: String) {
        self._date = date
        self.label = label
        self._hasDate = State(initialValue: date.wrappedValue != nil)
        self._selectedDate = State(initialValue: date.wrappedValue ?? Date())
    }
    
    var body: some View {
        HStack {
            Toggle("", isOn: $hasDate)
                .labelsHidden()
                .onChange(of: hasDate) { newValue in
                    if newValue {
                        date = selectedDate
                    } else {
                        date = nil
                    }
                }
            
            if hasDate {
                DatePicker(
                    "",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .labelsHidden()
                .onChange(of: selectedDate) { newValue in
                    date = newValue
                }
            } else {
                Text("未设置")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - 信息行

struct InfoRow: View {
    let label: String
    let value: String
    var isHighlighted: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isHighlighted ? .red : .primary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 辅助函数

private func formatChineseDate(_ date: Date?) -> String {
    guard let date = date else { return "-" }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy年M月d日"
    formatter.locale = Locale(identifier: "zh_CN")
    return formatter.string(from: date)
}

#Preview {
    OrderDetailView(order: .preview)
        .environmentObject(OrderManager())
        .environmentObject(AuthManager())
}
