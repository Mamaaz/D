import SwiftUI

// MARK: - AI 设置区域

/// AI 智能解析设置（从 SettingsView 提取）
struct AISettingsSection: View {
    @EnvironmentObject var settingsManager: SettingsManager
    
    @State private var isTestingAI: Bool = false
    @State private var aiTestResult: String?
    @State private var showModelPicker: Bool = false
    
    var body: some View {
        Section("AI 智能解析") {
            Toggle("启用 AI 解析", isOn: $settingsManager.aiEnabled)
            
            if settingsManager.aiEnabled {
                providerPicker
                apiKeyField
                
                if settingsManager.currentAIProvider == .custom {
                    endpointField
                }
                
                modelSelector
                testConnectionButton
                testResultLabel
            }
            
            Text("启用后，解析订单时将使用 AI 辅助识别复杂格式")
                .font(TvtDesign.Typography.caption)
                .foregroundColor(.secondary)
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView()
        }
    }
    
    // MARK: - 子视图
    
    private var providerPicker: some View {
        Picker("AI 提供商", selection: $settingsManager.aiProvider) {
            ForEach(AIService.AIProvider.allCases, id: \.rawValue) { provider in
                Text(provider.rawValue).tag(provider.rawValue)
            }
        }
        .onChange(of: settingsManager.aiProvider) { newValue in
            if let provider = AIService.AIProvider(rawValue: newValue) {
                settingsManager.setAIProvider(provider)
            }
        }
    }
    
    private var apiKeyField: some View {
        SecureField("API Key", text: $settingsManager.aiApiKey)
            .textFieldStyle(.roundedBorder)
    }
    
    private var endpointField: some View {
        TextField("API 端点", text: $settingsManager.aiApiEndpoint)
            .textFieldStyle(.roundedBorder)
    }
    
    private var modelSelector: some View {
        HStack {
            TextField("模型名称", text: $settingsManager.aiModel)
                .textFieldStyle(.roundedBorder)
            
            Button {
                showModelPicker = true
            } label: {
                Image(systemName: "list.bullet")
            }
            .disabled(settingsManager.aiApiKey.isEmpty)
            .help("浏览可用模型")
        }
    }
    
    private var testConnectionButton: some View {
        Button {
            testAIConnection()
        } label: {
            HStack {
                if isTestingAI {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "network")
                }
                Text("测试连接")
            }
        }
        .disabled(settingsManager.aiApiKey.isEmpty || isTestingAI)
    }
    
    @ViewBuilder
    private var testResultLabel: some View {
        if let result = aiTestResult {
            Text(result)
                .font(TvtDesign.Typography.caption)
                .foregroundColor(result.contains("成功") ? TvtDesign.Colors.success : TvtDesign.Colors.error)
        }
    }
    
    // MARK: - 方法
    
    private func testAIConnection() {
        isTestingAI = true
        aiTestResult = nil
        
        Task {
            do {
                let result = try await AIService.shared.testConnection(
                    provider: settingsManager.currentAIProvider,
                    apiKey: settingsManager.aiApiKey,
                    endpoint: settingsManager.aiApiEndpoint,
                    model: settingsManager.aiModel
                )
                await MainActor.run {
                    aiTestResult = result
                    isTestingAI = false
                }
            } catch {
                await MainActor.run {
                    aiTestResult = "连接失败: \(error.localizedDescription)"
                    isTestingAI = false
                }
            }
        }
    }
}

// MARK: - 预览

#Preview {
    Form {
        AISettingsSection()
    }
    .environmentObject(SettingsManager())
    .frame(width: 500)
}
