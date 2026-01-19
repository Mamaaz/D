import SwiftUI

// MARK: - 加载状态覆盖层

/// 统一的加载状态覆盖层
struct TvtLoadingOverlay: View {
    let isLoading: Bool
    var message: String? = nil
    
    var body: some View {
        if isLoading {
            ZStack {
                // 背景模糊
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                // 加载指示器
                VStack(spacing: TvtDesign.Spacing.md) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                    
                    if let message = message {
                        Text(message)
                            .font(TvtDesign.Typography.callout)
                            .foregroundColor(.white)
                    }
                }
                .padding(TvtDesign.Spacing.xxl)
                .background(.ultraThinMaterial)
                .cornerRadius(TvtDesign.CornerRadius.lg)
            }
            .transition(.opacity.animation(TvtDesign.Animation.fast))
        }
    }
}

// MARK: - 空状态视图

/// 统一的空状态/无数据视图
struct TvtEmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: TvtDesign.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text(title)
                .font(TvtDesign.Typography.headline)
                .foregroundColor(.secondary)
            
            if let message = message {
                Text(message)
                    .font(TvtDesign.Typography.subheadline)
                    .foregroundColor(.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .tvtGradientButton()
                }
                .buttonStyle(.plain)
                .padding(.top, TvtDesign.Spacing.sm)
            }
        }
        .padding(TvtDesign.Spacing.xxl)
    }
}

// MARK: - 错误状态视图

/// 统一的错误状态视图
struct TvtErrorState: View {
    let error: String
    var retryAction: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: TvtDesign.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(TvtDesign.Colors.warning)
            
            Text("出错了")
                .font(TvtDesign.Typography.headline)
            
            Text(error)
                .font(TvtDesign.Typography.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let retryAction = retryAction {
                Button(action: retryAction) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("重试")
                    }
                    .tvtGradientButton()
                }
                .buttonStyle(.plain)
                .padding(.top, TvtDesign.Spacing.sm)
            }
        }
        .padding(TvtDesign.Spacing.xxl)
    }
}

// MARK: - View 修饰符

extension View {
    /// 添加加载覆盖层
    func tvtLoading(_ isLoading: Bool, message: String? = nil) -> some View {
        ZStack {
            self
            TvtLoadingOverlay(isLoading: isLoading, message: message)
        }
    }
}

// MARK: - 预览

#Preview("Loading & States") {
    VStack(spacing: 40) {
        // 空状态
        TvtEmptyState(
            icon: "doc.text",
            title: "暂无订单",
            message: "还没有任何订单数据",
            actionTitle: "新建订单"
        ) {
            print("Action tapped")
        }
        
        // 错误状态
        TvtErrorState(error: "网络连接失败，请检查网络设置") {
            print("Retry tapped")
        }
    }
    .frame(width: 400, height: 600)
}

#Preview("Loading Overlay") {
    Text("内容区域")
        .frame(width: 300, height: 300)
        .tvtLoading(true, message: "加载中...")
}
