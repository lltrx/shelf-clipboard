import AppKit
import SwiftUI

/// Blur and crop, inside the paste box (⌘E, or the Blur & Crop button). Drag over the image: with
/// Blur the area becomes a mosaic, with Crop only that area is kept. B and C switch tools, ⌘Z
/// undoes, ⌫ clears, Return is Done and Esc puts back what there was. The box then pastes, copies
/// or saves the edited image.
struct ImageEditorView: View {
    @ObservedObject var model: ShelfModel
    let draft: ExportDraft
    let source: URL?
    @State private var base: CGImage?      // the image, at most 1600 pixels across
    @State private var shown: CGImage?     // the same with the blurs applied
    @State private var dragging: EditRect?
    @State private var unreadable = false
    @State private var crosshair = false

    private var editor: ExportDraft.Editor { draft.editor ?? ExportDraft.Editor(before: draft.edits) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Tool", selection: Binding(get: { editor.tool }, set: { model.exportDraft?.editor?.tool = $0 })) {
                    Text("Blur").tag(EditTool.blur)
                    Text("Crop").tag(EditTool.crop)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                Text(instruction)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Button { model.exportDraft?.undoEdit() } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Undo (⌘Z)")
                    .disabled(!editor.canUndo)
                Button("Clear") { model.exportDraft?.clearEdits() }
                    .help("Remove all blurs and the crop (⌫)")
                    .disabled(draft.edits.isEmpty)
            }
            .controlSize(.small)
            .frame(height: 24)

            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))

            Divider()

            HStack(spacing: 8) {
                HStack(spacing: 10) {
                    hint("B", "Blur")
                    hint("C", "Crop")
                    hint("⌘Z", "Undo")
                    hint("esc", "Cancel")
                }
                .foregroundStyle(.secondary)
                .fixedSize()
                Spacer(minLength: 8)
                Button("Cancel") { model.actions?.closeImageEditor(keep: false) }
                Button("Done") { model.actions?.closeImageEditor(keep: true) }
                    .keyboardShortcut(.defaultAction)
            }
            .frame(height: 28)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12 + PopoverShape.arrowHeight)
        .frame(width: model.popoverSize.width, height: model.popoverSize.height, alignment: .top)
        .background(PopoverShape(arrowX: model.popoverArrowX).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(PopoverShape(arrowX: model.popoverArrowX).stroke(Color.primary.opacity(0.16), lineWidth: 1))
        .onAppear(perform: load)
        .onDisappear {
            if crosshair { NSCursor.pop() }
            crosshair = false
        }
        .onChange(of: draft.edits.blurs) { render() }
    }

    private var instruction: String {
        if !draft.edits.isEmpty { return draft.edits.summary.capitalizedFirst }
        return editor.tool == .blur ? "Drag over what to hide" : "Drag around what to keep"
    }

    @ViewBuilder private var canvas: some View {
        GeometryReader { geo in
            if let image = shown ?? base {
                let size = fitted(CGSize(width: image.width, height: image.height), in: geo.size)
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .overlay(marks(size))
                    .contentShape(Rectangle())
                    .gesture(drag(size))
                    .onHover { inside in
                        guard inside != crosshair else { return }
                        crosshair = inside
                        if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
                    }
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            } else if unreadable {
                Text("Shelf can't open this image.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(6)
    }

    /// Outlines of the blurred areas, the crop (everything outside it dimmed), and the area being dragged.
    private func marks(_ size: CGSize) -> some View {
        let crop = editor.tool == .crop ? (dragging ?? draft.edits.crop) : draft.edits.crop
        return ZStack(alignment: .topLeading) {
            ForEach(Array(draft.edits.blurs.enumerated()), id: \.offset) { _, blur in
                Rectangle()
                    .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: rect(blur, size).width, height: rect(blur, size).height)
                    .offset(x: rect(blur, size).minX, y: rect(blur, size).minY)
            }
            if let crop {
                let r = rect(crop, size)
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: size))
                    p.addRect(r)
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                Rectangle()
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
            }
            if editor.tool == .blur, let dragging {
                let r = rect(dragging, size)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.25))
                    .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1.5))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func drag(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in dragging = area(from: value.startLocation, to: value.location, in: size) }
            .onEnded { value in
                dragging = nil
                model.exportDraft?.addEdit(area(from: value.startLocation, to: value.location, in: size))
            }
    }

    private func area(from a: CGPoint, to b: CGPoint, in size: CGSize) -> EditRect {
        guard size.width > 0, size.height > 0 else { return EditRect(x: 0, y: 0, w: 0, h: 0) }
        func clampX(_ x: CGFloat) -> Double { Double(min(max(x, 0), size.width) / size.width) }
        func clampY(_ y: CGFloat) -> Double { Double(min(max(y, 0), size.height) / size.height) }
        let x0 = clampX(min(a.x, b.x)), x1 = clampX(max(a.x, b.x))
        let y0 = clampY(min(a.y, b.y)), y1 = clampY(max(a.y, b.y))
        return EditRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
    }

    private func rect(_ area: EditRect, _ size: CGSize) -> CGRect {
        CGRect(x: area.x * size.width, y: area.y * size.height, width: area.w * size.width, height: area.h * size.height)
    }

    /// The image as large as fits (small ones at most twice their size).
    private func fitted(_ image: CGSize, in box: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let scale = min(box.width / image.width, box.height / image.height, 2)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 11, weight: .semibold))
            Text(label).font(.system(size: 11))
        }
    }

    private func load() {
        guard base == nil else { return }
        guard let source, let image = FileExport.displayImage(source, maxPixels: 1600) else {
            unreadable = true
            return
        }
        base = image
        render()
    }

    /// The blurs as they'll be in the file (the same mosaic, at this size).
    private func render() {
        guard let base else { return }
        let blurs = ImageEdits(blurs: draft.edits.blurs)
        shown = blurs.isEmpty ? base : FileExport.apply(blurs, to: base)
    }
}
