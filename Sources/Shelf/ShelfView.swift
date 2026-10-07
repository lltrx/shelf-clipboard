import AppKit
import SwiftUI

/// What the views ask the app to do. Implemented by AppDelegate.
protocol ShelfActions: AnyObject {
    func imageURL(_ item: ClipItem) -> URL?
    func attributed(_ item: ClipItem) -> NSAttributedString
    func paste(_ item: ClipItem, plain: Bool)
    func copy(_ item: ClipItem)
    func delete(_ item: ClipItem)
    func setBoard(_ item: ClipItem, _ board: Int64?)
    func togglePreview()
    func edit(_ item: ClipItem)
    func commitName()
    func deleteBoard(_ board: Board)
}

enum Naming: Equatable {
    case new
    case rename(Int64)
}

final class ShelfModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var boards: [Board] = []
    @Published var tab: Int64? { didSet { selection = 0 } }   // nil = History
    @Published var query = "" { didSet { selection = 0 } }
    @Published var selection = 0
    @Published var now = Date()
    @Published var focusTick = 0
    @Published var stack: [Int64] = []          // item ids queued for paste stack, in order
    @Published var previewing = false
    @Published var editing = false
    @Published var naming: Naming?
    @Published var nameDraft = ""

    weak var actions: ShelfActions?
    weak var editor: NSTextView?
    var pendingPin: Int64?                      // item to pin once a new board is named

    var filtered: [ClipItem] {
        let base = tab.map { board in items.filter { $0.board == board } } ?? items
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        return base.filter {
            ($0.text?.localizedCaseInsensitiveContains(q) ?? false) ||
                ($0.ocr?.localizedCaseInsensitiveContains(q) ?? false) ||
                ($0.sourceName?.localizedCaseInsensitiveContains(q) ?? false) ||
                $0.kind.title.localizedCaseInsensitiveContains(q)
        }
    }

    var selected: ClipItem? {
        let list = filtered
        return list.indices.contains(selection) ? list[selection] : nil
    }

    func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selection = min(max(selection + delta, 0), count - 1)
    }

    func clampSelection() {
        selection = min(selection, max(filtered.count - 1, 0))
    }

    func cycleTab(_ delta: Int) {
        let tabs: [Int64?] = [nil] + boards.map(\.id)
        let i = tabs.firstIndex(of: tab) ?? 0
        tab = tabs[(i + delta + tabs.count) % tabs.count]
    }

    func toggleStack(_ item: ClipItem) {
        if let i = stack.firstIndex(of: item.id) { stack.remove(at: i) } else { stack.append(item.id) }
    }

    func startNaming(_ n: Naming) {
        if case .rename(let id) = n { nameDraft = boards.first { $0.id == id }?.name ?? "" } else { nameDraft = "" }
        naming = n
    }
}

// MARK: - Shelf

struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    @FocusState private var focus: Field?

    private enum Field { case search, name }

    var body: some View {
        let list = model.filtered
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($focus, equals: .search)
                }
                .frame(width: 280, alignment: .leading)
                Spacer()
                tabs
                Spacer()
                Text(status(list))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 280, alignment: .trailing)
            }
            .padding(.horizontal, 22)

            if list.isEmpty {
                Text(emptyText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                cards(list)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 18)
        .onChange(of: model.focusTick) { focus = .search }
        .onChange(of: model.naming) { focus = model.naming == nil ? .search : .name }
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            TabButton(title: "History", selected: model.tab == nil) { model.tab = nil }
            ForEach(model.boards) { board in
                if model.naming == .rename(board.id) {
                    nameField
                } else {
                    TabButton(title: board.name, selected: model.tab == board.id) { model.tab = board.id }
                        .contextMenu {
                            Button("Rename") { model.startNaming(.rename(board.id)) }
                            Button("Delete Pinboard") { model.actions?.deleteBoard(board) }
                        }
                }
            }
            if model.naming == .new {
                nameField
            } else {
                Button { model.startNaming(.new) } label: {
                    Image(systemName: "plus").font(.system(size: 12)).frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("New pinboard (⌘N)")
            }
        }
    }

    private var nameField: some View {
        TextField("Pinboard name", text: $model.nameDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .frame(width: 130)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.1)))
            .focused($focus, equals: .name)
            .onSubmit { model.actions?.commitName() }
    }

    private func cards(_ list: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        CardView(item: item, selected: index == model.selection, now: model.now,
                                 stackPosition: model.stack.firstIndex(of: item.id).map { $0 + 1 },
                                 imageURL: model.actions?.imageURL(item))
                            .id(item.id)
                            .onTapGesture(count: 2) { model.actions?.paste(item, plain: false) }
                            .onTapGesture { model.selection = index }
                            .contextMenu { menu(item, index) }
                    }
                }
                .padding(.horizontal, 22)
            }
            .onChange(of: model.selection) {
                if let id = model.selected?.id { proxy.scrollTo(id) }
            }
            .onChange(of: model.focusTick) {
                if let id = list.first?.id { proxy.scrollTo(id, anchor: .leading) }
            }
        }
    }

    @ViewBuilder private func menu(_ item: ClipItem, _ index: Int) -> some View {
        Button("Paste") { model.actions?.paste(item, plain: false) }
        if item.formatted {
            Button("Paste as Plain Text") { model.actions?.paste(item, plain: true) }
        }
        Button("Copy") { model.actions?.copy(item) }
        Divider()
        Button("Preview") { model.selection = index; if !model.previewing { model.actions?.togglePreview() } }
        if item.editable {
            Button("Edit…") { model.selection = index; model.actions?.edit(item) }
        }
        Button(model.stack.contains(item.id) ? "Remove from Paste Stack" : "Add to Paste Stack") { model.toggleStack(item) }
        Divider()
        Menu("Pin to") {
            ForEach(model.boards) { board in
                Button(board.name) { model.actions?.setBoard(item, board.id) }
            }
            Divider()
            Button("New Pinboard…") { model.pendingPin = item.id; model.startNaming(.new) }
        }
        if item.pinned {
            Button("Unpin") { model.actions?.setBoard(item, nil) }
        }
        Divider()
        Button("Delete") { model.actions?.delete(item) }
    }

    private func status(_ list: [ClipItem]) -> String {
        if !model.stack.isEmpty {
            return "\(model.stack.count) in stack · Return pastes in order"
        }
        return list.count == 1 ? "1 item" : "\(list.count) items"
    }

    private var emptyText: String {
        if !model.query.isEmpty { return "No matches" }
        if model.tab != nil { return "Nothing pinned here yet. Press ⌘P on an item to pin it." }
        return "Nothing copied yet"
    }
}

struct TabButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.primary.opacity(0.12) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CardView: View {
    let item: ClipItem
    let selected: Bool
    let now: Date
    let stackPosition: Int?
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.kind.title).font(.system(size: 12, weight: .semibold))
                    Text(relativeTime).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if let icon = AppIcons.icon(for: item.sourceBundle) {
                    Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                }
            }
            .padding(10)

            Divider().opacity(0.6)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
                .clipped()

            HStack {
                Text(footer).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if let stackPosition {
                    Text("Stack \(stackPosition)").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.accentColor)
                } else if item.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .frame(width: 220, height: 220)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(borderColor, lineWidth: selected || stackPosition != nil ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private var borderColor: Color {
        if selected { return .accentColor }
        if stackPosition != nil { return Color.accentColor.opacity(0.45) }
        return Color.primary.opacity(0.08)
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .text:
            Text(String((item.text ?? "").prefix(800)))
                .font(.system(size: 12))
                .lineLimit(9)
        case .link:
            VStack(alignment: .leading, spacing: 4) {
                Text(URL(string: item.text ?? "")?.host ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(item.text ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            }
        case .image:
            Thumbnail(url: imageURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .file:
            FileList(paths: Array(item.filePaths.prefix(4)), iconSize: 44, showPaths: false)
        }
    }

    private var footer: String {
        switch item.kind {
        case .text:
            let n = item.text?.count ?? 0
            let count = n == 1 ? "1 character" : "\(n.formatted()) characters"
            return item.formatted ? count + " · Formatted" : count
        case .link: return item.sourceName ?? "Link"
        case .image:
            let hasText = !(item.ocr ?? "").isEmpty
            return (item.detail ?? "") + (hasText ? " · Contains text" : "")
        case .file: return item.detail ?? ""
        }
    }

    private var relativeTime: String {
        if now.timeIntervalSince(item.created) < 10 { return "Just now" }
        return CardView.relative.localizedString(for: item.created, relativeTo: now)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}

struct FileList: View {
    let paths: [String]
    let iconSize: CGFloat
    let showPaths: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !showPaths, let first = paths.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first)).resizable().frame(width: iconSize, height: iconSize)
            }
            ForEach(paths, id: \.self) { path in
                HStack(spacing: 10) {
                    if showPaths {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: iconSize, height: iconSize)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text((path as NSString).lastPathComponent)
                            .font(.system(size: showPaths ? 13 : 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if showPaths {
                            Text(path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct PreviewView: View {
    @ObservedObject var model: ShelfModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item = model.selected {
                HStack(spacing: 10) {
                    if let icon = AppIcons.icon(for: item.sourceBundle) {
                        Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(item)).font(.system(size: 13, weight: .semibold))
                        Text(subtitle(item)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(hint(item)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(14)
                Divider()
                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Nothing selected").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .text, .link:
            RichTextView(key: "\(item.id)-\(model.editing)", paper: item.formatted, editable: model.editing, model: model) {
                model.actions?.attributed(item) ?? NSAttributedString(string: item.text ?? "")
            }
        case .image:
            HStack(spacing: 0) {
                Thumbnail(url: model.actions?.imageURL(item), maxPixel: 2400)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(14)
                if let ocr = item.ocr, !ocr.isEmpty {
                    Divider()
                    ScrollView {
                        Text(ocr)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .frame(width: 280)
                }
            }
        case .file:
            ScrollView {
                FileList(paths: item.filePaths, iconSize: 32, showPaths: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
    }

    private func title(_ item: ClipItem) -> String {
        [item.kind.title, item.sourceName].compactMap { $0 }.joined(separator: " from ")
    }

    private func subtitle(_ item: ClipItem) -> String {
        let date = item.created.formatted(date: .abbreviated, time: .shortened)
        switch item.kind {
        case .text, .link:
            let n = item.text?.count ?? 0
            return "\(date) · \(n.formatted()) characters" + (item.formatted ? " · Formatted" : "")
        case .image, .file:
            return [date, item.detail].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private func hint(_ item: ClipItem) -> String {
        if model.editing { return "⌘Return paste · ⇧⌘Return plain · Esc cancel" }
        return item.editable ? "⌘E edit · Space close" : "Space close"
    }
}

/// NSTextView for previewing and editing, keeping rich formatting.
/// Formatted items are shown on a white page so their own colors stay readable.
struct RichTextView: NSViewRepresentable {
    let key: String
    let paper: Bool
    let editable: Bool
    let model: ShelfModel
    let make: () -> NSAttributedString

    final class Coordinator { var key = "" }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let tv = scroll.documentView as! NSTextView
        tv.textContainerInset = NSSize(width: 14, height: 12)
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard context.coordinator.key != key, let tv = scroll.documentView as? NSTextView else { return }
        context.coordinator.key = key
        let plainAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
        tv.isRichText = paper
        tv.isEditable = editable
        tv.drawsBackground = paper
        tv.backgroundColor = paper ? .white : .clear
        scroll.drawsBackground = paper
        scroll.backgroundColor = paper ? .white : .clear
        tv.textStorage?.setAttributedString(make())
        if !paper { tv.typingAttributes = plainAttributes }
        tv.scroll(.zero)
        model.editor = tv
        if editable {
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            }
        }
    }
}

// MARK: - Images and icons

/// Downsampled image, decoded off the main thread.
struct Thumbnail: View {
    let url: URL?
    var maxPixel = 400
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            guard let url else { return }
            let key = "\(url.path)#\(maxPixel)" as NSString
            if let cached = Thumbnail.cache.object(forKey: key) { image = cached; return }
            let size = maxPixel
            let loaded = await Task.detached(priority: .userInitiated) { Thumbnail.load(url, size) }.value
            if let loaded { Thumbnail.cache.setObject(loaded, forKey: key) }
            image = loaded
        }
    }

    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 200
        return c
    }()

    nonisolated private static func load(_ url: URL, _ maxPixel: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}

enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundle: String?) -> NSImage? {
        guard let bundle else { return nil }
        if let cached = cache[bundle] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundle] = icon
        return icon
    }
}
