import Foundation

// MARK: - 日期格式化工具

/// 统一的日期格式化工具，提供一致的日期显示格式
enum DateFormatters {
    
    // MARK: - 静态格式化器（复用避免重复创建）
    
    /// 中文日期格式：2025年1月11日
    static let chineseDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()
    
    /// 年月格式：2025-01
    static let yearMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
    
    /// 标准日期格式：2025-01-11
    static let standard: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    /// 短日期格式：01/11
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter
    }()
    
    /// ISO8601 格式化器
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    /// ISO8601 带微秒
    static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    // MARK: - 格式化方法
    
    /// 将 Date 格式化为中文日期
    static func formatToChinese(_ date: Date) -> String {
        chineseDate.string(from: date)
    }
    
    /// 将 Date 格式化为年月
    static func formatToYearMonth(_ date: Date) -> String {
        yearMonth.string(from: date)
    }
    
    /// 将 Date 格式化为标准格式
    static func formatToStandard(_ date: Date) -> String {
        standard.string(from: date)
    }
    
    // MARK: - 解析方法
    
    /// 解析 ISO8601 日期字符串
    static func parseISO8601(_ string: String?) -> Date? {
        guard let s = string, !s.isEmpty else { return nil }
        return iso8601.date(from: s) ?? iso8601WithFractional.date(from: s)
    }
    
    /// 智能解析拍摄日期（支持多种格式）
    /// 支持格式：25/9/6-7, 250906-07, 2025年9月6日, 9月6-7日 等
    static func formatShootDateToChinese(_ dateString: String) -> String {
        let trimmed = dateString.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "-" }
        
        // 已经是中文格式
        if trimmed.contains("年") && trimmed.contains("月") {
            return trimmed
        }
        
        // 格式1: 25/9/6-7 或 25/9/6
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/")
            if parts.count >= 3 {
                let year = "20\(parts[0])"
                let month = parts[1]
                let day = parts[2]
                return "\(year)年\(month)月\(day)日"
            }
        }
        
        // 格式2: 250906-07 或 250906
        if trimmed.count >= 6, let _ = Int(String(trimmed.prefix(6))) {
            let yearStr = String(trimmed.prefix(2))
            let startIndex = trimmed.index(trimmed.startIndex, offsetBy: 2)
            let midIndex = trimmed.index(trimmed.startIndex, offsetBy: 4)
            let monthStr = String(trimmed[startIndex..<midIndex])
            
            let year = "20\(yearStr)"
            let month = Int(monthStr) ?? 0
            
            // 检查是否有日期范围（-）
            if trimmed.contains("-") {
                let dayParts = trimmed.dropFirst(4).split(separator: "-")
                if dayParts.count >= 1 {
                    let startDay = Int(dayParts[0]) ?? 0
                    if dayParts.count >= 2 {
                        let endDay = dayParts[1]
                        return "\(year)年\(month)月\(startDay)-\(endDay)日"
                    }
                    return "\(year)年\(month)月\(startDay)日"
                }
            } else {
                let dayStr = String(trimmed.dropFirst(4))
                let day = Int(dayStr) ?? 0
                return "\(year)年\(month)月\(day)日"
            }
        }
        
        // 格式3: 直接返回原字符串
        return trimmed
    }
    
    // MARK: - 相对时间
    
    /// 计算距离现在的天数
    static func daysFromNow(_ date: Date) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: today, to: targetDate).day ?? 0
    }
    
    /// 格式化相对时间描述
    static func relativeTimeDescription(_ date: Date) -> String {
        let days = daysFromNow(date)
        
        switch days {
        case ..<0:
            return "已过期 \(abs(days)) 天"
        case 0:
            return "今天"
        case 1:
            return "明天"
        case 2:
            return "后天"
        case 3...7:
            return "\(days) 天后"
        default:
            return formatToChinese(date)
        }
    }
}
