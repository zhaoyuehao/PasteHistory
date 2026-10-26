import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: ClipStore
    /// 由 PanelController 持有并传入：预览大窗要跟着选中条目联动，
    /// 共享同一个 ViewModel 比通知转发少一层状态
    @ObservedObject private var model: HistoryViewModel
    @ObservedObject private var presentationState: HistoryPresentationState
    @FocusState private var searchFocused: Bool
    @State private var treeRoot = CGPoint.zero
    private var layoutEditing: Bool { presentationState.treeLayoutEditing }

    var onPaste: (ClipItem) -> Void
    var onCopyOnly: (ClipItem) -> Void
    var onClose: () -> Void
    var onPreview: () -> Void

    init(store: ClipStore,
         model: HistoryViewModel,
         presentation: HistoryPresentationState = HistoryPresentationState(),
         onPaste: @escaping (ClipItem) -> Void,
         onCopyOnly: @escaping (ClipItem) -> Void,
         onClose: @escaping () -> Void,
         onPreview: @escaping () -> Void) {
        self.store = store
        self.model = model
        self.presentationState = presentation
        self.onPaste = onPaste
        self.onCopyOnly = onCopyOnly
        self.onClose = onClose
        self.onPreview = onPreview
    }

    private var results: [ClipItem] { model.results }
    private var safeSelection: Int { model.safeSelection }

    private var presentation: some View {
        treeContent
            .frame(minWidth: 340, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
            .ignoresSafeArea()
            .onAppear {
                DispatchQueue.main.async { searchFocused = true }
                model.rebuildResults()
            }
    }

    var body: some View {
        presentation
        .onChange(of: presentationState.treeLayoutEditing) { _, editing in
            if !editing { searchFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .phMoveDown)) { _ in model.move(1) }
        .onReceive(NotificationCenter.default.publisher(for: .phMoveUp)) { _ in model.move(-1) }
        .onReceive(NotificationCenter.default.publisher(for: .phPageDown)) { _ in model.move(IvoryTreeLayout.pageSize) }
        .onReceive(NotificationCenter.default.publisher(for: .phPageUp)) { _ in model.move(-IvoryTreeLayout.pageSize) }
        .onReceive(NotificationCenter.default.publisher(for: .phConfirm)) { _ in
            guard let item = current else { return }
            onPaste(item)
        }
        .onReceive(NotificationCenter.default.publisher(for: .phCopyOnly)) { _ in
            guard let item = current else { return }
            onCopyOnly(item)
        }
        .onReceive(NotificationCenter.default.publisher(for: .phDelete)) { _ in
            guard current != nil else { return }
            model.deleteCurrent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .phPin)) { _ in
            guard current != nil else { return }
            model.togglePinCurrent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .phClose)) { _ in onClose() }
        // 每次打开面板都是一次新的「找」：回到第一条
        .onReceive(NotificationCenter.default.publisher(for: .phPanelWillShow)) { _ in
            model.resetForPresentation()
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .phQuickPaste)) { note in
            guard let index = note.object as? Int, index < results.count else { return }
            onPaste(results[index])
        }
        .onChange(of: store.query) { _, _ in model.resetSelection() }
        .onChange(of: store.displayed) { _, _ in model.rebuildResults() }
    }

    private var current: ClipItem? { model.current }

    private var treeContent: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                IvoryTreeView(model: model, onPreview: onPreview, layoutEditing: layoutEditing, onRootPosition: { treeRoot = $0 })
                if !layoutEditing {
                    Rectangle().fill(Color(red: 0.76, green: 0.72, blue: 0.62))
                        .frame(width: 1, height: 14)
                        .position(x: treeRoot == .zero ? geometry.size.width/2 : treeRoot.x,
                                  y: (treeRoot == .zero ? geometry.size.height-112 : treeRoot.y)+7)
                    TreeControlPortal(role: .search) { desktopSearch }
                    .frame(width: 116, height: 92)
                    .position(x: treeRoot == .zero ? geometry.size.width/2 : treeRoot.x,
                              y: min(geometry.size.height-46, (treeRoot == .zero ? geometry.size.height-112 : treeRoot.y)+64))
                } else {
                    TreeControlPortal(role: .layout) { layoutControls }
                        .frame(width: 310, height: 42)
                        .position(x: geometry.size.width/2, y: geometry.size.height-28)
                }
            }
        }
        .transition(Motion.reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
    }

    private var layoutControls: some View {
        HStack(spacing: 10) {
            TreeMoveHandle().frame(width: 65, height: 30)
            ForEach(Array(zip(["小", "标准", "大"], [0.82, 1.0, 1.14])), id: \.0) { title, size in
                Button(title) { NotificationCenter.default.post(name: .phTreeSize, object: size) }
                    .buttonStyle(.plain)
            }
            Button("完成") { NotificationCenter.default.post(name: .phFinishTreeLayout, object: nil) }
                .buttonStyle(.borderedProminent)
        }
        .font(.system(size: 13))
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var desktopSearch: some View {
        VStack(spacing: 4) {
            VStack(spacing: 4) {
                Circle().fill(Color.black.opacity(0.4)).frame(width: 3.5, height: 3.5)
                Image(systemName: "magnifyingglass").font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.43, green: 0.41, blue: 0.36))
                TextField("", text: $store.query)
                    .lineLimit(1)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center)
                    .focused($searchFocused)
                    .accessibilityLabel(L10n.search)
                    .help("输入搜索 · 空格预览 · Shift+空格输入空格")
                    .frame(height: 25)
                Text(store.matchCount == 0 ? "0 / 0" : "\(safeSelection / IvoryTreeLayout.pageSize + 1) / \((store.matchCount + IvoryTreeLayout.pageSize - 1) / IvoryTreeLayout.pageSize) · \(store.matchCount)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color(red: 0.39, green: 0.37, blue: 0.32))
                    .padding(.top, 2)
            }
            .foregroundStyle(Color(red: 0.19, green: 0.18, blue: 0.16))
            .padding(.horizontal, 10).padding(.top, 5).padding(.bottom, 9)
            .frame(width: 116)
            .background(Color(red: 0.93, green: 0.91, blue: 0.85), in: RootSearchTag())
            .shadow(color: .black.opacity(0.18), radius: 5, x: 1, y: 3)
        }
        .frame(width: 116)
    }

}

/// Clipped shoulders and a punched hole make search part of the hanging paper family.
private struct RootSearchTag: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 12, y: 0)); p.addLine(to: CGPoint(x: rect.width-12, y: 0))
            p.addLine(to: CGPoint(x: rect.width, y: 12)); p.addLine(to: CGPoint(x: rect.width, y: rect.height))
            p.addLine(to: CGPoint(x: 0, y: rect.height)); p.addLine(to: CGPoint(x: 0, y: 12)); p.closeSubpath()
        }
    }
}
