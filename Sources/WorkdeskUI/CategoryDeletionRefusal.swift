/// 删分类被拦下时说的那两句话。两端的 alert 逐字同款，只此一份 —— 数字由 `Store` 交回来，
/// 这儿只把话说清楚：待办的疏通路子是移走或删掉，小标题只能删掉（它换不了分类），
/// 所以两样分开说，没有的那样不提。
public enum CategoryDeletionRefusal {
    public static func title(categoryName: String, todoCount: Int) -> String {
        todoCount > 0 ? "「\(categoryName)」里还有待办" : "「\(categoryName)」里还有小标题"
    }

    /// 末尾补一句归档：多半人想删的是一个告一段落的分类，要的只是它别再占着 tab 栏 ——
    /// 那条路不必先清空，见 ADR-0010。已经归档了的就不再提。
    public static func message(todoCount: Int, headingCount: Int, isArchived: Bool = false) -> String {
        let clearing: String
        if headingCount == 0 {
            clearing = "先把这 \(todoCount) 条待办移到别的分类，或者删掉，再来删这个分类。"
        } else if todoCount == 0 {
            clearing = "先把这 \(headingCount) 个小标题删掉，再来删这个分类。"
        } else {
            clearing = "先把这 \(todoCount) 条待办移到别的分类或者删掉，再删掉这 \(headingCount) 个小标题，然后再来删这个分类。"
        }
        return isArchived ? clearing : clearing + "只是不想让它占着 tab 栏，可以归档。"
    }
}
