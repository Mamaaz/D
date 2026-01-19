import SwiftUI
import UniformTypeIdentifiers

// MARK: - 拍摄订单导入设置

/// 拍摄订单导入配置区域（仅管理员）
struct TencentDocsSyncSection: View {
    @EnvironmentObject var settingsManager: SettingsManager
    
    @State private var isUploading: Bool = false
    @State private var syncStatus: SyncStatus?
    @State private var uploadResult: UploadResult?
    @State private var errorMessage: String?
    @State private var showFilePicker: Bool = false
    @State private var selectedYears: Set<Int> = [2025, 2026]
    
    private let availableYears = [2024, 2025, 2026, 2027]
    
    var body: some View {
        Section("拍摄订单导入") {
            // 年份选择
            VStack(alignment: .leading, spacing: 8) {
                Text("选择导入年份")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(availableYears, id: \.self) { year in
                        Button {
                            if selectedYears.contains(year) {
                                selectedYears.remove(year)
                            } else {
                                selectedYears.insert(year)
                            }
                        } label: {
                            Text("\(year)")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedYears.contains(year) ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(selectedYears.contains(year) ? .white : .primary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
            
            // 上传按钮
            Button {
                showFilePicker = true
            } label: {
                HStack {
                    if isUploading {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text("选择 Excel 文件上传")
                }
            }
            .disabled(isUploading || selectedYears.isEmpty)
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [UTType(filenameExtension: "xlsx")!],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            
            Divider()
            
            // 同步状态
            if let status = syncStatus {
                syncStatusView(status)
            }
            
            // 上传结果
            if let result = uploadResult {
                uploadResultView(result)
            }
            
            // 错误提示
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Text("从腾讯文档导出 Excel，上传后自动解析和导入")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onAppear {
            loadSyncStatus()
        }
    }
    
    // MARK: - 同步状态视图
    
    @ViewBuilder
    private func syncStatusView(_ status: SyncStatus) -> some View {
        HStack {
            Text("已导入订单")
            Spacer()
            Text("\(status.totalSynced) 条")
                .foregroundColor(.secondary)
        }
        
        if let lastSync = status.lastSyncAt {
            HStack {
                Text("上次导入")
                Spacer()
                Text(formatRelativeTime(lastSync))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - 上传结果视图
    
    @ViewBuilder
    private func uploadResultView(_ result: UploadResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("导入完成")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.green)
            
            HStack(spacing: 16) {
                Label("\(result.imported) 新增", systemImage: "plus.circle")
                Label("\(result.updated) 更新", systemImage: "arrow.triangle.2.circlepath")
                if result.skipped > 0 {
                    Label("\(result.skipped) 跳过", systemImage: "xmark.circle")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - 方法
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            uploadFile(fileURL)
        case .failure(let error):
            errorMessage = "选择文件失败: \(error.localizedDescription)"
        }
    }
    
    private func uploadFile(_ fileURL: URL) {
        isUploading = true
        errorMessage = nil
        uploadResult = nil
        
        Task {
            do {
                // 开始访问安全范围资源
                guard fileURL.startAccessingSecurityScopedResource() else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法访问文件"])
                }
                defer { fileURL.stopAccessingSecurityScopedResource() }
                
                // 读取文件数据
                let fileData = try Data(contentsOf: fileURL)
                
                // 构建年份参数
                let yearsParam = selectedYears.sorted().map { String($0) }.joined(separator: ",")
                
                // 上传文件
                let result: UploadResult = try await uploadExcelFile(fileData, filename: fileURL.lastPathComponent, years: yearsParam)
                
                await MainActor.run {
                    self.uploadResult = result
                    self.isUploading = false
                    loadSyncStatus()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "上传失败: \(error.localizedDescription)"
                    self.isUploading = false
                }
            }
        }
    }
    
    private func uploadExcelFile(_ data: Data, filename: String, years: String) async throws -> UploadResult {
        let baseURL = APIService.shared.currentBaseURL
        guard let url = URL(string: "\(baseURL)/api/sync/upload?years=\(years)") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 URL"])
        }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // 添加认证头
        if let token = APIService.shared.currentAuthToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // 构建 multipart body
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的响应"])
        }
        
        if httpResponse.statusCode != 200 {
            if let errorDict = try? JSONDecoder().decode([String: String].self, from: responseData),
               let errorMsg = errorDict["error"] {
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
            throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "上传失败 (\(httpResponse.statusCode))"])
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(UploadResult.self, from: responseData)
    }
    
    private func loadSyncStatus() {
        Task {
            do {
                let status: SyncStatus = try await APIService.shared.request(
                    endpoint: "/api/sync/status"
                )
                await MainActor.run {
                    self.syncStatus = status
                }
            } catch {
                // 忽略加载状态错误
            }
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 辅助类型

struct SyncStatus: Codable {
    let lastSyncAt: Date?
    let totalSynced: Int
    let lastError: String?
    let isRunning: Bool
    let nextSyncAt: Date?
}

struct UploadResult: Codable {
    let message: String
    let imported: Int
    let updated: Int
    let skipped: Int
    let total: Int
    let valid: Int
    let byYear: [String: Int]?
}

struct EmptyResponse: Codable {
    let message: String?
}

// MARK: - 预览

#Preview {
    Form {
        TencentDocsSyncSection()
    }
    .environmentObject(SettingsManager())
    .frame(width: 500)
}
