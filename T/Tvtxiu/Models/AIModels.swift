import Foundation

// MARK: - AI Model Info

/// AI 模型信息
struct AIModelInfo: Identifiable, Codable, Hashable {
    let id: String              // 模型 ID (e.g. google/gemini-2.0-flash)
    let name: String            // 显示名称
    let description: String     // 描述
    let tags: Set<AIModelTag>   // 模型标签
    let pricing: ModelPricing?  // 价格信息
    let contextLength: Int?     // 上下文长度
    
    init(id: String, name: String, description: String = "", tags: Set<AIModelTag> = [], pricing: ModelPricing? = nil, contextLength: Int? = nil) {
        self.id = id
        self.name = name.isEmpty ? id : name
        self.description = description
        self.tags = tags.isEmpty ? AIModelTag.inferTags(from: id) : tags
        self.pricing = pricing
        self.contextLength = contextLength
    }
}

// MARK: - AI Model Tag

/// AI 模型类型标签
enum AIModelTag: String, Codable, CaseIterable, Hashable {
    case text        // 文本
    case vision      // 视觉
    case reasoning   // 推理
    case tool        // 工具
    case code        // 代码
    case multimodal  // 多模态
    
    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .vision: return "eye"
        case .reasoning: return "lightbulb"
        case .tool: return "hammer"
        case .code: return "curlybraces"
        case .multimodal: return "sparkles"
        }
    }
    
    var displayName: String {
        switch self {
        case .text: return "文本"
        case .vision: return "视觉"
        case .reasoning: return "推理"
        case .tool: return "工具"
        case .code: return "代码"
        case .multimodal: return "多模态"
        }
    }
    
    /// 根据模型名称自动推断标签
    static func inferTags(from modelId: String) -> Set<AIModelTag> {
        let lowercased = modelId.lowercased()
        var tags: Set<AIModelTag> = []
        
        // 视觉能力
        if lowercased.contains("vision") || 
           lowercased.contains("-vl") || 
           lowercased.contains("4o") ||
           lowercased.contains("gemini-pro") ||
           lowercased.contains("gemini-2") ||
           lowercased.contains("gpt-4-turbo") {
            tags.insert(.vision)
        }
        
        // 推理能力
        if lowercased.contains("r1") ||
           lowercased.contains("think") ||
           lowercased.contains("reasoning") ||
           lowercased.contains("o1") ||
           lowercased.contains("o3") {
            tags.insert(.reasoning)
        }
        
        // 代码能力
        if lowercased.contains("code") ||
           lowercased.contains("coder") ||
           lowercased.contains("codex") ||
           lowercased.contains("starcoder") ||
           lowercased.contains("codellama") {
            tags.insert(.code)
        }
        
        // 工具调用能力（主流大模型通常支持）
        if lowercased.contains("gpt-4") ||
           lowercased.contains("gpt-3.5") ||
           lowercased.contains("claude-3") ||
           lowercased.contains("claude-4") ||
           lowercased.contains("gemini") ||
           lowercased.contains("qwen") {
            tags.insert(.tool)
        }
        
        // 多模态能力
        if lowercased.contains("4o") ||
           lowercased.contains("gemini-2") ||
           lowercased.contains("gemini-1.5") ||
           (lowercased.contains("claude") && lowercased.contains("3")) {
            tags.insert(.multimodal)
        }
        
        // 如果没有匹配到任何特殊能力，默认为文本
        if tags.isEmpty {
            tags.insert(.text)
        }
        
        return tags
    }
}

// MARK: - Model Pricing

/// 模型价格信息
struct ModelPricing: Codable, Hashable {
    let promptPrice: Double      // 输入价格 (per 1M tokens)
    let completionPrice: Double  // 输出价格 (per 1M tokens)
    
    var formattedPromptPrice: String {
        String(format: "$%.2f/1M", promptPrice)
    }
    
    var formattedCompletionPrice: String {
        String(format: "$%.2f/1M", completionPrice)
    }
}

// MARK: - Preset Models

extension AIModelInfo {
    /// 预设模型列表
    static let presetModels: [AIModelInfo] = [
        // OpenAI
        AIModelInfo(
            id: "gpt-4o",
            name: "GPT-4o",
            description: "最新旗舰模型，支持视觉和多模态",
            tags: [.text, .vision, .multimodal, .tool],
            pricing: ModelPricing(promptPrice: 5.0, completionPrice: 15.0),
            contextLength: 128000
        ),
        AIModelInfo(
            id: "gpt-4o-mini",
            name: "GPT-4o Mini",
            description: "性价比之选，快速且经济",
            tags: [.text, .vision, .tool],
            pricing: ModelPricing(promptPrice: 0.15, completionPrice: 0.6),
            contextLength: 128000
        ),
        AIModelInfo(
            id: "gpt-4-turbo",
            name: "GPT-4 Turbo",
            description: "强大的多用途模型",
            tags: [.text, .vision, .tool],
            pricing: ModelPricing(promptPrice: 10.0, completionPrice: 30.0),
            contextLength: 128000
        ),
        
        // Gemini
        AIModelInfo(
            id: "gemini-2.0-flash",
            name: "Gemini 2.0 Flash",
            description: "Google 最新快速模型",
            tags: [.text, .vision, .multimodal, .tool],
            contextLength: 1000000
        ),
        AIModelInfo(
            id: "gemini-1.5-pro",
            name: "Gemini 1.5 Pro",
            description: "长上下文旗舰模型",
            tags: [.text, .vision, .multimodal, .tool],
            contextLength: 2000000
        ),
        AIModelInfo(
            id: "gemini-1.5-flash",
            name: "Gemini 1.5 Flash",
            description: "快速轻量模型",
            tags: [.text, .vision, .multimodal, .tool],
            contextLength: 1000000
        ),
        
        // OpenRouter 常用
        AIModelInfo(
            id: "google/gemini-2.0-flash-exp:free",
            name: "Gemini 2.0 Flash (OpenRouter Free)",
            description: "OpenRouter 免费额度",
            tags: [.text, .vision, .multimodal],
            pricing: ModelPricing(promptPrice: 0, completionPrice: 0)
        ),
        AIModelInfo(
            id: "anthropic/claude-3.5-sonnet",
            name: "Claude 3.5 Sonnet",
            description: "Anthropic 旗舰模型",
            tags: [.text, .code, .tool],
            pricing: ModelPricing(promptPrice: 3.0, completionPrice: 15.0),
            contextLength: 200000
        ),
    ]
}
