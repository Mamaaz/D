import SwiftUI

// MARK: - 动画工具

/// 列表项出现动画修饰符
struct ListItemAnimationModifier: ViewModifier {
    let index: Int
    let isVisible: Bool
    let baseDelay: Double
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .animation(
                .easeOut(duration: 0.35).delay(Double(index) * baseDelay),
                value: isVisible
            )
    }
}

/// 淡入缩放动画修饰符
struct FadeScaleAnimationModifier: ViewModifier {
    let isVisible: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.9)
            .animation(TvtDesign.Animation.spring, value: isVisible)
    }
}

/// 滑入动画修饰符
struct SlideInAnimationModifier: ViewModifier {
    enum Direction {
        case leading, trailing, top, bottom
        
        var offset: CGSize {
            switch self {
            case .leading: return CGSize(width: -30, height: 0)
            case .trailing: return CGSize(width: 30, height: 0)
            case .top: return CGSize(width: 0, height: -30)
            case .bottom: return CGSize(width: 0, height: 30)
            }
        }
    }
    
    let isVisible: Bool
    let direction: Direction
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(isVisible ? .zero : direction.offset)
            .animation(TvtDesign.Animation.spring, value: isVisible)
    }
}

// MARK: - View 扩展

extension View {
    /// 列表项出现动画
    func listItemAnimation(index: Int, isVisible: Bool, baseDelay: Double = 0.03) -> some View {
        modifier(ListItemAnimationModifier(index: index, isVisible: isVisible, baseDelay: baseDelay))
    }
    
    /// 淡入缩放动画
    func fadeScaleAnimation(isVisible: Bool) -> some View {
        modifier(FadeScaleAnimationModifier(isVisible: isVisible))
    }
    
    /// 滑入动画
    func slideInAnimation(isVisible: Bool, from direction: SlideInAnimationModifier.Direction = .bottom) -> some View {
        modifier(SlideInAnimationModifier(isVisible: isVisible, direction: direction))
    }
    
    /// 按钮按下效果
    func pressEffect(_ isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
    
    /// 悬浮效果
    func hoverEffect(_ isHovered: Bool, scale: CGFloat = 1.02) -> some View {
        self
            .scaleEffect(isHovered ? scale : 1)
            .animation(TvtDesign.Animation.fast, value: isHovered)
    }
    
    /// 加载时脉冲动画
    func pulseAnimation(isAnimating: Bool) -> some View {
        self
            .opacity(isAnimating ? 0.6 : 1)
            .animation(
                isAnimating ?
                    Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) :
                    .default,
                value: isAnimating
            )
    }
}

// MARK: - 过渡效果

extension AnyTransition {
    /// 滑入淡出过渡
    static var slideAndFade: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
    
    /// 缩放淡入过渡
    static var scaleAndFade: AnyTransition {
        .scale(scale: 0.9).combined(with: .opacity)
    }
    
    /// 从底部弹出过渡
    static var slideUp: AnyTransition {
        .move(edge: .bottom).combined(with: .opacity)
    }
}

// MARK: - 预览

#Preview("Animations") {
    struct DemoView: View {
        @State private var isVisible = false
        @State private var items = ["Item 1", "Item 2", "Item 3", "Item 4", "Item 5"]
        
        var body: some View {
            VStack(spacing: 20) {
                Button("Toggle Visibility") {
                    isVisible.toggle()
                }
                
                VStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        Text(item)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                            .listItemAnimation(index: index, isVisible: isVisible)
                    }
                }
                .padding()
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isVisible = true
                }
            }
        }
    }
    
    return DemoView()
        .frame(width: 300, height: 400)
}
