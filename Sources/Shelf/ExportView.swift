import AppKit
import SwiftUI

/// The Copy as File form (⇧⌘C), shown above the shelf where the preview goes.
/// Return pastes the file into the app you were in, ⌘C copies it, ⌘S saves it, Esc goes back.
struct ExportView: View {
    @ObservedObject var model: ShelfModel
    @FocusState private var nameFocused: Bool
    @State private var estimate = ""

    var body: some View {
        if let draft = model.exportDraft {
            form(draft)
        }
    }

    private func form(_ draft: ExportDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc").font(.system(size: 15)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Copy as File").font(.system(size: 13, weight: .semibold))
                    Text(subtitle(draft)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("↩ paste · ⌘C copy · ⌘S save · Esc back").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()

            HStack(alignment: .top, spacing: 20) {
                picture(draft)
                    .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 12) {
                    field("Name") {
                        TextField(draft.originals.count > 1 ? "Keep the original names" : "File name", text: binding(\.name, ""))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .focused($nameFocused)
                            .frame(maxWidth: 340)
                    }
                    if draft.formats.count > 1 {
                        field("Format") {
                            Picker("Format", selection: binding(\.format, draft.format)) {
                                ForEach(draft.formats) { format in
                                    Text(format.title).tag(format)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                    if draft.showsImageOptions && draft.format.isLossy {
                        field("Quality") {
                            Slider(value: binding(\.quality, 0.85), in: 0.1...1)
                                .frame(width: 180)
                            Text("\(Int((draft.quality * 100).rounded()))%")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    }
                    if draft.showsImageOptions {
                        field("Size") {
                            Picker("Size", selection: binding(\.scale, 1.0)) {
                                Text("Original").tag(1.0)
                                Text("75%").tag(0.75)
                                Text("50%").tag(0.5)
                                Text("25%").tag(0.25)
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        .transition(.opacity)
                    }
                    field("") {
                        Text(result(draft))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let error = draft.error {
                        field("") {
                            Text(error).font(.system(size: 11)).foregroundStyle(.red).lineLimit(3)
                        }
                        .transition(.opacity)
                    }
                }
                // Quality and Size come and go with the format.
                .animation(Motion.fade, value: draft.format)
                .animation(Motion.fade, value: draft.error)
                Spacer(minLength: 0)
            }
            .padding(18)

            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 10) {
                if draft.busy { ProgressView().controlSize(.small).transition(.opacity) }
                Spacer()
                Button("Cancel") { model.actions?.cancelExport() }
                    .keyboardShortcut(.cancelAction)
                Button("Save…") { model.actions?.finishExport(.save) }
                Button("Copy") { model.actions?.finishExport(.copy) }
                Button("Paste") { model.actions?.finishExport(.paste) }
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(draft.busy)
            .animation(Motion.fade, value: draft.busy)
            .padding(12)
        }
        .task(id: estimateKey(draft)) { await updateEstimate(draft) }
        .onAppear {
            // After the panel has become key, so the name field really gets focus (text selected).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { nameFocused = true }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
            content()
        }
    }

    private func binding<T>(_ key: WritableKeyPath<ExportDraft, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { model.exportDraft?[keyPath: key] ?? fallback },
                set: { model.exportDraft?[keyPath: key] = $0 })
    }

    @ViewBuilder private func picture(_ draft: ExportDraft) -> some View {
        switch draft.source {
        case .image:
            Thumbnail(url: model.actions?.imageURL(draft.item))
        case .files:
            let first = draft.item.filePaths.first
            if let first, FileExport.isImage(first) {
                Thumbnail(url: URL(fileURLWithPath: first))
            } else if let first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
            }
        case .text:
            Image(nsImage: NSWorkspace.shared.icon(for: draft.format.utType))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
        }
    }

    private func subtitle(_ draft: ExportDraft) -> String {
        switch draft.source {
        case .image:
            return ["Image", draft.item.detail].compactMap { $0 }.joined(separator: " · ")
        case .text:
            return "Text · \((draft.item.text?.count ?? 0).formatted()) characters"
        case .files:
            return draft.item.detail ?? "Files"
        }
    }

    /// "Beach.jpg · 1440 × 900 · 312 KB"
    private func result(_ draft: ExportDraft) -> String {
        [draft.namesSummary, estimate].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func estimateKey(_ draft: ExportDraft) -> String {
        "\(draft.item.id) \(draft.format.rawValue) \(draft.quality) \(draft.scale)"
    }

    /// Measures the real file for the current choices, a moment after they stop changing.
    @MainActor private func updateEstimate(_ draft: ExportDraft) async {
        estimate = ""
        let source: URL?
        let convert: Bool
        switch draft.source {
        case .image:
            source = model.actions?.imageURL(draft.item)
            convert = true
        case .files where draft.originals.count == 1:
            source = draft.item.filePaths.first.map { URL(fileURLWithPath: $0) }
            convert = draft.convertible.first ?? false
        default:
            return
        }
        guard let source else { return }
        try? await Task.sleep(nanoseconds: 250_000_000)   // let the quality slider settle
        if Task.isCancelled { return }
        let format = draft.format, quality = draft.quality, scale = draft.scale
        let text = await Task.detached(priority: .userInitiated) {
            FileExport.describe(source, format: format, quality: quality, scale: scale, convert: convert)
        }.value
        if !Task.isCancelled { estimate = text }
    }
}
