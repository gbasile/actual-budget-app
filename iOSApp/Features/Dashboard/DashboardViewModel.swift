import SwiftUI
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var accounts: [Account] = []
    @Published var categoriesById: [String: String] = [:]
    @Published var payeesById: [String: Payee] = [:]
    @Published var transactions: [Transaction] = []
    @Published var errorMessage: String?
    @Published var activeSheet: SheetType?

    // MARK: - Dependencies
    private let appState: AppState

    // MARK: - Computed Properties
    var onBudgetAccounts: [Account] {
        accounts.filter { !$0.offbudget }
    }

    var recentFive: [Transaction] {
        Array(recentNonTransferOnBudget().prefix(5))
    }

    var onBudgetAccountsCount: Int {
        onBudgetAccounts.count
    }

    var hasRecentTransactions: Bool {
        !recentFive.isEmpty
    }

    // MARK: - Formatted Values for Presentation
    var spentTodayFormatted: String {
        formatMoney(spentToday())
    }

    var spentThisMonthFormatted: String {
        formatMoney(spentThisMonth())
    }

    var spentLastMonthFormatted: String {
        formatMoney(spentLastMonth())
    }

    // MARK: - Initialization
    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Public Methods
    func load() async {
        do {
            async let accs = try client().fetchAccounts()
            async let cats = try client().fetchCategories()
            async let payees = try client().fetchPayees()
            let (accList, catList, payeeList) = try await (accs, cats, payees)
            let since = firstOfThisMonthMinus(days: 31)
            let txs = try await withThrowingTaskGroup(of: [Transaction].self) { group -> [[Transaction]] in
                for acc in accList {
                    group.addTask { try await self.client().fetchTransactions(accountId: acc.id, since: since) }
                }
                var results: [[Transaction]] = []
                for try await list in group {
                    results.append(list)
                }
                return results
            }

            accounts = accList
            transactions = txs.flatMap { $0 }
            categoriesById = Dictionary(uniqueKeysWithValues: catList.map { ($0.id, $0.name) })
            payeesById = Dictionary(uniqueKeysWithValues: payeeList.map { ($0.id, $0) })

            // Update shared data
            SharedDataManager.shared.save(spentToday: spentToday(), currencyCode: appState.currencyCode)
        } catch {
            AppLogger.shared.log(error: error, context: "DashboardViewModel.load")
            errorMessage = error.localizedDescription
        }
    }

    func deleteTransaction(_ tx: Transaction) async {
        guard let txId = tx.id else { return }

        // Optimistically remove from local list
        transactions.removeAll { $0.id == txId }

        do {
            try await client().deleteTransaction(transactionId: txId)
        } catch {
            AppLogger.shared.log(error: error, context: "DashboardViewModel.deleteTransaction")
            errorMessage = error.localizedDescription
        }
    }

    func showAddSheet() {
        activeSheet = .add
    }

    func showEditSheet(for transaction: Transaction) {
        activeSheet = .edit(transaction)
    }

    func dismissSheet() {
        activeSheet = nil
    }

    // MARK: - Calculations
    func spentToday() -> Int {
        let today = format(date: Date())
        let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
        let todays = transactions.filter {
            $0.date == today && onBudgetIds.contains($0.account) && !isTransfer($0)
        }
        return -todays.map { $0.amount ?? 0 }.filter { $0 < 0 }.reduce(0, +)
    }

    func spentThisMonth() -> Int {
        let (start, end) = monthRange(date: Date())
        let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
        let list = transactions.filter {
            $0.date >= start && $0.date <= end && onBudgetIds.contains($0.account) && !isTransfer($0)
        }
        return -list.map { $0.amount ?? 0 }.filter { $0 < 0 }.reduce(0, +)
    }

    func spentLastMonth() -> Int {
        let cal = Calendar(identifier: .gregorian)
        let lastMonthDate = cal.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let (start, end) = monthRange(date: lastMonthDate)
        let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
        let list = transactions.filter {
            $0.date >= start && $0.date <= end && onBudgetIds.contains($0.account) && !isTransfer($0)
        }
        return -list.map { $0.amount ?? 0 }.filter { $0 < 0 }.reduce(0, +)
    }

    func payeeText(for transaction: Transaction) -> String {
        if let payeeId = transaction.payee, let p = payeesById[payeeId] {
            return p.name
        }
        if let n = transaction.payee_name, !n.isEmpty {
            return n
        }
        return "(No payee)"
    }

    func formattedAmount(for transaction: Transaction) -> String {
        formatMoney(abs(transaction.amount ?? 0))
    }

    private func formatMoney(_ amount: Int) -> String {
        return CurrencyFormatter.shared.format(amount, currencyCode: appState.currencyCode)
    }

    // MARK: - Private Helper Methods
    private func client() throws -> ActualAPIClient {
        try ActualAPIClient(
            baseURLString: appState.baseURLString,
            apiKey: appState.apiKey,
            syncId: appState.syncId,
            budgetEncryptionPassword: appState.budgetEncryptionPassword,
            isDemoMode: appState.isDemoMode
        )
    }

    private func isTransfer(_ tx: Transaction) -> Bool {
        if tx.transfer_id != nil { return true }
        if let payeeId = tx.payee, let p = payeesById[payeeId], p.transfer_acct != nil {
            return true
        }
        return false
    }

    private func recentNonTransferOnBudget() -> [Transaction] {
        let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
        return transactions
            .filter { onBudgetIds.contains($0.account) && !isTransfer($0) }
            .sorted { $0.date > $1.date }
    }

    private func monthRange(date: Date) -> (String, String) {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month], from: date)
        let startDate = cal.date(from: comps) ?? date
        let endDate = cal.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) ?? date
        return (format(date: startDate), format(date: endDate))
    }

    private func firstOfThisMonthMinus(days: Int) -> String {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month], from: Date())
        let start = cal.date(from: comps) ?? Date()
        let since = cal.date(byAdding: .day, value: -days, to: start) ?? start
        return format(date: since)
    }

    private func format(date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
