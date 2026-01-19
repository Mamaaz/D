import SwiftUI

// MARK: - 通用卡片组件

/// 统一样式的卡片视图
struct TvtCardView<Content: View>: View {
    let content: Content
    var padding: CGFloat
    var hoverable: Bool
    
    @State private var isHovered = false
    
    init(
        padding: CGFloat = TvtDesign.Spacing.lg,
        hoverable: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.padding = padding
        self.hoverable = hoverable
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(backgroundStyle)
            .cornerRadius(TvtDesign.CornerRadius.md)
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
            .scaleEffect(hoverable && isHovered ? 1.01 : 1.0)
            .animation(TvtDesign.Animation.fast, value: isHovered)
            .onHover { hovering in
                if hoverable {
                    isHovered = hovering
                }
            }
    }
    
    private var backgroundStyle: Color {
        if hoverable && isHovered {
            return TvtDesign.Colors.cardBackgroundHover
        }
        return TvtDesign.Colors.cardBackground
    }
    
    private var shadowColor: Color {
        if hoverable && isHovered {
            return TvtDesign.Shadow.md.color
        }
        return TvtDesign.Shadow.sm.color
    }
    
    private var shadowRadius: CGFloat {
        if hoverable && isHovered {
            return TvtDesign.Shadow.md.radius
        }
        return TvtDesign.Shadow.sm.radius
    }
    
    private var shadowY: CGFloat {
        if hoverable && isHovered {
            return TvtDesign.Shadow.md.y
        }
        return TvtDesign.Shadow.sm.y
    }
}

// MARK: - 统计卡片

/// 用于显示统计数据的卡片
struct TvtStatCard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = TvtDesign.Colors.primary
    var subtitle: String? = nil
    var trend: TrendDirection? = nil
    
    enum TrendDirection {
        case up, down, neutral
        
        var icon: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .neutral: return "arrow.right"
            }
        }
        
        var color: Color {
            switch self {
            case .up: return .green
            case .down: return .red
            case .neutral: return .gray
            }
        }
    }
    
    var body: some View {
        TvtCardView(hoverable: true) {
            HStack {
                VStack(alignment: .leading, spacing: TvtDesign.Spacing.xs) {
                    Text(title)
                        .font(TvtDesign.Typography.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: TvtDesign.Spacing.xs) {
                        Text(value)
                            .font(TvtDesign.Typography.title)
                            .foregroundColor(color)
                        
                        if let trend = trend {
                            Image(systemName: trend.icon)
                                .font(.caption)
                                .foregroundColor(trend.color)
                        }
                    }
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(TvtDesign.Typography.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.1))
                    .cornerRadius(TvtDesign.CornerRadius.sm)
            }
        }
    }
}

// MARK: - 预览

#Preview("Cards") {
    VStack(spacing: 20) {
        TvtCardView {
            Text("Basic Card")
                .font(.headline)
        }
        
        TvtCardView(hoverable: true) {
            Text("Hoverable Card")
                .font(.headline)
        }
        
        TvtStatCard(
            title: "待处理订单",
            value: "79",
            icon: "doc.text",
            color: .blue,
            subtitle: "较上月增加 12%",
            trend: .up
        )
        
        TvtStatCard(
            title: "已完成",
            value: "156",
            icon: "checkmark.circle",
            color: .green
        )
    }
    .padding()
    .frame(width: 300)
}
