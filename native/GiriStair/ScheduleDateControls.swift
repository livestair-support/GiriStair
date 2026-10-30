import SwiftUI
import UIKit

/// TicketScheduleGroups.swift periodEditor / TicketScheduleEndpointButton:
/// two endpoint cards instead of a compressed full date/time on each form row.
struct GiriSchedulePeriodRow: View {
    let title: String
    @Binding var start: Date?
    @Binding var end: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                GiriScheduleEndpointButton(title: "開始", accessibilityTitle: title + "開始", selection: $start)
                Text("〜").foregroundStyle(.secondary)
                GiriScheduleEndpointButton(title: "終了・締切", accessibilityTitle: title + "締切", selection: $end)
            }
            if let start, let end, end < start {
                Text("終了・締切を開始以降の日時にしてください。")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct GiriScheduleEndpointButton: View {
    let title: String
    let accessibilityTitle: String
    @Binding var selection: Date?
    @State private var showingPicker = false

    var body: some View {
        Button { showingPicker = true } label: {
            VStack(spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                if let selection {
                    Text(selection, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                        .font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.75)
                    Text(GiriDateText.time(selection)).font(.subheadline.weight(.medium))
                } else {
                    Text("未設定").font(.subheadline).foregroundStyle(.secondary)
                    Text("タップして設定").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .monospacedDigit().foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 68)
            .padding(.horizontal, 6)
            .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .accessibilityLabel("\(accessibilityTitle)、\(selection.map { GiriDateText.dateTime($0) } ?? "未設定")")
        .contextMenu {
            if selection != nil {
                Button("未定に戻す", systemImage: "arrow.counterclockwise") { selection = nil }
            }
        }
        .sheet(isPresented: $showingPicker) {
            GiriScheduleEndpointPicker(title: accessibilityTitle, initialDate: selection ?? Date()) { selection = $0 }
        }
    }
}

private struct GiriScheduleEndpointPicker: View {
    let title: String
    let onSave: (Date) -> Void
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialDate: Date, onSave: @escaping (Date) -> Void) {
        self.title = title
        self.onSave = onSave
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("日付", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                GiriScheduleTimeWheel(selection: $date)
                    .frame(maxWidth: .infinity).frame(height: 216)
                    .accessibilityLabel("時刻")
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("完了") { onSave(date); dismiss() } }
            }
        }
        .tint(.indigo)
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .presentationDetents([.large])
    }
}

private struct GiriScheduleTimeWheel: UIViewRepresentable {
    @Binding var selection: Date
    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = 5
        picker.locale = Locale(identifier: "ja_JP")
        picker.calendar = Calendar(identifier: .gregorian)
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return picker
    }
    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.selection = $selection
        if picker.date != selection { picker.setDate(selection, animated: false) }
    }
    final class Coordinator: NSObject {
        var selection: Binding<Date>
        init(selection: Binding<Date>) { self.selection = selection }
        @objc func changed(_ picker: UIDatePicker) { selection.wrappedValue = picker.date }
    }
}
