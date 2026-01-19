import Foundation

// MARK: - 智能解析服务

/// 订单文本解析器
/// 从微信粘贴的文本中自动提取订单信息
struct OrderParser {
    
    /// 解析订单文本
    static func parse(_ text: String) -> Order {
        var order = Order()
        
        // 解析订单编号
        if let match = text.firstMatch(pattern: #"订单编号[：:]\s*([A-Z0-9]+)"#) {
            order.orderNumber = match
        }
        
        // 解析拍摄档期 (格式: 251230-31冰岛pvm航 或 251228上海纱pm1内2外（一霖、鑫鑫）)
        // 分步解析：先获取整行，再分别提取日期、地点、摄影师
        if let scheduleText = text.firstMatch(pattern: #"拍摄档期[：:]\s*(.+?)(?=\n|$)"#) {
            // 解析日期 (支持6位数字或6位-2位多日格式，如 251230 或 251230-31)
            if let dateMatch = scheduleText.firstMatch(pattern: #"(\d{6}(?:-\d{1,2})?)"#) {
                order.shootDate = dateMatch
            }
            
            // 解析地点 (日期后的2-4个中文字符，忽略后面的拼音等)
            if let locationMatch = scheduleText.firstMatch(pattern: #"\d{6}(?:-\d{1,2})?\s*([\u4e00-\u9fa5]{2,4})"#) {
                order.shootLocation = locationMatch
            }
            
            // 解析摄影师 (括号内的内容，兼容旧格式)
            if let photographerMatch = scheduleText.firstMatch(pattern: #"[（(]([^）)]+)[）)]"#) {
                order.photographer = photographerMatch
            }
        }
        
        // 解析拍摄人员 (新格式：单独一行)
        if let match = text.firstMatch(pattern: #"拍摄人员[：:]\s*(.+?)(?=\n|$)"#) {
            order.photographer = match.trimmingCharacters(in: .whitespaces)
        }
        
        // 解析选片总数
        if let match = text.firstMatch(pattern: #"选片总数[：:]\s*(\d+)"#) {
            order.totalCount = Int(match) ?? 0
        }
        
        // 解析加选数量
        if let match = text.firstMatch(pattern: #"(?:是否)?加选[：:]\s*(?:加选)?(\d+)"#) {
            order.extraCount = Int(match) ?? 0
        }
        
        // 解析是否有产品
        if let match = text.firstMatch(pattern: #"是否产品[：:]\s*(有|无|是|否)"#) {
            order.hasProduct = match == "有" || match == "是"
        }
        
        // 解析试修交付时间
        if let match = text.firstMatch(pattern: #"交付试修[：:]\s*\d+天[（(](\d{2}\.\d{1,2}\.\d{1,2})[）)]"#) {
            order.trialDeadline = parseDate(match)
        }
        
        // 解析全部交付时间
        if let match = text.firstMatch(pattern: #"交付全部[：:]\s*\d+天[（(](\d{2}\.\d{1,2}\.\d{1,2})[）)]"#) {
            order.finalDeadline = parseDate(match)
        }
        
        // 解析交付客服
        if let match = text.firstMatch(pattern: #"交付客服[：:]\s*(\S+)"#) {
            order.consultant = match
        }
        
        // 解析客人婚期 (直接存储原文本)
        if let match = text.firstMatch(pattern: #"客人婚期[：:]\s*(.+?)(?=\n|$)"#) {
            order.weddingDate = match.trimmingCharacters(in: .whitespaces)
        }
        
        // 解析是否复购
        if let match = text.firstMatch(pattern: #"是否复购[：:]\s*(是|否)"#) {
            order.isRepeatCustomer = match == "是"
        }
        
        // 解析客人要求
        if let match = text.firstMatch(pattern: #"客人要求[：:](.+?)(?=通过网盘|链接:|$)"#, options: [.dotMatchesLineSeparators]) {
            order.requirements = match.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 解析网盘链接
        if let match = text.firstMatch(pattern: #"链接:\s*(https?://[^\s]+)"#) {
            order.panLink = match
        }
        
        // 解析提取码
        if let match = text.firstMatch(pattern: #"提取码:\s*(\w+)"#) {
            order.panCode = match
        }
        
        return order
    }
    
    // MARK: - 日期解析
    
    /// 解析短日期格式 (如 "26.1.26")
    private static func parseDate(_ text: String) -> Date? {
        let parts = text.split(separator: ".")
        guard parts.count == 3 else { return nil }
        
        let year = 2000 + (Int(parts[0]) ?? 0)
        let month = Int(parts[1]) ?? 1
        let day = Int(parts[2]) ?? 1
        
        return DateComponents(
            calendar: .current,
            year: year,
            month: month,
            day: day
        ).date
    }
    
    /// 解析完整日期格式 (如 "2026.10.5")
    private static func parseFullDate(_ text: String) -> Date? {
        let parts = text.split(separator: ".")
        guard parts.count == 3 else { return nil }
        
        let year = Int(parts[0]) ?? 2026
        let month = Int(parts[1]) ?? 1
        let day = Int(parts[2]) ?? 1
        
        return DateComponents(
            calendar: .current,
            year: year,
            month: month,
            day: day
        ).date
    }
}

// MARK: - String 正则扩展

extension String {
    /// 获取第一个匹配的捕获组
    func firstMatch(pattern: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        
        let range = NSRange(self.startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: self) else {
            return nil
        }
        
        return String(self[captureRange])
    }
    
    /// 获取多个捕获组
    func firstMatch(pattern: String, groups: [Int], options: NSRegularExpression.Options = []) -> [String?] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return groups.map { _ in nil }
        }
        
        let range = NSRange(self.startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, options: [], range: range) else {
            return groups.map { _ in nil }
        }
        
        return groups.map { index in
            guard match.numberOfRanges > index,
                  let captureRange = Range(match.range(at: index), in: self) else {
                return nil
            }
            return String(self[captureRange])
        }
    }
}
