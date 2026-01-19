import SwiftUI

struct NewOrderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var orderManager: OrderManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var settingsManager: SettingsManager
    
    @State private var inputText: String = ""
    @State private var parsedOrder: Order = Order()
    @State private var selectedStaff: User?
    @State private var showPreview: Bool = false
    @State private var isParsing: Bool = false
    @State private var isAIParsed: Bool = false
    @State private var parseError: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !showPreview {
                    inputView
                } else {
                    previewView
                }
            }
            .navigationTitle("新建订单")
            #if os(macOS)
            .frame(minWidth: 700, minHeight: 600)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    if showPreview {
                        Button("保存") {
                            saveOrder()
                        }
                        .disabled(selectedStaff == nil)
                    } else {
                        Button {
                            parseInput()
                        } label: {
                            if isParsing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("解析")
                            }
                        }
                        .disabled(inputText.isEmpty || isParsing)
                    }
                }
            }
        }
    }
    
    // MARK: - 输入视图
    
    private var inputView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 使用说明
            VStack(alignment: .leading, spacing: 8) {
                Label("粘贴订单信息", systemImage: "doc.on.clipboard")
                    .font(.headline)
                
                Text("从微信群复制订单信息并粘贴到下方，系统将自动解析各字段")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
            
            // 输入区域
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("订单文本")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    // AI 解析开关
                    Button {
                        settingsManager.aiEnabled.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: settingsManager.aiEnabled ? "wand.and.stars.fill" : "wand.and.stars")
                            Text("AI解析")
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(settingsManager.aiEnabled ? Color.purple.opacity(0.15) : Color.gray.opacity(0.1))
                        .foregroundColor(settingsManager.aiEnabled ? .purple : .secondary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(settingsManager.aiEnabled ? "AI 智能解析已启用" : "AI 智能解析已关闭")
                }
                
                TextEditor(text: $inputText)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .frame(minHeight: 300)
            }
            
            // 示例文本
            DisclosureGroup("查看示例格式") {
                Text(sampleText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
            }
            .font(.caption)
            .foregroundColor(.blue)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - 预览视图
    
    private var previewView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 返回编辑按钮
                HStack {
                    Button {
                        showPreview = false
                    } label: {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("返回编辑")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    
                    Spacer()
                }
                
                // 解析结果预览
                VStack(alignment: .leading, spacing: 16) {
                    Text("解析结果预览")
                        .font(.headline)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        EditablePreviewField(title: "订单编号", value: $parsedOrder.orderNumber)
                        EditablePreviewField(title: "拍摄时间", value: $parsedOrder.shootDate)
                        EditablePreviewField(title: "拍摄地点", value: $parsedOrder.shootLocation)
                        EditablePreviewField(title: "摄影师", value: $parsedOrder.photographer)
                        EditablePreviewField(title: "顾问", value: $parsedOrder.consultant)
                        EditableIntField(title: "总张数", value: $parsedOrder.totalCount)
                        EditableIntField(title: "加选数量", value: $parsedOrder.extraCount)
                        BoolPreviewField(title: "是否有产品", value: $parsedOrder.hasProduct, trueLabel: "有", falseLabel: "无")
                        DatePreviewField(title: "试修交付", date: $parsedOrder.trialDeadline)
                        DatePreviewField(title: "结片时间", date: $parsedOrder.finalDeadline)
                        EditablePreviewField(title: "客人婚期", value: $parsedOrder.weddingDate)
                        BoolPreviewField(title: "是否复购", value: $parsedOrder.isRepeatCustomer, trueLabel: "是", falseLabel: "否")
                    }
                    
                    // 客人要求
                    VStack(alignment: .leading, spacing: 8) {
                        Text("客人要求")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(parsedOrder.requirements.isEmpty ? "-" : parsedOrder.requirements)
                            .font(.subheadline)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    // 网盘链接
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("网盘链接")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if !parsedOrder.panLink.isEmpty {
                                Link(parsedOrder.panLink, destination: URL(string: parsedOrder.panLink)!)
                                    .font(.subheadline)
                            } else {
                                Text("-")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("提取码")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(parsedOrder.panCode.isEmpty ? "-" : parsedOrder.panCode)
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.medium)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                // 订单类型和标签
                VStack(alignment: .leading, spacing: 12) {
                    Text("订单设置")
                        .font(.headline)
                    
                    HStack(spacing: 24) {
                        // 拍摄类型选择
                        VStack(alignment: .leading, spacing: 8) {
                            Text("拍摄类型")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $parsedOrder.shootType) {
                                ForEach(ShootType.allCases, id: \.self) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                        
                        Divider()
                            .frame(height: 50)
                        
                        // 标签选择
                        VStack(alignment: .leading, spacing: 8) {
                            Text("订单标签")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 16) {
                                Toggle(isOn: $parsedOrder.isInGroup) {
                                    Label("进群", systemImage: "person.3.fill")
                                }
                                #if os(macOS)
                                .toggleStyle(.checkbox)
                                #endif
                                
                                Toggle(isOn: $parsedOrder.isUrgent) {
                                    Label("加急", systemImage: "bolt.fill")
                                        .foregroundColor(parsedOrder.isUrgent ? .orange : .primary)
                                }
                                #if os(macOS)
                                .toggleStyle(.checkbox)
                                #endif
                                
                                Toggle(isOn: $parsedOrder.isComplaint) {
                                    Label("投诉", systemImage: "exclamationmark.triangle.fill")
                                        .foregroundColor(parsedOrder.isComplaint ? .red : .primary)
                                }
                                #if os(macOS)
                                .toggleStyle(.checkbox)
                                #endif
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                // 分配后期人员
                VStack(alignment: .leading, spacing: 12) {
                    Text("分配后期人员")
                        .font(.headline)
                    
                    Text("选择负责该订单的后期人员")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 100))
                    ], spacing: 12) {
                        ForEach(orderManager.staffList) { staff in
                            StaffSelectButton(
                                staff: staff,
                                isSelected: selectedStaff?.id == staff.id
                            ) {
                                selectedStaff = staff
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
            }
            .padding()
        }
    }
    
    // MARK: - 方法
    
    private func parseInput() {
        isParsing = true
        parseError = nil
        isAIParsed = false
        
        // 先尝试正则解析
        let regexResult = OrderParser.parse(inputText)
        
        // 计算置信度（基于关键字段是否识别）
        let confidence = calculateConfidence(regexResult)
        
        // 如果置信度高 或 AI 未配置，直接使用正则结果
        if confidence >= 0.6 || !settingsManager.aiEnabled || settingsManager.aiApiKey.isEmpty {
            applyResult(regexResult, isAI: false)
            return
        }
        
        // 否则调用 AI 解析
        Task {
            do {
                let aiResult = try await AIService.shared.parseOrder(
                    text: inputText,
                    provider: settingsManager.currentAIProvider,
                    apiKey: settingsManager.aiApiKey,
                    endpoint: settingsManager.aiApiEndpoint,
                    model: settingsManager.aiModel
                )
                
                await MainActor.run {
                    applyResult(aiResult.toOrder(), isAI: true)
                }
            } catch {
                // AI 解析失败，回退到正则结果
                await MainActor.run {
                    parseError = "AI 解析失败，使用默认解析: \(error.localizedDescription)"
                    applyResult(regexResult, isAI: false)
                }
            }
        }
    }
    
    private func calculateConfidence(_ order: Order) -> Double {
        var score = 0.0
        if !order.orderNumber.isEmpty { score += 0.3 }
        if !order.shootDate.isEmpty { score += 0.2 }
        if !order.shootLocation.isEmpty { score += 0.1 }
        if order.totalCount > 0 { score += 0.2 }
        if order.finalDeadline != nil || order.trialDeadline != nil { score += 0.2 }
        return score
    }
    
    private func applyResult(_ order: Order, isAI: Bool) {
        parsedOrder = order
        isAIParsed = isAI
        
        // 应用提前天数规则
        if let trialDeadline = parsedOrder.trialDeadline {
            parsedOrder.trialDeadline = settingsManager.applyAdvanceDays(to: trialDeadline)
        }
        if let finalDeadline = parsedOrder.finalDeadline {
            parsedOrder.finalDeadline = settingsManager.applyAdvanceDays(to: finalDeadline)
        }
        
        isParsing = false
        showPreview = true
    }
    
    private func saveOrder() {
        var newOrder = parsedOrder
        newOrder.createdBy = authManager.currentUser?.id
        
        if let staff = selectedStaff {
            newOrder.assignedTo = staff.id
            newOrder.assignedAt = Date()
        }
        
        orderManager.addOrder(newOrder)
        dismiss()
    }
    
    private var sampleText: String {
        """
        订单编号：CS02420241231B
        拍摄档期：251230-31冰岛pvm航（包包、w秋天v，x）
        选片总数：168张
        是否加选：加选108
        是否产品：有产品
        交付试修：15天（26.1.26）
        交付全部：50天（26.3.2）
        交付客服：朵朵
        
        客人婚期：2026.10.5
        是否复购：否
        
        客人要求：男生：发型修饰...
        
        链接: https://pan.baidu.com/s/xxx 提取码: xxxx
        """
    }
}

// MARK: - 预览字段（只读）

struct PreviewField: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value.isEmpty ? "-" : value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - 可编辑预览字段

struct EditablePreviewField: View {
    let title: String
    @Binding var value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextField(title, text: $value)
                .font(.subheadline)
                .fontWeight(.medium)
                .textFieldStyle(.plain)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - 可编辑数字字段

struct EditableIntField: View {
    let title: String
    @Binding var value: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextField(title, value: $value, format: .number)
                .font(.subheadline)
                .fontWeight(.medium)
                .textFieldStyle(.plain)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - 日期选择字段

struct DatePreviewField: View {
    let title: String
    @Binding var date: Date?
    
    @State private var showPicker = false
    @State private var tempDate = Date()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button {
                tempDate = date ?? Date()
                showPicker = true
            } label: {
                HStack {
                    Text(date.map { formatChineseDate($0) } ?? "-")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(date == nil ? .secondary : .primary)
                    
                    Spacer()
                    
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                }
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .popover(isPresented: $showPicker) {
            VStack(spacing: 16) {
                DatePicker(
                    title,
                    selection: $tempDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                
                HStack {
                    Button("清除") {
                        date = nil
                        showPicker = false
                    }
                    .foregroundColor(.red)
                    
                    Spacer()
                    
                    Button("取消") {
                        showPicker = false
                    }
                    
                    Button("确定") {
                        date = tempDate
                        showPicker = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }
    
    /// 中文日期格式化
    private func formatChineseDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

// MARK: - 布尔选择字段

struct BoolPreviewField: View {
    let title: String
    @Binding var value: Bool
    let trueLabel: String
    let falseLabel: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker(title, selection: $value) {
                Text(trueLabel).tag(true)
                Text(falseLabel).tag(false)
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - 人员选择按钮

struct StaffSelectButton: View {
    let staff: User
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Circle()
                    .fill(isSelected ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(staff.displayName.prefix(1)))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(isSelected ? .white : .primary)
                    )
                
                Text(staff.displayName)
                    .font(.subheadline)
                    .foregroundColor(isSelected ? .blue : .primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NewOrderView()
        .environmentObject(OrderManager())
        .environmentObject(AuthManager())
        .environmentObject(SettingsManager())
}
