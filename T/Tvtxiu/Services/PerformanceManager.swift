import Foundation
import SwiftUI

// MARK: - 绩效管理器

@MainActor
class PerformanceManager: ObservableObject {
    
    // MARK: - Published 属性
    
    /// 月度绩效配置列表
    @Published var monthlyConfigs: [MonthlyPerformanceConfig] = [] {
        didSet { saveMonthlyConfigs() }
    }
    
    // MARK: - 存储键
    
    private let monthlyConfigsKey = "Tvtxiu_MonthlyPerformanceConfigs"
    
    // MARK: - 初始化
    
    init() {
        loadMonthlyConfigs()
    }
    
    // MARK: - 月度配置管理
    
    /// 获取或创建指定用户指定月份的配置
    func monthlyConfig(for userId: UUID, month: String) -> MonthlyPerformanceConfig {
        if let existing = monthlyConfigs.first(where: { $0.userId == userId && $0.month == month }) {
            return existing
        }
        // 创建新配置
        let newConfig = MonthlyPerformanceConfig(userId: userId, month: month)
        monthlyConfigs.append(newConfig)
        return newConfig
    }
    
    /// 更新月度配置
    func updateMonthlyConfig(_ config: MonthlyPerformanceConfig) {
        if let index = monthlyConfigs.firstIndex(where: { $0.id == config.id }) {
            var updated = config
            updated.updatedAt = Date()
            monthlyConfigs[index] = updated
        } else {
            monthlyConfigs.append(config)
        }
    }
    
    /// 设置用户月度工资社保
    func setSalarySocial(for userId: UUID, month: String, amount: Double) {
        var config = monthlyConfig(for: userId, month: month)
        config.salarySocialTotal = amount
        config.updatedAt = Date()
        updateMonthlyConfig(config)
    }
    
    /// 保存月度配置
    private func saveMonthlyConfigs() {
        if let data = try? JSONEncoder().encode(monthlyConfigs) {
            UserDefaults.standard.set(data, forKey: monthlyConfigsKey)
        }
    }
    
    /// 加载月度配置
    private func loadMonthlyConfigs() {
        guard let data = UserDefaults.standard.data(forKey: monthlyConfigsKey),
              let configs = try? JSONDecoder().decode([MonthlyPerformanceConfig].self, from: data) else {
            return
        }
        self.monthlyConfigs = configs
    }
    
    // MARK: - 绩效计算
    
    /// 计算订单的单张绩效（直接使用用户配置）
    func calculatePerformance(for order: Order, user: User) -> Double {
        return order.calculatePerformance(user: user)
    }
    
    /// 计算用户在指定月份的修图绩效总额
    func calculateMonthlyPerformance(for user: User, month: String, orders: [Order]) -> Double {
        let userOrders = orders.filter {
            $0.assignedTo == user.id &&
            $0.assignedMonth == month &&
            $0.isCompleted
        }
        
        var totalPerformance: Double = 0
        for order in userOrders {
            let perPhoto = order.calculatePerformance(user: user)
            totalPerformance += perPhoto * Double(order.totalCount)
        }
        
        return totalPerformance
    }
    
    /// 计算用户在指定月份的单张成本
    /// 公式: (工资社保合计 + 修图绩效) ÷ 完成张数
    func calculateCostPerPhoto(for user: User, month: String, orders: [Order]) -> Double? {
        let config = monthlyConfig(for: user.id, month: month)
        let salarySocial = config.salarySocialTotal
        
        // 如果没有填写工资社保，返回 nil
        guard salarySocial > 0 else { return nil }
        
        let performance = calculateMonthlyPerformance(for: user, month: month, orders: orders)
        
        let completedPhotos = orders
            .filter { $0.assignedTo == user.id && $0.assignedMonth == month && $0.isCompleted }
            .reduce(0) { $0 + $1.totalCount }
        
        guard completedPhotos > 0 else { return nil }
        
        return (salarySocial + performance) / Double(completedPhotos)
    }
    
    /// 获取用户在指定月份的完成张数
    func completedPhotos(for user: User, month: String, orders: [Order]) -> Int {
        orders
            .filter { $0.assignedTo == user.id && $0.assignedMonth == month && $0.isCompleted }
            .reduce(0) { $0 + $1.totalCount }
    }
}
