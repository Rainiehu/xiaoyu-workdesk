/// 删分类被拦下时说的那两句话。两端的 alert 逐字同款，只此一份 —— 数字由 `Store` 交回来，
/// 这儿只把话说清楚：待办的疏通路子是移走或删掉，小标题只能删掉（它换不了分类），
/// 所以两样分开说，没有的那样不提。
public enum CategoryDeletionRefusal {
    public static func title(categoryName: String, todoCount: Int) -> String {
        todoCount > 0 ? "「\(categoryName)」里还有待办" : "「\(categoryName)」里还有小标题"
    }

    public static func message(todoCount: Int, headingCount: Int) -> String {
        if headingCount == 0 {
            return "先把这 \(todoCount) 条待办移到别的分类，或者删掉，再来删这个分类。"
        }
        if todoCount == 0 {
            return "先把这 \(headingCount) 个小标题删掉，再来删这个分类。"
        }
        return "先把这 \(todoCount) 条待办移到别的分类或者删掉，再删掉这 \(headingCount) 个小标题，然后再来删这个分类。"
    }
}
