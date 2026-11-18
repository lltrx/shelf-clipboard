import AppKit
import SwiftUI

/// What the views ask the app to do. Implemented by AppDelegate.
protocol ShelfActions: AnyObject {
    func imageURL(_ item: ClipItem) -> URL?
    func attributed(_ item: ClipItem) -> NSAttributedString
    func paste(_ item: ClipItem, plain: Bool)
    func pasteFromCard(_ item: ClipItem)
    func pasteAs(_ item: ClipItem, _ option: PasteOption)
    func copy(_ item: ClipItem)
    func delete(_ item: ClipItem)
    func setBoard(_ item: ClipItem, _ board: Int64?)
    func togglePreview()
    func edit(_ item: ClipItem)
    func startExport(_ item: ClipItem)
    func markup(_ item: ClipItem)
    func finishExport(_ action: ExportAction)
    func cancelExport()
    func openImageEditor()
    func closeImageEditor(keep: Bool)
    func dragItem(_ item: ClipItem) -> NSItemProvider?
    func commitName()
    func deleteBoard(_ board: Board)
    func ignoreApp(_ item: ClipItem)
    func showMenu()
    func showStyleMenu()
}

enum Naming: Equatable {
    case new
    case rename(Int64)
}

final class ShelfModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var boards: [Board] = []
    @Published var tab: Int64? { didSet { selection = 0 } }   // nil = History
    @Published var kindFilter: ClipKind? { didSet { selection = 0 } }   // nil = every kind
    @Published var query = "" { didSet { selection = 0 } }
    @Published var selection = 0
    @Published var now = Date()
    @Published var focusTick = 0
    @Published var stack: [Int64] = []          // item ids queued for paste stack, in order
    @Published var password: ClipItem?          // placeholder card for a password on the clipboard
    @Published var previewing = false
    @Published var editing = false
    @Published var exportDraft: ExportDraft?    // the Copy as File form, while it's open
    @Published var naming: Naming?
    @Published var nameDraft = ""
    @Published var commandHeld = false          // ⌘ held down: cards show ⌘1…⌘9 and the bar lists ⌘ shortcuts
    @Published var target: TargetApp?           // the app the shelf pastes into
    @Published var plainEverywhere = false      // Paste as Plain Text by Default
    @Published var appStyles: [String: Bool] = [:]   // bundle id → Return pastes plain text (true) or formatted there
    @Published var askBeforePasting = true      // Return on an image or file opens the paste box first
    @Published var popoverArrowX: CGFloat = 200 // where the paste box's arrow points, in the box
    @Published var popoverSize = CGSize(width: 400, height: 193)   // the box's size (bigger while editing an image)
    @Published var exportFocus: ExportField = .name   // the paste box control Tab is on
    var selectedCardMidX: CGFloat?              // the selected card's center in the shelf, for the paste box
    var cardFrames: [Int64: CGRect] = [:]      // where the visible cards are, to drag several at once

    struct TargetApp: Equatable {
        let bundle: String
        let name: String
    }

    static let filterKinds: [ClipKind] = [.text, .link, .image, .file]

    weak var actions: ShelfActions?
    weak var editor: NSTextView?
    var pendingPins: [Int64] = []               // cards to pin once a new board is named
    @Published var canUndo = false              // ⌘Z can bring deleted cards back

    /// Return pastes plain text (⇧ adds the formatting back): the target app's own setting, else the default.
    var plainByDefault: Bool {
        target.flatMap { appStyles[$0.bundle] } ?? plainEverywhere
    }

    var filtered: [ClipItem] {
        var base = tab.map { board in items.filter { $0.board == board } } ?? items
        if let kindFilter { base = base.filter { $0.kind == kindFilter } }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            // A password on the clipboard is the most recent copy, so it leads History.
            if tab == nil, kindFilter == nil, let password { return [password] + base }
            return base
        }
        let search = SearchQuery(q, now: now)   // from:app, @today, @yesterday, @week, @month, then text
        return base.filter(search.matches)
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

    /// ↑ ↓: All, Text, Links, Images, Files.
    func cycleKind(_ delta: Int) {
        let kinds: [ClipKind?] = [nil] + Self.filterKinds.map { Optional($0) }
        let i = kinds.firstIndex(of: kindFilter) ?? 0
        kindFilter = kinds[(i + delta + kinds.count) % kinds.count]
    }

    func toggleStack(_ item: ClipItem) {
        guard !item.concealed else { return }
        if let i = stack.firstIndex(of: item.id) { stack.remove(at: i) } else { stack.append(item.id) }
    }

    func startNaming(_ n: Naming) {
        if case .rename(let id) = n { nameDraft = boards.first { $0.id == id }?.name ?? "" } else { nameDraft = "" }
        naming = n
    }
}

// MARK: - Shelf

/// Shelf's motion: short and quiet. With Reduce Motion nothing slides or scales; fades stay.
enum Motion {
    static let fade = Animation.easeOut(duration: 0.15)
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.86)

    static func move(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : spring }
}

struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    @FocusState private var focus: Field?
    @Namespace private var pills   // the highlight that slides to the selected tab and filter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field { case search, name }

    var body: some View {
        let list = model.filtered
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search   from:app  @today", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($focus, equals: .search)
                    kindFilters
                }
                .frame(width: 300, alignment: .leading)
                Spacer()
                tabs
                Spacer()
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(status(list))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    // The menu bar menu, also here: crowded menu bars can hide Shelf's icon.
                    Button { model.actions?.showMenu() } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 14)).frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Shelf menu · ⌘, Settings")
                }
                .frame(width: 300, alignment: .trailing)
            }
            .padding(.horizontal, 22)

            Group {
                if list.isEmpty {
                    emptyState.transition(.opacity)
                } else {
                    cards(list).transition(.opacity)
                }
            }
            .animation(Motion.fade, value: list.isEmpty)

            footer
                .padding(.horizontal, 22)
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .onChange(of: model.focusTick) { focus = .search }
        .onChange(of: model.naming) { focus = model.naming == nil ? .search : .name }
    }

    /// Show only one kind of card. ↑ ↓ cycle through them.
    private var kindFilters: some View {
        HStack(spacing: 2) {
            ForEach(ShelfModel.filterKinds, id: \.self) { kind in
                let on = model.kindFilter == kind
                let name = kind.plural.lowercased()
                let tip: String = on ? "Showing only \(name). Click to show everything (↑ ↓)" : "Show only \(name) (↑ ↓)"
                Button { model.kindFilter = on ? nil : kind } label: {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 11))
                        .frame(width: 24, height: 22)
                        .foregroundStyle(on ? .primary : .secondary)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.primary.opacity(0.12))
                                    .matchedGeometryEffect(id: "kind", in: pills)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tip)
            }
        }
        .animation(Motion.move(reduceMotion), value: model.kindFilter)
    }

    // MARK: Footer

    /// What the keys do for the selected card. Holding ⌘ lists the ⌘ shortcuts instead.
    private var footer: some View {
        HStack(spacing: 14) {
            ForEach(hints, id: \.self) { hint in
                HStack(spacing: 4) {
                    Text(hint.key).font(.system(size: 11, weight: .semibold))
                    Text(hint.label).font(.system(size: 11))
                }
                .fixedSize()
                .transition(.opacity)
            }
            Spacer(minLength: 12)
            styleButton
        }
        .animation(Motion.fade, value: hints)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(height: 20)
    }

    private var hints: [Hint] {
        if model.commandHeld {
            return [Hint("⌘1–9", "Paste"), Hint("⌘K", "Paste As…"), Hint("⌘R", "Copy as File…"), Hint("⌘C", "Copy"),
                    Hint("⌘P", "Pin"), Hint("⌘S", "Mark"), Hint("⌘E", "Edit · Markup"), Hint("⌘⌫", "Delete"), Hint("⌘Z", "Undo")]
        }
        if !model.stack.isEmpty {
            return [Hint("↩", "Paste \(model.stack.count) in order"), Hint("⌥↩", "All at once"), Hint("⌘J", "Join"),
                    Hint("⌘P", "Pin"), Hint("⌘⌫", "Delete"), Hint("⇧← →", "Mark more")]
        }
        guard let item = model.selected else { return [Hint("⇥", "Next tab"), Hint("↑↓", "Filter")] }
        if item.concealed { return [Hint("↩", "Paste password")] }
        var hints: [Hint] = []
        let isFileLike = item.kind == .image || item.kind == .file
        if item.formatted {
            hints.append(Hint("↩", model.plainByDefault ? "Paste as plain text" : "Paste with formatting"))
            hints.append(Hint("⇧↩", model.plainByDefault ? "With formatting" : "As plain text"))
        } else if isFileLike && model.askBeforePasting {
            hints.append(Hint("↩", "Paste…"))
            hints.append(Hint("⇧↩", "Paste original"))
        } else {
            hints.append(Hint("↩", "Paste"))
        }
        hints.append(Hint("⌘K", "Paste As…"))
        if item.canMarkup { hints.append(Hint("⌘E", "Markup")) }
        if isFileLike && !model.askBeforePasting { hints.append(Hint("⌘R", "Copy as File…")) }
        if model.query.isEmpty { hints.append(Hint("Space", "Preview")) }
        hints.append(Hint("↑↓", "Filter"))
        if model.canUndo { hints.append(Hint("⌘Z", "Undo delete")) }
        hints.append(Hint("⌘", "Hold for more"))
        return hints
    }

    /// What Return pastes in the app you're pasting into. Click to change it for that app.
    private var styleButton: some View {
        Button { model.actions?.showStyleMenu() } label: {
            HStack(spacing: 5) {
                if let icon = AppIcons.icon(for: model.target?.bundle) {
                    Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                }
                Text(styleLabel).font(.system(size: 11))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("What Return pastes in this app. ⇧Return pastes the other way.")
    }

    private var styleLabel: String {
        let style = model.plainByDefault ? "Plain Text" : "Formatted"
        guard let name = model.target?.name else { return "Paste: \(style)" }
        return "\(name): \(style)"
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            TabButton(title: "History", selected: model.tab == nil, namespace: pills) { model.tab = nil }
            ForEach(model.boards) { board in
                if model.naming == .rename(board.id) {
                    nameField
                } else {
                    TabButton(title: board.name, selected: model.tab == board.id, namespace: pills) { model.tab = board.id }
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
        .animation(Motion.move(reduceMotion), value: model.tab)
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
                LazyHStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        CardView(item: item, selected: index == model.selection, now: model.now,
                                 stackPosition: model.stack.firstIndex(of: item.id).map { $0 + 1 },
                                 shortcut: model.commandHeld && index < 9 ? index + 1 : nil,
                                 imageURL: model.actions?.imageURL(item))
                            .background {
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear {
                                            model.cardFrames[item.id] = geo.frame(in: .global)
                                            if index == model.selection { model.selectedCardMidX = geo.frame(in: .global).midX }
                                        }
                                        .onChange(of: geo.frame(in: .global)) {
                                            model.cardFrames[item.id] = geo.frame(in: .global)
                                            if index == model.selection { model.selectedCardMidX = geo.frame(in: .global).midX }
                                        }
                                        .onChange(of: index == model.selection) {
                                            if index == model.selection { model.selectedCardMidX = geo.frame(in: .global).midX }
                                        }
                                        .onDisappear { model.cardFrames[item.id] = nil }
                                }
                            }
                            .onTapGesture(count: 2) {
                                model.selection = index
                                // Next turn of the run loop, once the card's position is known.
                                DispatchQueue.main.async { model.actions?.pasteFromCard(item) }
                            }
                            .onTapGesture {
                                if NSEvent.modifierFlags.contains(.shift) { model.toggleStack(item) }   // ⇧-click marks
                                model.selection = index
                            }
                            .contextMenu { menu(item, index) }
                            .dragOut(item.draggable) { model.actions?.dragItem(item) ?? NSItemProvider() }
                            // The margins belong to each card, so scrolling to a card keeps them:
                            // 22 at the ends (like the rest of the shelf), 6 + 6 between cards.
                            .padding(.leading, index == 0 ? 22 : 6)
                            .padding(.trailing, index == list.count - 1 ? 22 : 6)
                            .id(item.id)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
                // Cards ease in and out as you search, filter, pin or delete.
                .animation(Motion.move(reduceMotion), value: list.map(\.id))
            }
            .onChange(of: model.selection) {
                guard let id = model.selected?.id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(id) }
            }
            .onChange(of: model.focusTick) {
                if let id = list.first?.id { proxy.scrollTo(id, anchor: .leading) }
            }
        }
    }

    @ViewBuilder private func menu(_ item: ClipItem, _ index: Int) -> some View {
        if item.concealed {
            Button("Paste") { model.actions?.paste(item, plain: false) }
        } else {
            itemMenu(item, index)
        }
    }

    @ViewBuilder private func itemMenu(_ item: ClipItem, _ index: Int) -> some View {
        Button("Paste") { model.actions?.paste(item, plain: model.plainByDefault) }
        if item.formatted {
            Button(model.plainByDefault ? "Paste with Formatting" : "Paste as Plain Text") {
                model.actions?.paste(item, plain: !model.plainByDefault)
            }
        }
        Menu("Paste As") {
            let sections = PasteOption.sections(for: item)
            ForEach(Array(sections.enumerated()), id: \.offset) { i, section in
                if i > 0 { Divider() }
                ForEach(section, id: \.self) { option in
                    Button(option.title) { model.actions?.pasteAs(item, option) }
                }
            }
        }
        Button("Copy") { model.actions?.copy(item) }
        Button("Copy as File…") { model.selection = index; model.actions?.startExport(item) }
        Divider()
        Button("Preview") { model.selection = index; if !model.previewing { model.actions?.togglePreview() } }
        if item.editable {
            Button("Edit…") { model.selection = index; model.actions?.edit(item) }
        }
        if item.canMarkup {
            Button("Markup…") { model.selection = index; model.actions?.markup(item) }
        }
        Button(model.stack.contains(item.id) ? "Remove from Paste Stack" : "Add to Paste Stack") { model.toggleStack(item) }
        Divider()
        Menu("Pin to") {
            ForEach(model.boards) { board in
                Button(board.name) { model.actions?.setBoard(item, board.id) }
            }
            Divider()
            Button("New Pinboard…") { model.pendingPins = [item.id]; model.startNaming(.new) }
        }
        if item.pinned {
            Button("Unpin") { model.actions?.setBoard(item, nil) }
        }
        Divider()
        if item.sourceBundle != nil {
            Button("Don't Record Copies from \(item.sourceName ?? "This App")") { model.actions?.ignoreApp(item) }
        }
        Button("Delete") { model.actions?.delete(item) }
    }

    private func status(_ list: [ClipItem]) -> String {
        if !model.stack.isEmpty {
            return "\(model.stack.count) in stack"
        }
        let count = list.filter { !$0.concealed }.count
        return count == 1 ? "1 item" : "\(count) items"
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: emptyText.symbol)
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(emptyText.title).font(.system(size: 13, weight: .medium))
            Text(emptyText.detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyText: (symbol: String, title: String, detail: String) {
        let only = model.kindFilter.map { " Showing only \($0.plural.lowercased()); ↑ ↓ shows other kinds." } ?? ""
        if !model.query.isEmpty {
            return ("magnifyingglass", "No matches for “\(model.query)”",
                    "Search looks in text, links, file names, app names, and text inside images. Try from:app or @today." + only)
        }
        if let kind = model.kindFilter {
            return (kind.symbol, "No \(kind.plural.lowercased()) here", "Press ↑ or ↓ to show other kinds, or click the icon again.")
        }
        if model.tab != nil {
            return ("pin", "Nothing pinned here yet", "Select a card and press ⌘P to pin it.")
        }
        return ("doc.on.clipboard", "Nothing copied yet", "Copy something with ⌘C and it shows up here.")
    }
}

private struct Hint: Hashable {
    let key: String
    let label: String

    init(_ key: String, _ label: String) {
        self.key = key
        self.label = label
    }
}

extension ClipKind {
    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    var plural: String {
        switch self {
        case .text: return "Text"
        case .link: return "Links"
        case .image: return "Images"
        case .file: return "Files"
        }
    }
}

extension ClipItem {
    /// An image, or a single image file: ⌘E opens it in Markup.
    var canMarkup: Bool {
        guard !concealed else { return false }
        if kind == .image { return true }
        return kind == .file && filePaths.count == 1 && FileExport.isImage(filePaths[0])
    }

    /// Can be dragged into other apps by SwiftUI, which carries one item. A card with several files
    /// (and several marked cards) is dragged by the shelf's panel instead.
    var draggable: Bool { !concealed && !(kind == .file && filePaths.count > 1) }

    /// A text card that is just a hex color, shown as a swatch.
    var color: ColorText.RGBA? { kind == .text ? ColorText.parse(text ?? "") : nil }
}

extension View {
    /// Lets a card be dragged out of the shelf into another app.
    @ViewBuilder func dragOut(_ enabled: Bool, _ provider: @escaping () -> NSItemProvider) -> some View {
        if enabled {
            onDrag(provider)
        } else {
            self
        }
    }
}

struct TabButton: View {
    let title: String
    let selected: Bool
    let namespace: Namespace.ID   // the selected tab's highlight slides between tabs
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.12))
                            .matchedGeometryEffect(id: "tab", in: namespace)
                    }
                }
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
    let shortcut: Int?          // 1…9 while ⌘ is held: ⌘ and that number pastes this card
    let imageURL: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .semibold))
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

            HStack(spacing: 6) {
                Text(footer).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if let stackPosition {
                    Text("Stack \(stackPosition)").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.accentColor)
                        .transition(.opacity)
                } else if item.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                if let shortcut {
                    Text("⌘\(shortcut)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .frame(width: 220, height: 220)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(selected ? 0.1 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(borderColor, lineWidth: selected || stackPosition != nil ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selected)
        .animation(Motion.fade, value: shortcut)
        .animation(Motion.fade, value: stackPosition)
        .animation(Motion.fade, value: item.pinned)
    }

    private var borderColor: Color {
        if selected { return .accentColor }
        if stackPosition != nil { return Color.accentColor.opacity(0.45) }
        return Color.primary.opacity(0.08)
    }

    @ViewBuilder private var content: some View {
        if item.concealed {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").font(.system(size: 15)).foregroundStyle(.secondary)
                    Text("••••••••••").font(.system(size: 16, weight: .medium)).foregroundStyle(.secondary)
                }
                Text("Not saved to history").font(.system(size: 12, weight: .medium))
                Text("It's on the clipboard until you copy something else.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        } else {
            kindContent
        }
    }

    /// "Report.pdf", or "Report.pdf and 2 more".
    private var fileNames: String {
        let names = item.filePaths.map { ($0 as NSString).lastPathComponent }
        guard let first = names.first else { return "" }
        return names.count == 1 ? first : "\(first) and \(names.count - 1) more"
    }

    /// A secret's kind ("AWS key"…) while it's waiting to be deleted.
    private var secretKind: String? {
        guard item.expires != nil, let text = item.text else { return nil }
        return SecretScanner.kind(of: text) ?? "Secret"
    }

    private var title: String {
        if item.concealed { return "Password" }
        if let secretKind { return secretKind }
        return item.color != nil ? "Color" : item.kind.title
    }

    @ViewBuilder private var kindContent: some View {
        if secretKind != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill").font(.system(size: 14)).foregroundStyle(.secondary)
                    Text(SecretScanner.masked(item.text ?? "")).font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("Kept for a few minutes").font(.system(size: 12, weight: .medium))
                Text("It looks like a key or password, so it's deleted soon. Pin it to keep it.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        } else {
            plainKindContent
        }
    }

    @ViewBuilder private var plainKindContent: some View {
        switch item.kind {
        case .text:
            if let color = item.color {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                    Text((item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 12, design: .monospaced))
                }
            } else {
                Text(String((item.text ?? "").prefix(800)))
                    .font(.system(size: 12))
                    .lineLimit(9)
            }
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
            VStack(alignment: .leading, spacing: 6) {
                FileThumbnail(path: item.filePaths.first ?? "", maxSize: 200)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(fileNames).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private var footer: String {
        if item.concealed { return "Return or ⌘V pastes it" }
        if let expires = item.expires, secretKind != nil {
            let minutes = max(1, Int((expires.timeIntervalSince(now) / 60).rounded(.up)))
            return minutes == 1 ? "Deleted in 1 minute" : "Deleted in \(minutes) minutes"
        }
        switch item.kind {
        case .text where item.color != nil:
            return "Hex color"
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

/// Several files in the preview, each with its Quick Look picture, name and folder.
struct FileList: View {
    let paths: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(paths, id: \.self) { path in
                HStack(spacing: 12) {
                    FileThumbnail(path: path, maxSize: 64)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 1) {
                        Text((path as NSString).lastPathComponent)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
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
        preview
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.selected?.concealed == true {
                Text("Passwords aren't shown or saved. Return or ⌘V pastes it.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let item = model.selected {
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
            if item.filePaths.count == 1, let path = item.filePaths.first, FileManager.default.fileExists(atPath: path) {
                QuickLookView(url: URL(fileURLWithPath: path))
            } else {
                ScrollView {
                    FileList(paths: item.filePaths)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
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
        if model.editing {
            return "⌘Return paste · ⇧⌘Return \(model.plainByDefault ? "formatted" : "plain") · Esc cancel"
        }
        return item.editable ? "⌘E edit · ⌘K paste as · Space close" : "⌘K paste as · Space close"
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
