import AppKit
import SwiftUI

/// Mark up, blur and crop an image, inside the paste box (⌘E on an image card, or Markup in the box).
/// Drag on the image with a tool: Arrow (A), Box (R), Highlight (H), Text (T: click, type, Return),
/// Blur (B: the area becomes a mosaic) or Crop (C: only that area is kept). 1–7 pick a color.
/// All of it works from the keyboard too: Space adds one in the middle, Tab selects, the arrows move
/// (⌥ resizes, ⇧ in bigger steps), ⌫ deletes, Return changes selected text or is Done, Esc lets go
/// and then cancels. The box then pastes, copies or saves the edited image.
struct ImageEditorView: View {
    @ObservedObject var model: ShelfModel
    let draft: ExportDraft
    let source: URL?
    @State private var base: CGImage?      // the image, at most 1600 pixels across
    @State private var shown: CGImage?     // the same with the marks and blurs, as the file will have them
    @State private var drag: (from: EditPoint, to: EditPoint)?
    @State private var unreadable = false
    @State private var crosshair = false
    @FocusState private var textFocused: Bool

    private var editor: ExportDraft.Editor { draft.editor ?? ExportDraft.Editor(before: draft.edits) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    ForEach(EditTool.allCases, id: \.self) { tool in toolButton(tool) }
                }
                Divider().frame(height: 18)
                if editor.typing != nil {
                    TextField("Type, then Return", text: Binding(get: { model.exportDraft?.typedText ?? "" },
                                                                 set: { model.exportDraft?.typeText($0) }))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(maxWidth: 240)
                        .focused($textFocused)
                        .id(editor.typing)   // a new field for each text, so the last one's words don't carry over
                } else if editor.tool.usesColor {
                    HStack(spacing: 5) {
                        ForEach(Array(MarkColor.allCases.enumerated()), id: \.element) { index, color in swatch(color, index) }
                    }
                }
                Spacer(minLength: 8)
                Button { model.exportDraft?.undoEdit() } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Undo (⌘Z)")
                    .disabled(!editor.canUndo && editor.typing == nil)
                Button("Clear") { model.exportDraft?.clearEdits() }
                    .help("Remove everything you've done to the image (⌫)")
                    .disabled(draft.edits.isEmpty)
            }
            .controlSize(.small)
            .frame(height: 24)

            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))

            Divider()

            HStack(spacing: 8) {
                Text(instruction)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
        .onChange(of: draft.edits.uncropped) { render() }
        .onChange(of: editor.typing) {
            // After the field appears, so it really gets the keys.
            let typing = editor.typing != nil
            DispatchQueue.main.async { textFocused = typing }
        }
    }

    /// What the selected tool does, or what the keys do with what's selected.
    private var instruction: String {
        if editor.typing != nil { return "Return keeps the text · Esc takes it back" }
        if let selected = editor.selected {
            var keys = "Arrows move it (⇧ more) · ⌥ arrows resize · ⌫ deletes · Esc lets go"
            if case .mark(let i) = selected, draft.edits.marks.indices.contains(i) {
                switch draft.edits.marks[i].kind {
                case .text: keys = "↩ changes the text · arrows move it · 1–7 color · ⌫ deletes · Esc lets go"
                case .arrow: keys = "Arrows move it (⇧ more) · ⌥ arrows move the tip · 1–7 color · ⌫ deletes"
                case .box: keys += " · 1–7 color"
                case .highlight: break
                }
            }
            return keys
        }
        let tab = draft.edits.isEmpty ? "" : " · ⇥ selects"
        return editor.tool.instruction + " · Space adds one" + tab
    }

    private func toolButton(_ tool: EditTool) -> some View {
        let on = editor.tool == tool
        return Button { model.exportDraft?.setTool(tool) } label: {
            Image(systemName: icon(tool))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(on ? Color.white : Color.primary)
                .frame(width: 28, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(on ? Color.accentColor : Color.primary.opacity(0.07)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(tool.title) (\(tool.letter))")
    }

    private func icon(_ tool: EditTool) -> String {
        switch tool {
        case .arrow: return "arrow.up.right"
        case .box: return "rectangle"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .blur: return "eye.slash"
        case .crop: return "crop"
        }
    }

    private func swatch(_ color: MarkColor, _ index: Int) -> some View {
        let on = editor.color == color
        return Button { model.exportDraft?.setColor(color) } label: {
            Circle()
                .fill(swiftUIColor(color))
                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                .frame(width: 14, height: 14)
                .padding(2)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2).opacity(on ? 1 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("\(color.rawValue.capitalized) (\(index + 1))")
    }

    private func swiftUIColor(_ color: MarkColor) -> Color {
        Color(.sRGB, red: color.rgb.red, green: color.rgb.green, blue: color.rgb.blue, opacity: 1)
    }

    @ViewBuilder private var canvas: some View {
        GeometryReader { geo in
            if let image = shown ?? base {
                let size = fitted(CGSize(width: image.width, height: image.height), in: geo.size)
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .overlay(overlays(size))
                    .contentShape(Rectangle())
                    .gesture(dragGesture(size))
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

    /// Outlines of the blurred areas, the crop (everything outside it dimmed), and what's being dragged.
    /// The marks themselves are in the image (`shown`), drawn the way the file will have them.
    private func overlays(_ size: CGSize) -> some View {
        let dragArea = drag.map { EditRect(x: min($0.from.x, $0.to.x), y: min($0.from.y, $0.to.y),
                                           w: abs($0.to.x - $0.from.x), h: abs($0.to.y - $0.from.y)) }
        let crop = editor.tool == .crop ? (dragArea ?? draft.edits.crop) : draft.edits.crop
        let tint = editor.tool.usesColor ? swiftUIColor(editor.color) : Color.accentColor
        return ZStack(alignment: .topLeading) {
            ForEach(Array(draft.edits.blurs.enumerated()), id: \.offset) { _, blur in
                let r = rect(blur, size)
                Rectangle()
                    .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
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
            if let selected = editor.selected, editor.typing == nil,
               let area = draft.bounds(of: selected, aspect: size.height > 0 ? Double(size.width / size.height) : 1) {
                let r = rect(area, size).insetBy(dx: -4, dy: -4)
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .background(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.8), lineWidth: 3))
                    .frame(width: max(r.width, 8), height: max(r.height, 8))
                    .offset(x: r.minX, y: r.minY)
            }
            if let drag, let dragArea {
                let r = rect(dragArea, size)
                switch editor.tool {
                case .blur:
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.25))
                        .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1.5))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                case .box:
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(tint, lineWidth: 2.5)
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                case .highlight:
                    Rectangle()
                        .fill(swiftUIColor(.yellow).opacity(0.45))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                case .arrow:
                    Path { p in
                        p.move(to: CGPoint(x: CGFloat(drag.from.x) * size.width, y: CGFloat(drag.from.y) * size.height))
                        p.addLine(to: CGPoint(x: CGFloat(drag.to.x) * size.width, y: CGFloat(drag.to.y) * size.height))
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                case .crop, .text:
                    EmptyView()
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func dragGesture(_ size: CGSize) -> some Gesture {
        // Distance 0, so a click counts too (Text starts where you click).
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                drag = (point(value.startLocation, in: size), point(value.location, in: size))
            }
            .onEnded { value in
                drag = nil
                model.exportDraft?.addDrag(from: point(value.startLocation, in: size), to: point(value.location, in: size),
                                           aspect: size.height > 0 ? Double(size.width / size.height) : 1)
            }
    }

    private func point(_ p: CGPoint, in size: CGSize) -> EditPoint {
        guard size.width > 0, size.height > 0 else { return EditPoint(x: 0, y: 0) }
        return EditPoint(x: Double(p.x / size.width), y: Double(p.y / size.height)).clamped
    }

    private func rect(_ area: EditRect, _ size: CGSize) -> CGRect {
        CGRect(x: CGFloat(area.x) * size.width, y: CGFloat(area.y) * size.height,
               width: CGFloat(area.w) * size.width, height: CGFloat(area.h) * size.height)
    }

    /// The image as large as fits (small ones at most twice their size).
    private func fitted(_ image: CGSize, in box: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let scale = min(box.width / image.width, box.height / image.height, 2)
        return CGSize(width: image.width * scale, height: image.height * scale)
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

    /// The marks and blurs as they'll be in the file (drawn the same way, at this size).
    private func render() {
        guard let base else { return }
        let edits = draft.edits.uncropped
        shown = edits.isEmpty ? base : FileExport.apply(edits, to: base)
    }
}
