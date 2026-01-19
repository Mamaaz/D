import SwiftUI

// MARK: - Tvtxiu 设计系统

/// 统一的设计系统，确保整个应用视觉一致性
enum TvtDesign {
    
    // MARK: - 颜色
    
    enum Colors {
        // 主色调
        static let primary = Color.blue
        static let secondary = Color.purple
        static let accent = Color.orange
        
        // 状态色
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue
        
        // 背景色（深色模式适配）
        static let background = Color(NSColor.windowBackgroundColor)
        static let secondaryBackground = Color(NSColor.controlBackgroundColor)
        static let tertiaryBackground = Color.gray.opacity(0.1)
        
        // 卡片背景（深色模式优化）
        static let cardBackground = Color(NSColor.controlBackgroundColor)
        static let cardBackgroundHover = Color.gray.opacity(0.15)
        
        // 文字色
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.gray
        
        // 订单状态色
        static let pending = Color.blue
        static let completed = Color.green
        static let archived = Color.gray
        static let urgent = Color.orange
        static let complaint = Color.red
        static let overdue = Color.red.opacity(0.8)
        
        // 渐变
        static let primaryGradient = LinearGradient(
            colors: [.blue, .purple],
            startPoint: .leading,
            endPoint: .trailing
        )
        
        static let successGradient = LinearGradient(
            colors: [.green, .mint],
            startPoint: .leading,
            endPoint: .trailing
        )
        
        static let warningGradient = LinearGradient(
            colors: [.orange, .yellow],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // MARK: - 间距
    
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }
    
    // MARK: - 圆角
    
    enum CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let full: CGFloat = 999
    }
    
    // MARK: - 阴影
    
    enum Shadow {
        static let sm = ShadowStyle(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        static let md = ShadowStyle(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        static let lg = ShadowStyle(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
        
        struct ShadowStyle {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }
    
    // MARK: - 字体
    
    enum Typography {
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title.weight(.semibold)
        static let title2 = Font.title2.weight(.semibold)
        static let title3 = Font.title3.weight(.medium)
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let caption2 = Font.caption2
    }
    
    // MARK: - 动画
    
    enum Animation {
        static let fast = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let normal = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let spring = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.7)
        static let bounce = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.6)
        
        // 列表项出现动画
        static func staggered(index: Int, baseDelay: Double = 0.03) -> SwiftUI.Animation {
            .easeOut(duration: 0.3).delay(Double(index) * baseDelay)
        }
    }
}

// MARK: - View 扩展

extension View {
    /// 应用标准卡片样式
    func tvtCard(padding: CGFloat = TvtDesign.Spacing.lg) -> some View {
        self
            .padding(padding)
            .background(TvtDesign.Colors.cardBackground)
            .cornerRadius(TvtDesign.CornerRadius.md)
            .shadow(
                color: TvtDesign.Shadow.sm.color,
                radius: TvtDesign.Shadow.sm.radius,
                x: TvtDesign.Shadow.sm.x,
                y: TvtDesign.Shadow.sm.y
            )
    }
    
    /// 应用标准卡片样式（带 hover 效果）
    func tvtCardHoverable(isHovered: Bool, padding: CGFloat = TvtDesign.Spacing.lg) -> some View {
        self
            .padding(padding)
            .background(isHovered ? TvtDesign.Colors.cardBackgroundHover : TvtDesign.Colors.cardBackground)
            .cornerRadius(TvtDesign.CornerRadius.md)
            .shadow(
                color: isHovered ? TvtDesign.Shadow.md.color : TvtDesign.Shadow.sm.color,
                radius: isHovered ? TvtDesign.Shadow.md.radius : TvtDesign.Shadow.sm.radius,
                x: 0,
                y: isHovered ? TvtDesign.Shadow.md.y : TvtDesign.Shadow.sm.y
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(TvtDesign.Animation.fast, value: isHovered)
    }
    
    /// 应用渐变背景按钮样式
    @ViewBuilder
    func tvtGradientButton(disabled: Bool = false) -> some View {
        self
            .padding(.horizontal, TvtDesign.Spacing.lg)
            .padding(.vertical, TvtDesign.Spacing.md)
            .background(
                Group {
                    if disabled {
                        Color.gray
                    } else {
                        TvtDesign.Colors.primaryGradient
                    }
                }
            )
            .foregroundColor(.white)
            .cornerRadius(TvtDesign.CornerRadius.md)
            .opacity(disabled ? 0.6 : 1)
    }
    
    /// 列表项出现动画
    func tvtListItemAnimation(index: Int, isVisible: Bool) -> some View {
        self
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .animation(TvtDesign.Animation.staggered(index: index), value: isVisible)
    }
}

// MARK: - 预览

#Preview("Design System") {
    VStack(spacing: 20) {
        Text("Tvtxiu Design System")
            .font(TvtDesign.Typography.largeTitle)
        
        HStack(spacing: 16) {
            Circle().fill(TvtDesign.Colors.primary).frame(width: 40, height: 40)
            Circle().fill(TvtDesign.Colors.secondary).frame(width: 40, height: 40)
            Circle().fill(TvtDesign.Colors.success).frame(width: 40, height: 40)
            Circle().fill(TvtDesign.Colors.warning).frame(width: 40, height: 40)
            Circle().fill(TvtDesign.Colors.error).frame(width: 40, height: 40)
        }
        
        Text("示例卡片")
            .font(TvtDesign.Typography.headline)
            .tvtCard()
        
        Button("渐变按钮") {}
            .tvtGradientButton()
    }
    .padding()
    .frame(width: 400)
}
