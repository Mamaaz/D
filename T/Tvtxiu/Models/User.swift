import Foundation

// MARK: - 用户角色

/// 用户角色
enum UserRole: String, Codable, CaseIterable {
    case admin = "admin"           // 主管理员
    case subAdmin = "sub_admin"    // 副管理员
    case staff = "staff"           // 后期人员
    case outsource = "outsource"   // 外包人员
    
    var displayName: String {
        switch self {
        case .admin: return "主管理员"
        case .subAdmin: return "副管理员"
        case .staff: return "后期人员"
        case .outsource: return "外包"
        }
    }
    
    /// 是否有管理权限（录入、分配、编辑）
    var hasAdminPrivilege: Bool {
        self == .admin || self == .subAdmin
    }
    
    /// 是否为普通员工（后期或外包，只能看自己订单）
    var isRegularStaff: Bool {
        self == .staff || self == .outsource
    }
}

// MARK: - 职级

/// 后期人员职级
enum StaffLevel: String, Codable, CaseIterable {
    case junior = "初级"
    case intermediate = "中级"
    case senior = "高级"
    case expert = "外援"
    
    var displayName: String {
        return self.rawValue
    }
    
    /// 默认基础绩效 (元/张)
    var defaultBaseRate: Double {
        switch self {
        case .junior: return 6.0
        case .intermediate: return 8.0
        case .senior: return 10.0
        case .expert: return 15.0
        }
    }
}

// MARK: - 用户模型

/// 用户模型
struct User: Identifiable, Codable, Hashable {
    let id: UUID
    var username: String      // 唯一名称（登录 + 显示）
    var nickname: String      // 兼容旧数据，实际不再使用
    var realName: String      // 兼容旧数据，实际不再使用
    var role: UserRole
    var createdAt: Date
    var updatedAt: Date
    
    // 人员状态（用于离职人员管理）
    var isHidden: Bool        // 隐藏人员（离职）
    var leftAt: Date?         // 离职时间
    
    // 绩效配置（每人独立配置）
    var basePrice: Double           // 基础单价 (元/张)
    var groupBonus: Double          // 进群加项 (元)，0=不适用
    var urgentBonus: Double         // 加急加项 (元)，0=不适用
    var complaintBonus: Double      // 投诉加项 (元)
    var weddingMultiplier: Double   // 婚礼系数，默认0.8
    
    // 兼容旧数据（已废弃，不再使用）
    var level: StaffLevel?
    var basePerformanceRate: Double?
    
    // 日历颜色 (存储 RGB 值)
    var calendarColorRed: Double
    var calendarColorGreen: Double
    var calendarColorBlue: Double
    
    // 头像 URL (相对路径)
    var avatarUrl: String?
    
    /// 显示名称（统一使用 username）
    var displayName: String { username }
    
    /// 绩效显示名称（统一使用 username）
    var performanceName: String { username }
    
    /// 是否为在职人员（未隐藏）
    var isActive: Bool { !isHidden }
    
    init(
        id: UUID = UUID(),
        username: String,
        nickname: String = "",
        realName: String = "",
        role: UserRole,
        isHidden: Bool = false,
        leftAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        basePrice: Double = 8.0,
        groupBonus: Double = 2.0,
        urgentBonus: Double = 5.0,
        complaintBonus: Double = 8.0,
        weddingMultiplier: Double = 0.8,
        level: StaffLevel? = nil,
        basePerformanceRate: Double? = nil,
        calendarColorRed: Double = 0.2,
        calendarColorGreen: Double = 0.5,
        calendarColorBlue: Double = 0.9,
        avatarUrl: String? = nil
    ) {
        self.id = id
        self.username = username
        self.nickname = nickname
        self.realName = realName
        self.role = role
        self.isHidden = isHidden
        self.leftAt = leftAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.basePrice = basePrice
        self.groupBonus = groupBonus
        self.urgentBonus = urgentBonus
        self.complaintBonus = complaintBonus
        self.weddingMultiplier = weddingMultiplier
        self.level = level
        self.basePerformanceRate = basePerformanceRate
        self.calendarColorRed = calendarColorRed
        self.calendarColorGreen = calendarColorGreen
        self.calendarColorBlue = calendarColorBlue
        self.avatarUrl = avatarUrl
    }
}

// MARK: - 月度绩效配置

/// 月度绩效配置 (每人每月)
struct MonthlyPerformanceConfig: Identifiable, Codable {
    let id: UUID
    var userId: UUID              // 人员 ID
    var month: String             // 月份 (yyyy-MM)
    var salarySocialTotal: Double // 工资社保合计
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        month: String,
        salarySocialTotal: Double = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.month = month
        self.salarySocialTotal = salarySocialTotal
        self.updatedAt = updatedAt
    }
}

// MARK: - 示例数据
extension User {
    static let preview = User(
        username: "peizi",
        nickname: "小培",
        realName: "张培滋",
        role: .staff,
        basePrice: 8.0
    )
    
    static let adminPreview = User(
        username: "admin",
        nickname: "管理员",
        realName: "",
        role: .admin
    )
    
    static let outsourcePreview = User(
        username: "waibao_a",
        nickname: "外包A",
        role: .outsource,
        basePrice: 15.0,
        groupBonus: 0,
        urgentBonus: 0,
        complaintBonus: 5.0
    )
    
    static let staffList: [User] = [
        User(username: "linghumin", nickname: "敏敏", realName: "令狐敏", role: .staff, basePrice: 10.0,
             calendarColorRed: 0.2, calendarColorGreen: 0.6, calendarColorBlue: 0.9),
        User(username: "lijie", nickname: "小洁", realName: "李洁", role: .staff, basePrice: 8.0,
             calendarColorRed: 0.9, calendarColorGreen: 0.3, calendarColorBlue: 0.5),
        User(username: "linhualong", nickname: "龙哥", realName: "林怀龙", role: .staff, basePrice: 8.0,
             calendarColorRed: 0.3, calendarColorGreen: 0.8, calendarColorBlue: 0.4),
        User(username: "yuchenchen", nickname: "晨晨", realName: "余晨晨", role: .staff, basePrice: 8.0,
             calendarColorRed: 0.9, calendarColorGreen: 0.6, calendarColorBlue: 0.2),
        User(username: "wanghaonan", nickname: "浩南", realName: "王浩南", role: .staff, basePrice: 6.0,
             calendarColorRed: 0.6, calendarColorGreen: 0.3, calendarColorBlue: 0.9),
    ]
}

