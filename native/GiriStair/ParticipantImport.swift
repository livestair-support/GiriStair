import SwiftUI
import Vision

enum GiriParticipantReadError: LocalizedError {
    case unreadable
    case noText
    var errorDescription: String? {
        switch self {
        case .unreadable: return "画像を読み込めませんでした。別の画像を選んでください。"
        case .noText: return "画像から文字を読み取れませんでした。文字が鮮明な画像を選んでください。"
        }
    }
}

enum GiriParticipantOCR {
    static func recognize(_ data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(data: data, options: [:])
            try handler.perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GiriParticipantReadError.noText }
            return text
        }.value
    }
}

struct GiriParticipantImport: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: String
    @State private var names: [String] = []
    @State private var previewing = false
    let onAdd: ([String]) -> Void

    init(source: String = "", onAdd: @escaping ([String]) -> Void) {
        _source = State(initialValue: source)
        self.onAdd = onAdd
    }

    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: previewing ? "名前を確認" : "参加者を読み込む", systemImage: "text.viewfinder", accentColor: AppSectionAccent.artist)
                    .listRowSeparator(.hidden)
                if previewing {
                    ForEach(names.indices, id: \.self) { index in
                        HStack {
                            TextField("参加者名", text: $names[index])
                            Button(role: .destructive) { names.remove(at: index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }.listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                    }
                    Button { names.append("") } label: { Label("名前を追加", systemImage: "plus.circle") }
                    Button("文章に戻る") { previewing = false }
                } else {
                    Text("ツイプラ・noteなどの参加者一覧を貼り付けてください。1行に1人、または「、」区切りで読み込みます。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    TextEditor(text: $source).frame(minHeight: 220).scrollContentBackground(.hidden)
                    Button("名前を確認") {
                        names = giriParseParticipantNames(source)
                        previewing = true
                    }.disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }
        .appEditorFormStyle()
        .navigationTitle("参加者を一括追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("追加") {
                    let cleaned = giriParseParticipantNames((previewing ? names : giriParseParticipantNames(source)).joined(separator: "\n"))
                    guard !cleaned.isEmpty else { return }
                    onAdd(cleaned)
                    dismiss()
                }.disabled(previewing ? names.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } : source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

func giriParseParticipantNames(_ source: String) -> [String] {
    let separators = CharacterSet(charactersIn: "\r\n,，、\t")
    var seen = Set<String>()
    return source.components(separatedBy: separators).compactMap { line in
        var name = line.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: #"^\s*(?:[-・●○■□▪︎•]\s*|[0-9０-９]+[.．)）:：]\s*)"#, with: "", options: .regularExpression)
        if name.hasPrefix("@") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.range(of: #"^(?:https?://|www\.)"#, options: [.regularExpression, .caseInsensitive]) == nil,
              name.range(of: #"^(?:参加者(?:一覧)?|参加予定(?:者)?|参加(?:する)?人|参加者名|名前|参加者リスト|キャンセル待ち)(?:\s*(?:[（(]\s*[0-9０-９]+\s*人?[)）]|[0-9０-９]+\s*人))?\s*[:：]?$"#, options: .regularExpression) == nil,
              seen.insert(giriEditorNameKey(name)).inserted else { return nil }
        return name
    }
}
