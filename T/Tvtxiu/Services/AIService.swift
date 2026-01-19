import Foundation

// MARK: - AI 服务

/// AI 订单解析服务
@MainActor
class AIService: ObservableObject {
    static let shared = AIService()
    
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    
    // MARK: - AI 提供商
    
    enum AIProvider: String, CaseIterable {
        case openai = "OpenAI"
        case gemini = "Gemini"
        case custom = "自定义"
        
        var defaultEndpoint: String {
            switch self {
            case .openai:
                return "https://api.openai.com/v1/chat/completions"
            case .gemini:
                return "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
            case .custom:
                return ""
            }
        }
        
        var defaultModel: String {
            switch self {
            case .openai:
                return "gpt-4o-mini"
            case .gemini:
                return "gemini-1.5-flash"
            case .custom:
                return ""
            }
        }
    }
    
    // MARK: - 解析订单
    
    /// 使用 AI 解析订单文本
    func parseOrder(text: String, provider: AIProvider, apiKey: String, endpoint: String, model: String) async throws -> AIOrderResult {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        
        let prompt = buildPrompt(text: text)
        
        let response: String
        switch provider {
        case .openai, .custom:
            response = try await callOpenAICompatible(prompt: prompt, apiKey: apiKey, endpoint: endpoint, model: model)
        case .gemini:
            response = try await callGemini(prompt: prompt, apiKey: apiKey, model: model)
        }
        
        // 解析 JSON 响应
        return try parseResponse(response)
    }
    
    // MARK: - 测试连接
    
    /// 测试 API 连接
    func testConnection(provider: AIProvider, apiKey: String, endpoint: String, model: String) async throws -> String {
        let testPrompt = "请回复：连接成功"
        
        switch provider {
        case .openai, .custom:
            let response = try await callOpenAICompatible(prompt: testPrompt, apiKey: apiKey, endpoint: endpoint, model: model)
            return "连接成功：\(response.prefix(50))..."
        case .gemini:
            let response = try await callGemini(prompt: testPrompt, apiKey: apiKey, model: model)
            return "连接成功：\(response.prefix(50))..."
        }
    }
    
    // MARK: - 获取可用模型列表
    
    /// 获取可用模型列表
    func fetchAvailableModels(provider: AIProvider, apiKey: String, endpoint: String) async throws -> [AIModelInfo] {
        switch provider {
        case .custom:
            // 检测是否为 OpenRouter
            if endpoint.lowercased().contains("openrouter.ai") {
                return try await fetchOpenRouterModels(apiKey: apiKey, endpoint: endpoint)
            }
            // 其他自定义端点返回预设列表
            return AIModelInfo.presetModels
            
        case .openai:
            return AIModelInfo.presetModels.filter { $0.id.hasPrefix("gpt-") }
            
        case .gemini:
            return AIModelInfo.presetModels.filter { $0.id.hasPrefix("gemini-") }
        }
    }
    
    /// 获取 OpenRouter 模型列表
    private func fetchOpenRouterModels(apiKey: String, endpoint: String) async throws -> [AIModelInfo] {
        // 从 endpoint 获取 base URL，然后调用 /models
        var baseURL = endpoint
        if baseURL.hasSuffix("/chat/completions") {
            baseURL = String(baseURL.dropLast("/chat/completions".count))
        }
        baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        guard let url = URL(string: "\(baseURL)/models") else {
            throw AIError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AIError.apiError("无法获取模型列表")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsData = json["data"] as? [[String: Any]] else {
            throw AIError.parseError("无法解析模型列表")
        }
        
        return modelsData.compactMap { modelDict in
            guard let id = modelDict["id"] as? String else { return nil }
            
            let name = modelDict["name"] as? String ?? id
            let description = modelDict["description"] as? String ?? ""
            let contextLength = modelDict["context_length"] as? Int
            
            var pricing: ModelPricing? = nil
            if let pricingDict = modelDict["pricing"] as? [String: Any],
               let promptStr = pricingDict["prompt"] as? String,
               let completionStr = pricingDict["completion"] as? String,
               let promptPrice = Double(promptStr),
               let completionPrice = Double(completionStr) {
                pricing = ModelPricing(
                    promptPrice: promptPrice * 1_000_000,
                    completionPrice: completionPrice * 1_000_000
                )
            }
            
            return AIModelInfo(
                id: id,
                name: name,
                description: description,
                pricing: pricing,
                contextLength: contextLength
            )
        }
    }
    
    // MARK: - OpenAI 兼容 API
    
    private func callOpenAICompatible(prompt: String, apiKey: String, endpoint: String, model: String) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw AIError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // OpenRouter 需要的额外请求头
        if endpoint.contains("openrouter.ai") {
            request.setValue("https://tvtxiu.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("Tvtxiu", forHTTPHeaderField: "X-Title")
        }
        
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.1
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            // 尝试解析错误响应
            let responseBody = String(data: data, encoding: .utf8) ?? "无法读取响应"
            
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIError.apiError("[\(httpResponse.statusCode)] \(message)")
            }
            
            // 显示完整响应以便调试
            throw AIError.apiError("HTTP \(httpResponse.statusCode): \(responseBody.prefix(200))")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            // 显示实际响应内容以便调试
            let responseBody = String(data: data, encoding: .utf8) ?? "无法读取响应"
            throw AIError.parseError("无法解析 AI 响应。实际响应: \(responseBody.prefix(200))")
        }
        
        return content
    }
    
    // MARK: - Gemini API
    
    private func callGemini(prompt: String, apiKey: String, model: String) async throws -> String {
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        
        guard let url = URL(string: endpoint) else {
            throw AIError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": 0.1
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIError.apiError(message)
            }
            throw AIError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw AIError.parseError("无法解析 Gemini 响应")
        }
        
        return text
    }
    
    // MARK: - Prompt 构建
    
    private func buildPrompt(text: String) -> String {
        return """
        你是一个订单信息提取专家。请从以下微信群消息中提取婚纱影楼订单信息，返回 JSON 格式。

        返回格式（只返回 JSON，不要其他解释）：
        {
          "orderNumber": "订单编号，如 CS02420241231A",
          "shootDate": "拍摄日期，格式 YYMMDD 或原文",
          "shootLocation": "拍摄地点",
          "photographer": "摄影师",
          "consultant": "顾问/客服",
          "totalCount": 100,
          "extraCount": 0,
          "hasProduct": true,
          "trialDeadline": "试修交付日期 YYYY-MM-DD 或 null",
          "finalDeadline": "结片交付日期 YYYY-MM-DD 或 null",
          "weddingDate": "婚期描述原文",
          "isRepeatCustomer": false,
          "requirements": "客人要求",
          "panLink": "网盘链接",
          "panCode": "提取码"
        }

        规则：
        1. 如果某字段无法识别，设为 null
        2. 数字类型字段无法识别时设为 0
        3. 布尔类型字段无法识别时设为 false
        4. 日期尽量转换为标准格式

        消息内容：
        \(text)
        """
    }
    
    // MARK: - 响应解析
    
    private func parseResponse(_ response: String) throws -> AIOrderResult {
        // 提取 JSON 部分（处理可能的 markdown 代码块）
        var jsonString = response
        
        if let startRange = response.range(of: "```json"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            jsonString = String(response[startRange.upperBound..<endRange.lowerBound])
        } else if let startRange = response.range(of: "```"),
                  let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            jsonString = String(response[startRange.upperBound..<endRange.lowerBound])
        } else if let startIndex = response.firstIndex(of: "{"),
                  let endIndex = response.lastIndex(of: "}") {
            jsonString = String(response[startIndex...endIndex])
        }
        
        guard let data = jsonString.data(using: .utf8) else {
            throw AIError.parseError("无法转换为 Data")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(AIOrderResult.self, from: data)
    }
}

// MARK: - AI 解析结果

struct AIOrderResult: Codable {
    var orderNumber: String?
    var shootDate: String?
    var shootLocation: String?
    var photographer: String?
    var consultant: String?
    var totalCount: Int?
    var extraCount: Int?
    var hasProduct: Bool?
    var trialDeadline: String?
    var finalDeadline: String?
    var weddingDate: String?
    var isRepeatCustomer: Bool?
    var requirements: String?
    var panLink: String?
    var panCode: String?
    
    /// 转换为 Order 对象
    func toOrder() -> Order {
        var order = Order()
        
        order.orderNumber = orderNumber ?? ""
        order.shootDate = shootDate ?? ""
        order.shootLocation = shootLocation ?? ""
        order.photographer = photographer ?? ""
        order.consultant = consultant ?? ""
        order.totalCount = totalCount ?? 0
        order.extraCount = extraCount ?? 0
        order.hasProduct = hasProduct ?? false
        order.weddingDate = weddingDate ?? ""
        order.isRepeatCustomer = isRepeatCustomer ?? false
        order.requirements = requirements ?? ""
        order.panLink = panLink ?? ""
        order.panCode = panCode ?? ""
        
        // 解析日期
        if let trialStr = trialDeadline {
            order.trialDeadline = parseDate(trialStr)
        }
        if let finalStr = finalDeadline {
            order.finalDeadline = parseDate(finalStr)
        }
        
        return order
    }
    
    private func parseDate(_ str: String) -> Date? {
        let formatters = [
            "yyyy-MM-dd",
            "yy.MM.dd",
            "yy/MM/dd"
        ]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: str) {
                return date
            }
        }
        return nil
    }
}

// MARK: - AI 错误

enum AIError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case apiError(String)
    case parseError(String)
    case notConfigured
    
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "无效的 API 端点"
        case .invalidResponse:
            return "无效的响应"
        case .apiError(let message):
            return "API 错误: \(message)"
        case .parseError(let message):
            return "解析错误: \(message)"
        case .notConfigured:
            return "AI 未配置，请在设置中配置 API"
        }
    }
}
