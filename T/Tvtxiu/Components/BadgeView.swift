import SwiftUI

// MARK: - 徽章组件

/// 通用徽章/标签视图
struct TvtBadge: View {
    let text: String
    var color: Color = TvtDesign.Colors.primary
    var style: BadgeStyle = .filled
    var size: BadgeSize = .medium
    
    enum BadgeStyle {
        case filled
        case outlined
        case subtle
    }
    
    enum BadgeSize {
        case small
        case medium
        case large
        
        var font: Font {
            switch self {
            case .small: return TvtDesign.Typography.caption2
            case .medium: return TvtDesign.Typography.caption
            case .large: return TvtDesign.Typography.subheadline
            }
        }
        
        var horizontalPadding: CGFloat {
            switch self {
            case .small: return TvtDesign.Spacing.xs
            case .medium: return TvtDesign.Spacing.sm
            case .large: return TvtDesign.Spacing.md
            }
        }
        
        var verticalPadding: CGFloat {
            switch self {
            case .small: return TvtDesign.Spacing.xxs
            case .medium: return TvtDesign.Spacing.xs
            case .large: return TvtDesign.Spacing.sm
            }
        }
    }
    
    var body: some View {
        Text(text)
            .font(size.font)
            .fontWeight(.medium)
            .foregroundColor(foregroundColor)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(backgroundColor)
            .cornerRadius(TvtDesign.CornerRadius.xs)
            .overlay(
                RoundedRectangle(cornerRadius: TvtDesign.CornerRadius.xs)
                    .stroke(borderColor, lineWidth: style == .outlined ? 1 : 0)
            )
    }
    
    private var foregroundColor: Color {
        switch style {
        case .filled:
            return .white
        case .outlined, .subtle:
            return color
        }
    }
    
    private var backgroundColor: Color {
        switch style {
        case .filled:
            return color
        case .outlined:
            return .clear
        case .subtle:
            return color.opacity(0.1)
        }
    }
    
    private var borderColor: Color {
        style == .outlined ? color : .clear
    }
}

// MARK: - 订单状态徽章

/// 订单状态专用徽章
struct TvtOrderStatusBadge: View {
    let status: OrderStatus
    
    enum OrderStatus {
        case pending
        case completed
        case archived
        case urgent
        case complaint
        case overdue
        case inGroup
        
        var text: String {
            switch self {
            case .pending: return "待处理"
            case .completed: return "已完成"
            case .archived: return "已归档"
            case .urgent: return "加急"
            case .complaint: return "投诉"
            case .overdue: return "逾期"
            case .inGroup: return "进群"
            }
        }
        
        var color: Color {
            switch self {
            case .pending: return TvtDesign.Colors.pending
            case .completed: return TvtDesign.Colors.completed
            case .archived: return TvtDesign.Colors.archived
            case .urgent: return TvtDesign.Colors.urgent
            case .complaint: return TvtDesign.Colors.complaint
            case .overdue: return TvtDesign.Colors.overdue
            case .inGroup: return .purple
            }
        }
        
        var icon: String? {
            switch self {
            case .urgent: return "bolt.fill"
            case .complaint: return "flag.fill"
            case .overdue: return "exclamationmark.circle.fill"
            case .inGroup: return "person.2.fill"
            default: return nil
            }
        }
    }
    
    var body: some View {
        HStack(spacing: TvtDesign.Spacing.xxs) {
            if let icon = status.icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(status.text)
        }
        .font(TvtDesign.Typography.caption)
        .fontWeight(.medium)
        .foregroundColor(.white)
        .padding(.horizontal, TvtDesign.Spacing.sm)
        .padding(.vertical, TvtDesign.Spacing.xs)
        .background(status.color)
        .cornerRadius(TvtDesign.CornerRadius.xs)
    }
}

// MARK: - 数量徽章

/// 显示数量的小徽章（如未读消息数）
struct TvtCountBadge: View {
    let count: Int
    var color: Color = TvtDesign.Colors.error
    var maxDisplay: Int = 99
    
    var body: some View {
        if count > 0 {
            Text(count > maxDisplay ? "\(maxDisplay)+" : "\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color)
                .cornerRadius(TvtDesign.CornerRadius.full)
        }
    }
}

// MARK: - 预览

#Preview("Badges") {
    VStack(spacing: 20) {
        // 通用徽章样式
        HStack(spacing: 8) {
            TvtBadge(text: "Filled", color: .blue, style: .filled)
            TvtBadge(text: "Outlined", color: .blue, style: .outlined)
            TvtBadge(text: "Subtle", color: .blue, style: .subtle)
        }
        
        // 徽章尺寸
        HStack(spacing: 8) {
            TvtBadge(text: "Small", size: .small)
            TvtBadge(text: "Medium", size: .medium)
            TvtBadge(text: "Large", size: .large)
        }
        
        // 订单状态徽章
        HStack(spacing: 8) {
            TvtOrderStatusBadge(status: .pending)
            TvtOrderStatusBadge(status: .completed)
            TvtOrderStatusBadge(status: .urgent)
            TvtOrderStatusBadge(status: .complaint)
        }
        
        // 数量徽章
        HStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.title2)
                TvtCountBadge(count: 5)
                    .offset(x: 8, y: -8)
            }
            
            ZStack(alignment: .topTrailing) {
                Image(systemName: "envelope")
                    .font(.title2)
                TvtCountBadge(count: 128)
                    .offset(x: 12, y: -8)
            }
        }
    }
    .padding()
}
