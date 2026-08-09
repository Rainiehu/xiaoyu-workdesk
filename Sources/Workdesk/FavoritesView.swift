import SwiftUI
import WorkdeskCore

struct FavoritesView: View {
    @Environment(Store.self) private var store
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("收藏流")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                HStack(spacing: 10) {
                    Image(systemName: "bookmark.circle.fill")
                        .foregroundStyle(.pink.opacity(0.8))
                        .imageScale(.large)
                    TextField("粘贴链接或输入一段文字，回车收藏…", text: $draft)
                        .textFieldStyle(.plain)
                        .focused($inputFocused)
                        .onSubmit {
                            store.addFavorite(draft)
                            draft = ""
                            inputFocused = true
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))

                if store.favorites.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 36))
                            .foregroundStyle(.pink.opacity(0.5))
                        Text("收藏的链接和灵感会汇成一条流")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }

                LazyVStack(spacing: 10) {
                    ForEach(store.favorites.reversed()) { item in
                        // 删除态的卡是原位占位：撤销窗口开着的那几秒它还站在这儿，见 ADR-0007。
                        if item.isDeleted {
                            DeletedFavoriteCard(item: item)
                        } else {
                            FavoriteCard(item: item)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// 原位占位：刚删掉的收藏在流里原来的位置上留下的口子，撤销窗口开着的那几秒里
/// 点撤销就回来 —— 与待办行、分类 tab 的占位同一副分寸，见 ADR-0007。
/// 卡片的形状留着（同宽同圆角），里头只剩一句话和撤销：占位说明这儿少了什么，不复述内容。
private struct DeletedFavoriteCard: View {
    @Environment(Store.self) private var store
    let item: FavoriteItem

    var body: some View {
        HStack(spacing: 12) {
            Text("已删除「\(item.title)」")
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
            Button("撤销") { withAnimation { store.undeleteFavorite(item.id) } }
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .foregroundStyle(.teal)
                .help("撤销删除")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.quaternary.opacity(0.35))
        )
    }
}

struct FavoriteCard: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    let item: FavoriteItem
    @State private var hovering = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.url != nil ? "link" : "text.quote")
                .foregroundStyle(item.url != nil ? .blue : .orange)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.quaternary.opacity(0.5)))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(3)
                HStack(spacing: 8) {
                    if let domain = item.domain {
                        Text(domain)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.blue.opacity(0.1)))
                            .foregroundStyle(.blue)
                    }
                    Text(Self.timeFormatter.string(from: item.createdAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if hovering {
                if let url = item.url {
                    Button { openURL(url) } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("打开链接")
                }
                Button {
                    withAnimation { store.deleteFavorite(item) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("删除")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(hovering ? 0.08 : 0.04), radius: hovering ? 6 : 3, y: 1)
        )
        .onHover { hovering = $0 }
        .onTapGesture {
            if let url = item.url { openURL(url) }
        }
    }
}
