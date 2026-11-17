import AppKit
import SwiftUI

/// The paste box: Return on an image or file card (or ⌘R on any card) opens it just above the card.
/// Name, format and size; Return pastes (the original, if nothing changed), ⇧Return pastes the
/// original, ⌘C copies, ⌘S saves, Esc goes back. Its height is fixed per card (`popoverHeight`), so
/// the panel around it never needs resizing.
struct ExportView: View {
    @ObservedObject var model: ShelfModel
    @FocusState private var nameFocused: Bool
    @State private var estimate = ""   // the new file: "861 × 539 · 180 KB"
    @State private var original = ""  // the card as it is: "PNG · 1722 × 1078 · 412 KB"

    var body: some View {
        if let draft = model.exportDraft {
            if draft.editor != nil {
                ImageEditorView(model: model, draft: draft, source: singleSource(draft))
            } else {
                box(draft)
            }
        }
    }

    private func box(_ draft: ExportDraft) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                label("Name")
                TextField(draft.originals.count > 1 ? "Keep their names" : "File name", text: binding(\.name, ""))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .focused($nameFocused)
                if draft.formats.count > 1 {
                    Picker("Format", selection: binding(\.format, draft.format)) {
                        ForEach(draft.formats) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .overlay(focusRing(.format))
                }
            }
            .frame(height: 28)

            if draft.hasImages {
                HStack(spacing: 10) {
                    label("Size")
                    HStack(spacing: 4) {
                        ForEach(ExportDraft.scales, id: \.self) { scale in
                            sizeButton(scale, draft)
                        }
                    }
                    .overlay(focusRing(.size))
                    .disabled(!draft.showsImageOptions)
                    .opacity(draft.showsImageOptions ? 1 : 0.45)
                    .help(resizeTip(draft))
                    Spacer(minLength: 8)
                    if draft.showsImageOptions && draft.format.isLossy {
                        Picker("Quality", selection: binding(\.quality, 0.8)) {
                            ForEach(ExportDraft.qualities, id: \.self) { quality in
                                Text("Quality \(Int((quality * 100).rounded()))%").tag(quality)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .overlay(focusRing(.quality))
                        .transition(.opacity)
                    }
                }
                .frame(height: 26)
                .animation(Motion.fade, value: draft.format)
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline(draft))
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let error = draft.error {
                        Text(error).font(.system(size: 11)).foregroundStyle(.red).lineLimit(1).truncationMode(.tail)
                    } else {
                        Text(detail(draft)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if draft.canEdit {
                    Button { model.actions?.openImageEditor() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "pencil.tip.crop.circle")
                            Text("Markup")
                            Text("⌘E").foregroundStyle(.secondary)
                        }
                        .font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                    .help("Draw arrows, boxes, highlights and text, hide parts or crop the image")
                    .disabled(draft.busy)
                }
            }
            .padding(.leading, 54)
            .frame(height: 32, alignment: .topLeading)

            Divider()

            HStack(spacing: 8) {
                HStack(spacing: 10) {
                    ForEach(keyHints(draft), id: \.self) { hint in
                        HStack(spacing: 4) {
                            Text(hint.key).font(.system(size: 11, weight: .semibold))
                            Text(hint.label).font(.system(size: 11))
                        }
                    }
                }
                .foregroundStyle(.secondary)
                .fixedSize()
                if draft.busy { ProgressView().controlSize(.small).transition(.opacity) }
                Spacer(minLength: 8)
                Button("Save…") { model.actions?.finishExport(.save) }
                Button("Copy") { model.actions?.finishExport(.copy) }
                Button("Paste") { model.actions?.finishExport(.paste) }
                    .keyboardShortcut(.defaultAction)
            }
            .frame(height: 28)
            .disabled(draft.busy)
            .animation(Motion.fade, value: draft.busy)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12 + PopoverShape.arrowHeight)
        .frame(width: 400, height: draft.popoverHeight, alignment: .top)
        .background(PopoverShape(arrowX: model.popoverArrowX).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(PopoverShape(arrowX: model.popoverArrowX).stroke(Color.primary.opacity(0.16), lineWidth: 1))
        .task(id: estimateKey(draft)) { await updateEstimate(draft) }
        .task(id: draft.id) { await describeOriginal(draft) }
        .onAppear {
            // After the panel has become key, so the name field really gets focus (text selected).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { nameFocused = true }
        }
        // Tab moves between the controls (handled in AppDelegate); the name field follows along.
        .onChange(of: model.exportFocus) { nameFocused = model.exportFocus == .name }
        .onChange(of: nameFocused) { if nameFocused { model.exportFocus = .name } }
        .onChange(of: draft.format) {
            if let now = model.exportDraft, !now.fields.contains(model.exportFocus) { model.exportFocus = .format }
        }
    }

    /// The blue ring on the control Tab is on (the name field draws its own).
    private func focusRing(_ field: ExportField) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.accentColor, lineWidth: 2)
            .padding(-3)
            .opacity(model.exportFocus == field ? 1 : 0)
            .allowsHitTesting(false)
    }

    /// The keys worth knowing where focus is now.
    private func keyHints(_ draft: ExportDraft) -> [BoxHint] {
        var hints: [BoxHint] = []
        if model.exportFocus == .name {
            if draft.source != .text { hints.append(BoxHint(key: "⇧↩", label: "Original")) }
        } else {
            hints.append(BoxHint(key: "← →", label: "Change"))
        }
        if draft.fields.count > 1 { hints.append(BoxHint(key: "⇥", label: "Next")) }
        return hints
    }

    private func resizeTip(_ draft: ExportDraft) -> String {
        draft.showsImageOptions ? "Make the image smaller" : "Choose an image format to resize"
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 44, alignment: .trailing)
    }

    private func sizeButton(_ scale: Double, _ draft: ExportDraft) -> some View {
        let on = draft.scale == scale
        return Button { model.exportDraft?.scale = scale } label: {
            Text(scale == 1 ? "Original" : "\(Int(scale * 100))%")
                .font(.system(size: 12, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Color.white : Color.primary)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.accentColor : Color.primary.opacity(0.08)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func binding<T>(_ key: WritableKeyPath<ExportDraft, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { model.exportDraft?[keyPath: key] ?? fallback },
                set: { model.exportDraft?[keyPath: key] = $0 })
    }

    /// What Return will paste.
    private func headline(_ draft: ExportDraft) -> String {
        if draft.pastesOriginal { return "Pastes it as it is" }
        return [draft.namesSummary, estimate].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// What there is now.
    private func detail(_ draft: ExportDraft) -> String {
        if draft.source == .text { return "\((draft.item.text?.count ?? 0).formatted()) characters" }
        if draft.pastesOriginal { return original }
        let was = original.isEmpty ? nil : "was \(original)"
        return [draft.edits.isEmpty ? nil : draft.edits.summary.capitalizedFirst, was].compactMap { $0 }.joined(separator: " · ")
    }

    private func estimateKey(_ draft: ExportDraft) -> String {
        "\(draft.id) \(draft.format.rawValue) \(draft.quality) \(draft.scale) \(String(describing: draft.edits))"
    }

    /// The single image or file this card holds, if there is one to measure.
    private func singleSource(_ draft: ExportDraft) -> URL? {
        switch draft.source {
        case .image: return model.actions?.imageURL(draft.item)
        case .files where draft.originals.count == 1: return draft.item.filePaths.first.map { URL(fileURLWithPath: $0) }
        default: return nil
        }
    }

    /// The new file, measured for real, a moment after the choices stop changing.
    @MainActor private func updateEstimate(_ draft: ExportDraft) async {
        estimate = ""
        guard !draft.pastesOriginal, draft.hasImages, draft.outputFormat.isImage, let source = singleSource(draft) else { return }
        try? await Task.sleep(nanoseconds: 200_000_000)
        if Task.isCancelled { return }
        let format = draft.outputFormat, quality = draft.quality, scale = draft.scale, edits = draft.edits
        let text = await Task.detached(priority: .userInitiated) {
            FileExport.describe(source, format: format, quality: quality, scale: scale, convert: true, edits: edits)
        }.value
        if !Task.isCancelled { estimate = text }
    }

    /// The card as it is: "PNG · 1722 × 1078 · 412 KB", or "3 files".
    @MainActor private func describeOriginal(_ draft: ExportDraft) async {
        original = ""
        guard let source = singleSource(draft) else {
            if draft.originals.count > 1 { original = "\(draft.originals.count) files" }
            return
        }
        let kind = source.pathExtension.uppercased()
        let text = await Task.detached(priority: .userInitiated) {
            FileExport.describe(source, format: .original, quality: 1, scale: 1, convert: false)
        }.value
        original = [kind.isEmpty ? nil : kind, text.isEmpty ? nil : text].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct BoxHint: Hashable {
    let key: String
    let label: String
}

/// A rounded box with an arrow on its bottom edge, pointing down at the card.
struct PopoverShape: Shape {
    static let arrowHeight: CGFloat = 8
    var arrowX: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 12
        let half: CGFloat = 9
        let bottom = rect.maxY - Self.arrowHeight
        let x = min(max(arrowX, rect.minX + radius + half), rect.maxX - radius - half)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius), radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom - radius))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: bottom), tangent2End: CGPoint(x: rect.maxX - radius, y: bottom), radius: radius)
        path.addLine(to: CGPoint(x: x + half, y: bottom))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        path.addLine(to: CGPoint(x: x - half, y: bottom))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: bottom))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: bottom), tangent2End: CGPoint(x: rect.minX, y: bottom - radius), radius: radius)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
        path.closeSubpath()
        return path
    }
}
