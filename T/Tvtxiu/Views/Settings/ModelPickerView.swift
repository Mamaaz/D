import SwiftUI

// MARK: - 模型选择器

struct ModelPickerView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var models: [AIModelInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedTag: AIModelTag? = nil
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索和过滤
                VStack(spacing: 12) {
                    // 搜索框
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("搜索模型名称...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    // 标签过滤
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            TagFilterButton(tag: nil, selectedTag: $selectedTag, title: "全部")
                            ForEach(AIModelTag.allCases, id: \.self) { tag in
                                TagFilterButton(tag: tag, selectedTag: $selectedTag, title: tag.displayName)
                            }
                        }
                    }
                }
                .padding()
                
                Divider()
                
                // 模型列表
                if isLoading {
                    Spacer()
                    ProgressView("正在加载模型列表...")
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("重试") {
                            loadModels()
                        }
                    }
                    Spacer()
                } else if filteredModels.isEmpty {
                    Spacer()
                    Text("没有找到匹配的模型")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredModels) { model in
                                ModelRowView(
                                    model: model,
                                    isSelected: settingsManager.aiModel == model.id
                                ) {
                                    settingsManager.aiModel = model.id
                                    dismiss()
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("选择模型")
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 400)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadModels()
        }
    }
    
    private var filteredModels: [AIModelInfo] {
        models.filter { model in
            let matchesSearch = searchText.isEmpty ||
                model.name.localizedCaseInsensitiveContains(searchText) ||
                model.id.localizedCaseInsensitiveContains(searchText)
            
            let matchesTag = selectedTag == nil || model.tags.contains(selectedTag!)
            
            return matchesSearch && matchesTag
        }
    }
    
    private func loadModels() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await AIService.shared.fetchAvailableModels(
                    provider: settingsManager.currentAIProvider,
                    apiKey: settingsManager.aiApiKey,
                    endpoint: settingsManager.aiApiEndpoint
                )
                await MainActor.run {
                    models = result
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - 标签过滤按钮

struct TagFilterButton: View {
    let tag: AIModelTag?
    @Binding var selectedTag: AIModelTag?
    let title: String
    
    private var isSelected: Bool {
        selectedTag == tag
    }
    
    var body: some View {
        Button {
            selectedTag = tag
        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.15))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 模型行视图

struct ModelRowView: View {
    let model: AIModelInfo
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                // 选中指示
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    // 名称
                    Text(model.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    // ID
                    Text(model.id)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // 描述
                    if !model.description.isEmpty {
                        Text(model.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    // 标签和价格
                    HStack(spacing: 8) {
                        // 标签
                        ForEach(Array(model.tags), id: \.self) { tag in
                            HStack(spacing: 2) {
                                Image(systemName: tag.icon)
                                Text(tag.displayName)
                            }
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        }
                        
                        Spacer()
                        
                        // 价格
                        if let pricing = model.pricing {
                            Text(pricing.promptPrice == 0 ? "免费" : pricing.formattedPromptPrice)
                                .font(.caption2)
                                .foregroundColor(pricing.promptPrice == 0 ? .green : .orange)
                        }
                        
                        // 上下文长度
                        if let contextLength = model.contextLength {
                            Text("\(contextLength / 1000)K")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.05) : Color.gray.opacity(0.05))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ModelPickerView()
        .environmentObject(SettingsManager())
}
