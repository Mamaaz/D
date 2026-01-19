import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var rememberPassword: Bool = false
    
    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.15, green: 0.15, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Logo 区域
                VStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .shadow(color: .blue.opacity(0.5), radius: 20)
                    
                    Text("TVT")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("TVT后期协作系统")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(.top, 60)
                
                // 登录表单
                VStack(spacing: 20) {
                    // 用户名输入
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                            .frame(width: 24)
                        
                        TextField("用户名", text: $username)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            #if os(macOS)
                            .textContentType(.username)
                            #endif
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    
                    // 密码输入
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.gray)
                            .frame(width: 24)
                        
                        if isPasswordVisible {
                            TextField("密码", text: $password)
                                .textFieldStyle(.plain)
                                .foregroundColor(.white)
                        } else {
                            SecureField("密码", text: $password)
                                .textFieldStyle(.plain)
                                .foregroundColor(.white)
                        }
                        
                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    
                    // 记住密码复选框
                    HStack {
                        Toggle(isOn: $rememberPassword) {
                            Text("记住密码")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .toggleStyle(.checkbox)
                        
                        Spacer()
                    }
                    
                    // 错误提示
                    if let error = authManager.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(error)
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                    
                    // 登录按钮
                    Button {
                        Task {
                            await authManager.login(username: username, password: password)
                            // 登录成功后保存或清除凭据
                            if authManager.isAuthenticated {
                                if rememberPassword {
                                    _ = KeychainManager.save(key: KeychainManager.savedUsernameKey, value: username)
                                    _ = KeychainManager.save(key: KeychainManager.savedPasswordKey, value: password)
                                    UserDefaults.standard.set(true, forKey: "rememberPassword")
                                } else {
                                    _ = KeychainManager.delete(key: KeychainManager.savedUsernameKey)
                                    _ = KeychainManager.delete(key: KeychainManager.savedPasswordKey)
                                    UserDefaults.standard.set(false, forKey: "rememberPassword")
                                }
                            }
                        }
                    } label: {
                        HStack {
                            if authManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                            } else {
                                Text("登 录")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(username.isEmpty || password.isEmpty || authManager.isLoading)
                    .opacity(username.isEmpty || password.isEmpty ? 0.6 : 1)
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: 360)
                
                Spacer()
                
                // 底部版本号
                Text("v1.0.0")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.5))
                    .padding(.bottom, 40)
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
        .onAppear {
            // 加载保存的凭据
            rememberPassword = UserDefaults.standard.bool(forKey: "rememberPassword")
            if rememberPassword {
                if let savedUsername = KeychainManager.load(key: KeychainManager.savedUsernameKey) {
                    username = savedUsername
                }
                if let savedPassword = KeychainManager.load(key: KeychainManager.savedPasswordKey) {
                    password = savedPassword
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}

