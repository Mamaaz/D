import Foundation

// MARK: - 中国农历工具

struct ChineseLunarCalendar {
    private static let calendar = Calendar(identifier: .chinese)
    
    // 农历月份名称
    private static let lunarMonthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]
    
    // 农历日期名称
    private static let lunarDayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]
    
    // 中文数字月份
    private static let chineseMonthNames = [
        "一月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "十一月", "十二月"
    ]
    
    /// 获取农历日期字符串
    static func lunarDay(from date: Date) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let day = components.day, day > 0, day <= 30 else {
            return ""
        }
        
        // 如果是初一，显示月份
        if day == 1 {
            if let month = components.month, month > 0, month <= 12 {
                return lunarMonthNames[month - 1]
            }
        }
        
        return lunarDayNames[day - 1]
    }
    
    /// 获取农历月份和日期
    static func lunarMonthDay(from date: Date) -> (month: String, day: String) {
        let components = calendar.dateComponents([.month, .day], from: date)
        
        var monthStr = ""
        var dayStr = ""
        
        if let month = components.month, month > 0, month <= 12 {
            monthStr = lunarMonthNames[month - 1]
        }
        
        if let day = components.day, day > 0, day <= 30 {
            dayStr = lunarDayNames[day - 1]
        }
        
        return (monthStr, dayStr)
    }
    
    /// 格式化公历月份为中文（2026年一月）
    static func formatMonthYear(_ date: Date) -> String {
        let gregorian = Calendar(identifier: .gregorian)
        let components = gregorian.dateComponents([.year, .month], from: date)
        
        guard let year = components.year, let month = components.month,
              month > 0, month <= 12 else {
            return ""
        }
        
        return "\(year)年\(chineseMonthNames[month - 1])"
    }
}
