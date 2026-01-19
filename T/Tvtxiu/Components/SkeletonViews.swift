import SwiftUI

// MARK: - 骨架屏订单行

/// 订单列表加载时显示的骨架屏效果
struct SkeletonOrderRow: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 16) {
            // 左侧状态条
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 4)
                .cornerRadius(2)
            
            VStack(alignment: .leading, spacing: 10) {
                // 订单编号占位
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 200, height: 16)
                
                // 拍摄信息占位
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 12)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 12)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 100, height: 12)
                }
                
                // 标签占位
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 50, height: 20)
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 70, height: 20)
                }
            }
            
            Spacer()
            
            // 右侧信息占位
            VStack(alignment: .trailing, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 14)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 60, height: 12)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(
            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - 骨架屏列表

/// 用于订单列表的骨架屏加载效果
struct SkeletonOrderList: View {
    let count: Int
    
    init(count: Int = 5) {
        self.count = count
    }
    
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonOrderRow()
            }
        }
        .padding()
    }
}

// MARK: - 通用骨架屏组件

/// 可复用的骨架屏块
struct SkeletonBlock: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    
    @State private var isAnimating = false
    
    init(width: CGFloat? = nil, height: CGFloat = 16, cornerRadius: CGFloat = 4) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.25))
            .frame(width: width, height: height)
            .opacity(isAnimating ? 0.5 : 1.0)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - 骨架屏统计卡片

struct SkeletonStatCard: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 12) {
            SkeletonBlock(width: 40, height: 24, cornerRadius: 4)
            SkeletonBlock(width: 60, height: 12, cornerRadius: 4)
        }
        .padding()
        .frame(width: 100)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - 预览

#Preview("骨架屏订单行") {
    VStack(spacing: 12) {
        SkeletonOrderRow()
        SkeletonOrderRow()
        SkeletonOrderRow()
    }
    .padding()
}

#Preview("骨架屏列表") {
    ScrollView {
        SkeletonOrderList(count: 5)
    }
}
