import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: DashboardViewModel

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(appState: appState))
    }

    var body: some View {
        ZStack {
            AppBackground()
            List {
                Section {
                    VStack(spacing: 24) {
                        Text("Overview")
                            .font(AppTheme.Fonts.largeTitle)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top)

                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Spent This Month")
                                    .font(AppTheme.Fonts.body)
                                    .foregroundStyle(.secondary)
                                Text(viewModel.spentThisMonthFormatted)
                                    .font(AppTheme.Fonts.title)
                                    .foregroundColor(.primary)
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                metricCard(title: "Spent Today", value: viewModel.spentTodayFormatted)
                                metricCard(title: "Spent Last Month", value: viewModel.spentLastMonthFormatted)
                                metricCard(title: "On-budget Accounts", value: "\(viewModel.onBudgetAccountsCount)")
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section(header:
                    HStack {
                        Text("Recent Activity")
                            .font(AppTheme.Fonts.title)
                            .foregroundColor(.primary)
                        Spacer()
                        NavigationLink("View All") { AllTransactionsView() }
                            .foregroundColor(AppTheme.accent)
                    }
                ) {
                    if viewModel.recentFive.isEmpty {
                        GlassCard {
                            Text("No recent transactions to show.")
                                .font(AppTheme.Fonts.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 100)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(viewModel.recentFive, id: \.id) { tx in
                            TransactionRow(
                                transaction: tx,
                                accounts: viewModel.accounts,
                                payeesById: viewModel.payeesById,
                                categoriesById: viewModel.categoriesById,
                                currencyCode: appState.currencyCode,
                                onEdit: { t in viewModel.showEditSheet(for: t) },
                                onDelete: { t in Task { await viewModel.deleteTransaction(t) } }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    Button {
                        viewModel.showAddSheet()
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Transaction")
                        }
                        .font(AppTheme.Fonts.headline)
                        .foregroundColor(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationBarHidden(true)
        .task { await viewModel.load() }
        .sheet(item: $viewModel.activeSheet) { sheetType in
            switch sheetType {
            case .add:
                TransactionEditor(transaction: nil, initialAccountId: nil, onSave: { _ in Task { await viewModel.load() } })
            case .edit(let transaction):
                TransactionEditor(transaction: transaction, initialAccountId: nil, onSave: { _ in Task { await viewModel.load() } })
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil), actions: {
            Button("OK") { viewModel.errorMessage = nil }
            Button("View Logs") {
                AppLogger.shared.log("User tapped View Logs from Dashboard error", level: .info, context: "DashboardView")
                viewModel.errorMessage = nil
                NotificationCenter.default.post(name: NSNotification.Name("OpenLogsView"), object: nil)
            }
        }, message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        })
    }

    private func metricCard(title: String, value: String) -> some View {
        GlassCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTheme.Fonts.footnote)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(AppTheme.Fonts.subtitle)
                    .foregroundColor(.primary)
            }
            .frame(width: 140, alignment: .leading)
        }
    }
}