import CoreTransferable
import UniformTypeIdentifiers

/// 拖着一条待办走时递过去的东西：它的身份，仅此而已。
/// 只带 id 不带整条待办 —— 落下时按 id 现找现改，途中它被打了勾或被删了，也不会有旧副本被写回去。
///
/// 三处拖拽共用它，于是「抓起一条待办」在哪儿都是同一件事：沙漏视图里拖到别的日期分组上是改期，
/// 分类视图左列里拖到另一行上是换位置，拖到 tab 栏另一个分类上是改归属。
/// 落下时发生什么由接住的那一方定，抓起的这一头不知道也不必知道。
///
/// 类型是自家的，于是从别处拖来的文字、链接一律接不住；反过来，从这儿拖出去的东西
/// 别的应用也接不住 —— 这些手势只在这个应用里成立。
struct DraggedTodo: Codable, Transferable {
    var id: TodoItem.ID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .workdeskTodo)
    }
}

extension UTType {
    /// 只有这个应用自己拖出来的待办认得这个类型。与 `build.sh` 里 Info.plist 的
    /// `UTExportedTypeDeclarations` 是同一个标识符，两边要一起改。
    static let workdeskTodo = UTType(exportedAs: "cc.huxiaoyu.workdesk.todo")
}
