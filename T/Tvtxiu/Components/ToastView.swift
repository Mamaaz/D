import SwiftUI

// MARK: - Toast 消息类型

enum ToastType {
    case success
    case error
    case warning
    case info
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}

// MARK: - Toast 消息模型

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let title: String
    let message: String?
    let duration: TimeInterval
    
    init(type: ToastType, title: String, message: String? = nil, duration: TimeInterval = 3.0) {
        self.type = type
        self.title = title
        self.message = message
        self.duration = duration
    }
    
    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Toast 管理器

@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var currentToast: ToastMessage?
    private var dismissTask: Task<Void, Never>?
    
    private init() {}
    
    func show(_ toast: ToastMessage) {
        dismissTask?.cancel()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentToast = toast
        }
        
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            if !Task.isCancelled {
                await dismiss()
            }
        }
    }
    
    func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            currentToast = nil
        }
    }
    
    // 便捷方法
    func success(_ title: String, message: String? = nil) {
        show(ToastMessage(type: .success, title: title, message: message))
    }
    
    func error(_ title: String, message: String? = nil) {
        show(ToastMessage(type: .error, title: title, message: message, duration: 5.0))
    }
    
    func warning(_ title: String, message: String? = nil) {
        show(ToastMessage(type: .warning, title: title, message: message))
    }
    
    func info(_ title: String, message: String? = nil) {
        show(ToastMessage(type: .info, title: title, message: message))
    }
}

// MARK: - Toast 视图

struct ToastView: View {
    let toast: ToastMessage
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.type.icon)
                .font(.system(size: 20))
                .foregroundColor(toast.type.color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if let message = toast.message {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(toast.type.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Toast 容器（添加到根视图）

struct ToastContainer: ViewModifier {
    @ObservedObject var toastManager = ToastManager.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            VStack {
                if let toast = toastManager.currentToast {
                    ToastView(toast: toast) {
                        toastManager.dismiss()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toastManager.currentToast)
        }
    }
}

extension View {
    func withToast() -> some View {
        modifier(ToastContainer())
    }
}

#Preview {
    VStack(spacing: 20) {
        ToastView(toast: ToastMessage(type: .success, title: "操作成功", message: "订单已保存")) {}
        ToastView(toast: ToastMessage(type: .error, title: "操作失败", message: "网络连接错误")) {}
        ToastView(toast: ToastMessage(type: .warning, title: "警告", message: "数据可能不完整")) {}
        ToastView(toast: ToastMessage(type: .info, title: "提示", message: "正在加载...")) {}
    }
    .padding()
    .frame(width: 400)
}
