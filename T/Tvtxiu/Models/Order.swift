import Foundation

// MARK: - 拍摄类型枚举

enum ShootType: String, Codable, CaseIterable {
    case wedding = "婚纱"
    case ceremony = "婚礼"
    
    var displayName: String {
        return self.rawValue
    }
    
    /// 婚礼类型绩效系数
    var performanceMultiplier: Double {
        switch self {
        case .wedding: return 1.0
        case .ceremony: return 0.8
        }
    }
}

// MARK: - 订单模型

/// 订单模型
struct Order: Identifiable, Codable, Hashable {
    let id: UUID
    var orderNumber: String          // 订单编号
    var shootDate: String            // 拍摄时间 (如 "251230-31")
    var shootLocation: String        // 拍摄地点
    var photographer: String         // 摄影师信息
    var consultant: String           // 顾问 (客服)
    var totalCount: Int              // 总张数
    var extraCount: Int              // 加选数量
    var hasProduct: Bool             // 是否有产品
    var trialDeadline: Date?         // 试修交付时间
    var finalDeadline: Date?         // 结片时间 (最终交付)
    var weddingDate: String           // 客人婚期 (原文本，如 "春节以后")
    var isRepeatCustomer: Bool       // 是否复购
    var requirements: String         // 客人要求
    var panLink: String              // 网盘链接
    var panCode: String              // 提取码
    var assignedTo: UUID?            // 分配给的后期人员 ID
    var assignedUserName: String?    // 分配人员姓名（从 API 获取）
    var assignedAt: Date?            // 分配时间
    var remarks: String              // 备注 (投诉原因等)
    var remarksHistory: [Date]        // 备注修改历史
    var isCompleted: Bool            // 是否交付
    var completedAt: Date?           // 完成时间
    
    // 新增字段
    var shootType: ShootType         // 拍摄类型：婚纱/婚礼
    var isInGroup: Bool              // 是否进群 (默认为是)
    var isUrgent: Bool               // 是否加急 (橙色显示)
    var isComplaint: Bool            // 是否为投诉处理订单
    
    // 归档相关
    var isArchived: Bool             // 是否已归档
    var archiveMonth: String?        // 归档月份 (如 "2025-12")
    
    var createdBy: UUID?             // 创建人 ID
    var createdAt: Date              // 创建时间
    var updatedAt: Date              // 更新时间
    
    // MARK: - 绩效计算
    
    /// 计算单张绩效金额（使用用户个人配置）
    /// - Parameter user: 分配的用户（包含绩效配置）
    /// - Returns: 单张绩效金额
    func performancePerPhoto(user: User) -> Double {
        var rate = user.basePrice
        
        // 加急或投诉加成（二选一，投诉优先）
        // 有投诉或加急时，进群加项不生效
        if isComplaint {
            rate += user.complaintBonus
        } else if isUrgent {
            rate += user.urgentBonus
        } else if isInGroup {
            // 只有没有加急/投诉时，进群才生效
            rate += user.groupBonus
        }
        
        // 婚礼类型打折
        if shootType == .ceremony {
            rate *= user.weddingMultiplier
        }
        
        return rate
    }
    
    /// 计算订单总绩效金额
    func totalPerformance(user: User) -> Double {
        return performancePerPhoto(user: user) * Double(totalCount)
    }
    
    init(
        id: UUID = UUID(),
        orderNumber: String = "",
        shootDate: String = "",
        shootLocation: String = "",
        photographer: String = "",
        consultant: String = "",
        totalCount: Int = 0,
        extraCount: Int = 0,
        hasProduct: Bool = false,
        trialDeadline: Date? = nil,
        finalDeadline: Date? = nil,
        weddingDate: String = "",
        isRepeatCustomer: Bool = false,
        requirements: String = "",
        panLink: String = "",
        panCode: String = "",
        assignedTo: UUID? = nil,
        assignedUserName: String? = nil,
        assignedAt: Date? = nil,
        remarks: String = "",
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        shootType: ShootType = .wedding,
        isInGroup: Bool = true,
        isUrgent: Bool = false,
        isComplaint: Bool = false,
        isArchived: Bool = false,
        archiveMonth: String? = nil,
        createdBy: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.orderNumber = orderNumber
        self.shootDate = shootDate
        self.shootLocation = shootLocation
        self.photographer = photographer
        self.consultant = consultant
        self.totalCount = totalCount
        self.extraCount = extraCount
        self.hasProduct = hasProduct
        self.trialDeadline = trialDeadline
        self.finalDeadline = finalDeadline
        self.weddingDate = weddingDate
        self.isRepeatCustomer = isRepeatCustomer
        self.requirements = requirements
        self.panLink = panLink
        self.panCode = panCode
        self.assignedTo = assignedTo
        self.assignedUserName = assignedUserName
        self.assignedAt = assignedAt
        self.remarks = remarks
        self.remarksHistory = []
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.shootType = shootType
        self.isInGroup = isInGroup
        self.isUrgent = isUrgent
        self.isComplaint = isComplaint
        self.isArchived = isArchived
        self.archiveMonth = archiveMonth
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// 订单归属月份 (基于分配时间)
    var assignedMonth: String? {
        guard let date = assignedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
    
    /// 是否逾期
    var isOverdue: Bool {
        guard let deadline = finalDeadline, !isCompleted else { return false }
        return Date() > deadline
    }
    
    /// 距离交付天数 (负数表示已逾期)
    var daysUntilDeadline: Int? {
        guard let deadline = finalDeadline else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: deadline)
        return components.day
    }
    
    /// 计算单张绩效加项（使用用户配置）
    /// 规则：投诉优先，加急次之，只有无投诉和加急时进群才生效
    func performanceBonus(user: User) -> Double {
        // 投诉和加急同时存在，只算投诉
        if isComplaint {
            return user.complaintBonus
        }
        if isUrgent {
            return user.urgentBonus
        }
        // 只有进群标签时
        if isInGroup {
            return user.groupBonus
        }
        return 0.0
    }
    
    /// 计算单张绩效 (使用用户配置)
    func calculatePerformance(user: User) -> Double {
        let bonus = performanceBonus(user: user)
        let total = user.basePrice + bonus
        // 婚礼类型绩效 × 用户婚礼系数
        return total * (shootType == .ceremony ? user.weddingMultiplier : 1.0)
    }
}

// MARK: - 示例数据
extension Order {
    static let preview = Order(
        orderNumber: "CS02420241231B",
        shootDate: "251230-31",
        shootLocation: "冰岛",
        photographer: "包包、w秋天v，x",
        consultant: "朵朵",
        totalCount: 168,
        extraCount: 108,
        hasProduct: true,
        trialDeadline: Calendar.current.date(byAdding: .day, value: 15, to: Date()),
        finalDeadline: Calendar.current.date(byAdding: .day, value: 50, to: Date()),
        weddingDate: "2026年10月5日",
        isRepeatCustomer: false,
        requirements: """
        男生：发型修饰，下颚线清晰，身高适当拉高，面部修饰，皮肤冻红的修饰，衣服褶皱修饰，眼睛适当放大一点点。
        女生：身高适当拉高，脸瘦一些，眼睛放大一点，直角肩，天鹅颈，手臂线条修饰，腋下副乳修饰，背部细节修饰，腰身比例修饰，鞋子穿帮修饰，手指纤细一点，体态要好看，面部修饰，保留肌肤纹理质感，不要修的太假，真实自然感为主。
        """,
        panLink: "https://pan.baidu.com/s/1WqB80Y7kFfzdE2AItA8LxA",
        panCode: "wwa4",
        assignedAt: Date(),
        shootType: .wedding,
        isInGroup: true,
        isUrgent: false
    )
    
    static let previewList: [Order] = [
        preview,
        Order(
            orderNumber: "CS02520250711B",
            shootDate: "2025/8/13",
            shootLocation: "罗马",
            consultant: "云云",
            totalCount: 92,
            finalDeadline: Calendar.current.date(byAdding: .day, value: 10, to: Date()),
            assignedAt: Date(),
            shootType: .ceremony,
            isUrgent: true
        ),
        Order(
            orderNumber: "CS00520250630B",
            shootDate: "25/9/6-7",
            shootLocation: "冰岛",
            consultant: "amy",
            totalCount: 68,
            finalDeadline: Calendar.current.date(byAdding: .day, value: -2, to: Date()),
            assignedAt: Date(),
            isCompleted: true,
            completedAt: Date(),
            shootType: .wedding,
            isComplaint: true
            // 不再自动归档，需要手动点击归档
        )
    ]
}
