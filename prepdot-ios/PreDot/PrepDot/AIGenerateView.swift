import SwiftUI
import UniformTypeIdentifiers

struct AIGenerateView: View {
    @Environment(\.dismiss) var dismiss
    var onComplete: (() -> Void)? = nil

    enum InputMode: String, CaseIterable {
        case file  = "上传文件"
        case paste = "粘贴文字"
    }
    @State private var inputMode: InputMode = .paste

    static let detailLabels = ["极简", "简洁", "标准", "详细", "极详"]
    static let detailHints  = [
        "答案极简，不超过20字",
        "答案简洁，不超过50字",
        "答案详细，100字以内",
        "答案详细，可分要点列举，150字以内",
        "答案尽可能详尽，含原理和示例，200字以内",
    ]

    @State private var aiDecideCount: Bool   = true   // 默认让 AI 决定张数
    @State private var cardCount:     Double = 20     // 5–100（手动时）
    @State private var detailLevel:   Double = 2      // 0–4

    @State private var deckTitle       = ""
    @State private var customKey       = ""
    @State private var useCustomKey    = false
    @State private var selectedFiles: [(data: Data, name: String)] = []
    @State private var pastedText      = ""

    @State private var phase: Phase = .input
    @State private var errorMsg      = ""
    @State private var previewDeck: AIPreviewDeck? = nil
    @State private var showFilePicker = false
    @State private var generatingProgress = ""  // 多文件时提示第几个

    enum Phase { case input, generating, preview, importing, done }

    private var isReady: Bool {
        let title = deckTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return false }
        switch inputMode {
        case .file:  return !selectedFiles.isEmpty
        case .paste: return !pastedText.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input:      inputView
                case .generating: generatingView
                case .preview:    previewView
                case .importing:  importingView
                case .done:       doneView
                }
            }
            .navigationTitle("AI 生成卡组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .text,
                                   UTType(filenameExtension: "md")   ?? .text,
                                   UTType(filenameExtension: "docx") ?? .data,
                                   UTType(filenameExtension: "pptx") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            handleFilePick(result)
        }
    }

    // MARK: - 输入页

    private var inputView: some View {
        Form {
            Section {
                TextField("给这份资料起个名字", text: $deckTitle)
            } header: {
                Text("卡组名称")
            } footer: {
                Text("例如：Java 面试准备、操作系统复习")
            }

            Section {
                Picker("输入方式", selection: $inputMode) {
                    ForEach(InputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if inputMode == .file { fileSection } else { pasteSection }

            Section {
                // ── 张数滑块
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("卡片数量")
                            .font(.subheadline).fontWeight(.medium)
                        Spacer()
                        Toggle("自动", isOn: $aiDecideCount)
                            .font(.subheadline)
                            .tint(.indigo)
                            .fixedSize()
                    }
                    if aiDecideCount {
                        Text("AI 将根据内容信息量自动决定生成张数")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(Int(cardCount)) 张")
                                .font(.title3).fontWeight(.bold)
                                .foregroundColor(.indigo)
                            Spacer()
                        }
                        Slider(value: $cardCount, in: 5...100, step: 5)
                            .tint(.indigo)
                        HStack {
                            Text("5 张").font(.caption2).foregroundColor(.secondary)
                            Spacer()
                            Text("100 张").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)

                // ── 详细程度滑块
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("答案详细程度")
                            .font(.subheadline).fontWeight(.medium)
                        Spacer()
                        Text(AIGenerateView.detailLabels[Int(detailLevel)])
                            .font(.title3).fontWeight(.bold)
                            .foregroundColor(.indigo)
                    }
                    Slider(value: $detailLevel, in: 0...4, step: 1)
                        .tint(.indigo)
                    HStack {
                        Text(AIGenerateView.detailLabels.first!).font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        Text(AIGenerateView.detailHints[Int(detailLevel)])
                            .font(.caption2).foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(AIGenerateView.detailLabels.last!).font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } header: { Text("生成强度") }
              footer: { Text("卡片越多、越详细，AI 分析时间越长") }

            Section {
                Toggle("使用我自己的 API Key", isOn: $useCustomKey).tint(.indigo)
                if useCustomKey {
                    SecureField("DeepSeek / Qwen / 豆包 API Key", text: $customKey)
                        .font(.system(.footnote, design: .monospaced))
                } else {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                        Text("使用系统 AI（每日 10 次免费）").font(.subheadline)
                    }
                }
            } header: { Text("AI 设置") }
              footer: {
                Text(useCustomKey ? "填入自己的 Key 享受无限次使用"
                                  : "系统 AI 使用 DeepSeek，免费但有次数限制")
              }

            if !errorMsg.isEmpty {
                Section {
                    Label(errorMsg, systemImage: "exclamationmark.triangle")
                        .foregroundColor(.red).font(.caption)
                }
            }

            Section {
                Button(action: startGenerate) {
                    HStack {
                        Spacer()
                        Label("开始 AI 生成", systemImage: "sparkles").font(.headline)
                        Spacer()
                    }
                }
                .disabled(!isReady)
                .listRowBackground(isReady ? Color.indigo : Color.indigo.opacity(0.3))
                .foregroundColor(.white)
            }
        }
    }

    // MARK: - 文件上传区（多文件）

    private var fileSection: some View {
        Section {
            if selectedFiles.isEmpty {
                Button(action: { showFilePicker = true }) {
                    Label("选择文件（可多选）", systemImage: "doc.badge.plus")
                        .foregroundColor(.indigo)
                }
            } else {
                ForEach(selectedFiles.indices, id: \.self) { i in
                    HStack(spacing: 10) {
                        Image(systemName: fileIcon(selectedFiles[i].name))
                            .foregroundColor(.indigo)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedFiles[i].name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text("\(selectedFiles[i].data.count / 1024) KB")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            selectedFiles.remove(at: i)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
                Button(action: { showFilePicker = true }) {
                    Label("继续添加文件", systemImage: "plus")
                        .font(.subheadline)
                        .foregroundColor(.indigo)
                }
            }
        } header: { Text("上传文件") }
          footer: { Text("支持 PDF、Word(.docx)、PPT(.pptx)、TXT、Markdown，最多同时上传 10 个文件") }
    }

    // MARK: - 粘贴文字区

    private var pasteSection: some View {
        Section {
            TextEditor(text: $pastedText)
                .frame(minHeight: 160)
                .font(.system(.body))
            if !pastedText.isEmpty {
                HStack {
                    Spacer()
                    Text("\(pastedText.count) 字").font(.caption2).foregroundColor(.secondary)
                    Button("清空") { pastedText = "" }.font(.caption2).foregroundColor(.red)
                }
            }
        } header: { Text("粘贴学习内容") }
          footer: { Text("把你的笔记、讲义、知识点直接粘贴在这里，AI 会自动整理成卡片") }
    }

    // MARK: - 生成中

    private var generatingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView().scaleEffect(1.5)
            VStack(spacing: 8) {
                Text("AI 正在分析你的资料…").font(.headline)
                if !generatingProgress.isEmpty {
                    Text(generatingProgress)
                        .font(.subheadline)
                        .foregroundColor(.indigo)
                }
                Text("通常需要 10–30 秒，请稍候")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - 预览（含取消 / 重新生成 / 确认）

    private var previewView: some View {
        Group {
            if let deck = previewDeck {
                List {
                    // 卡组摘要
                    Section("卡组预览") {
                        HStack {
                            Text("名称").foregroundColor(.secondary)
                            Spacer()
                            Text(deck.title).fontWeight(.semibold)
                        }
                        HStack {
                            Text("分类").foregroundColor(.secondary)
                            Spacer()
                            Text(deck.category)
                        }
                        if !deck.description.isEmpty {
                            Text(deck.description)
                                .font(.caption).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("共").foregroundColor(.secondary)
                            Spacer()
                            Text("\(deck.children.flatMap(\.cards).count) 张卡片，\(deck.children.count) 个主题")
                                .fontWeight(.medium)
                        }
                    }

                    // 卡片列表
                    ForEach(deck.children) { child in
                        Section {
                            ForEach(child.cards) { card in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(card.question)
                                        .font(.subheadline).fontWeight(.medium)
                                    Text(card.answer)
                                        .font(.caption).foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                                .padding(.vertical, 2)
                            }
                        } header: {
                            HStack {
                                Image(systemName: "folder.fill").foregroundColor(.indigo)
                                Text(child.title)
                                Spacer()
                                Text("\(child.cards.count) 张").foregroundColor(.secondary)
                            }
                        }
                    }

                    // 操作按钮
                    Section {
                        // 确认导入
                        Button(action: importDeck) {
                            HStack {
                                Spacer()
                                Label("确认导入", systemImage: "tray.and.arrow.down.fill")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .listRowBackground(Color.indigo)
                        .foregroundColor(.white)

                        // 重新生成
                        Button(action: {
                            previewDeck = nil
                            phase = .input
                        }) {
                            HStack {
                                Spacer()
                                Label("重新生成", systemImage: "arrow.clockwise")
                                    .font(.subheadline)
                                Spacer()
                            }
                        }
                        .foregroundColor(.indigo)

                        // 取消
                        Button(action: { dismiss() }) {
                            HStack {
                                Spacer()
                                Text("取消，不导入")
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                                Spacer()
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - 导入中 / 完成

    private var importingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView().scaleEffect(1.5)
            Text("正在保存卡组…").font(.headline)
            Spacer()
        }
    }

    private var doneView: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72)).foregroundColor(.green)
            VStack(spacing: 8) {
                Text("导入成功！").font(.title2).fontWeight(.bold)
                Text("卡组已添加到「我的卡组」").foregroundColor(.secondary)
            }
            Button("完成") { onComplete?(); dismiss() }
                .buttonStyle(.borderedProminent).tint(.indigo)
            Spacer()
        }
    }

    // MARK: - 逻辑

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                if selectedFiles.count >= 10 {
                    errorMsg = "最多同时上传 10 个文件"; break
                }
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url) else { continue }
                let name = url.lastPathComponent
                if !selectedFiles.contains(where: { $0.name == name }) {
                    selectedFiles.append((data: data, name: name))
                }
            }
            if selectedFiles.count < 10 { errorMsg = "" }
        case .failure(let err):
            errorMsg = err.localizedDescription
        }
    }

    private func startGenerate() {
        errorMsg = ""
        generatingProgress = ""
        phase = .generating
        let count      = aiDecideCount ? 0 : Int(cardCount)
        let detailHint = AIGenerateView.detailHints[Int(detailLevel)]
        let key = useCustomKey ? customKey : ""

        Task {
            do {
                var mergedChildren: [AIPreviewChild] = []
                var rootCategory = "综合"
                var rootDescription = ""

                switch inputMode {
                case .file:
                    let total = selectedFiles.count
                    for (i, file) in selectedFiles.enumerated() {
                        if total > 1 {
                            await MainActor.run {
                                generatingProgress = "正在处理第 \(i + 1) / \(total) 个文件：\(file.name)"
                            }
                        }
                        let jsonStr = try await APIService.shared.generateDeckFromFile(
                            fileData: file.data,
                            fileName: file.name,
                            deckTitle: total == 1 ? deckTitle : file.name,
                            customKey: key,
                            cardCount: count,
                            detailHint: detailHint
                        )
                        let decoded = try JSONDecoder().decode(
                            AIPreviewDeck.self,
                            from: jsonStr.data(using: .utf8)!
                        )
                        if i == 0 {
                            rootCategory    = decoded.category
                            rootDescription = decoded.description
                        }
                        mergedChildren.append(contentsOf: decoded.children)
                    }

                case .paste:
                    let data = pastedText.data(using: .utf8)!
                    let jsonStr = try await APIService.shared.generateDeckFromFile(
                        fileData: data,
                        fileName: "input.txt",
                        deckTitle: deckTitle,
                        customKey: key,
                        cardCount: count,
                        detailHint: detailHint
                    )
                    let decoded = try JSONDecoder().decode(
                        AIPreviewDeck.self,
                        from: jsonStr.data(using: .utf8)!
                    )
                    rootCategory    = decoded.category
                    rootDescription = decoded.description
                    mergedChildren  = decoded.children
                }

                let merged = AIPreviewDeck(
                    title: deckTitle,
                    category: rootCategory,
                    description: rootDescription,
                    children: mergedChildren
                )
                await MainActor.run {
                    previewDeck = merged
                    phase = .preview
                }
            } catch {
                await MainActor.run {
                    errorMsg = error.localizedDescription
                    phase = .input
                }
            }
        }
    }

    private func importDeck() {
        guard let deck = previewDeck else { return }
        phase = .importing
        Task {
            do {
                let json    = try JSONEncoder().encode(deck)
                let jsonStr = String(data: json, encoding: .utf8)!
                _ = try await APIService.shared.importDeckJson(jsonStr)
                await MainActor.run { phase = .done }
            } catch {
                await MainActor.run { errorMsg = error.localizedDescription; phase = .preview }
            }
        }
    }

    private func fileIcon(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":         return "doc.richtext.fill"
        case "docx", "doc": return "doc.text.fill"
        case "pptx", "ppt": return "rectangle.stack.fill"
        default:            return "doc.text"
        }
    }
}
