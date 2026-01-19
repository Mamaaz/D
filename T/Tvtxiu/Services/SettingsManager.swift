import Foundation
import SwiftUI

// MARK: - 设置管理器

@MainActor
class SettingsManager: ObservableObject {
    // 提前天数规则
    @AppStorage("advanceDays") var advanceDays: Int = 0
    
    // 提醒设置
    @AppStorage("reminderEnabled") var reminderEnabled: Bool = true
    @AppStorage("reminderDaysBefore") var reminderDaysBefore: Int = 3
    
    // 服务器地址
    @AppStorage("serverAddress") var serverAddress: String = "http://localhost:8080"
    
    // 界面设置
    @AppStorage("sidebarWidth") var sidebarWidth: Double = 250
    @AppStorage("compactMode") var compactMode: Bool = false
    
    // MARK: - AI 配置
    
    /// AI 提供商
    @AppStorage("aiProvider") var aiProvider: String = "openai"
    
    /// AI API Key（使用 Keychain 安全存储）
    var aiApiKey: String {
        get { KeychainManager.load(key: KeychainManager.aiApiKeyKey) ?? "" }
        set {
            if newValue.isEmpty {
                KeychainManager.delete(key: KeychainManager.aiApiKeyKey)
            } else {
                KeychainManager.save(key: KeychainManager.aiApiKeyKey, value: newValue)
            }
            objectWillChange.send()
        }
    }
    
    /// AI API 端点
    @AppStorage("aiApiEndpoint") var aiApiEndpoint: String = "https://api.openai.com/v1/chat/completions"
    
    /// AI 模型
    @AppStorage("aiModel") var aiModel: String = "gpt-4o-mini"
    
    /// 是否启用 AI 解析
    @AppStorage("aiEnabled") var aiEnabled: Bool = false
    
    /// 获取当前 AI 提供商枚举
    var currentAIProvider: AIService.AIProvider {
        AIService.AIProvider(rawValue: aiProvider) ?? .openai
    }
    
    /// 应用提前天数规则到日期
    func applyAdvanceDays(to date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -advanceDays, to: date) ?? date
    }
    
    /// 更新 AI 提供商并设置默认值
    func setAIProvider(_ provider: AIService.AIProvider) {
        aiProvider = provider.rawValue
        if provider != .custom {
            aiApiEndpoint = provider.defaultEndpoint
            aiModel = provider.defaultModel
        }
    }
}

