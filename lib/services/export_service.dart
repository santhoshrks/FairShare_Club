import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/member_model.dart';
import '../models/contribution_model.dart';
import '../models/wallet_transaction_model.dart';
import '../utils/helpers.dart';
import '../utils/constants.dart';

class ExportService {
  Future<void> exportGroupAsPdf({
    required GroupModel group,
    required List<MemberModel> members,
    required List<ExpenseModel> expenses,
    List<ContributionModel>? contributions,
    List<WalletTransactionModel>? walletTransactions,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            // Header
            pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('00897B'),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              padding: const pw.EdgeInsets.all(16),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'FairShare Club',
                        style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.Text(
                        'Group Expense Summary',
                        style: const pw.TextStyle(
                          fontSize: 12,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                  pw.Text(
                    group.name,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Group Info
            pw.Text(
              'Group Details',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              children: [
                _buildTableRow('Group Name', group.name),
                _buildTableRow('Type', AppConstants.groupTypeLabel(group.type)),
                _buildTableRow('Members', '${members.length}'),
                _buildTableRow(
                    'Generated On', Helpers.formatDate(DateTime.now())),
              ],
            ),
            pw.SizedBox(height: 20),

            // Members
            pw.Text(
              'Members',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            ...members.map(
              (m) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Text('• ${m.name}${m.phone.isNotEmpty ? ' (${m.phone})' : ''}'),
              ),
            ),
            pw.SizedBox(height: 20),

            // Expenses
            if (expenses.isNotEmpty) ...[
              pw.Text(
                'Expenses',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: ['Date', 'Description', 'Amount', 'Paid By'],
                data: expenses.map((e) {
                  final payer = members.firstWhere(
                    (m) => m.id == e.paidByMemberId,
                    orElse: () => MemberModel(
                        id: '', name: 'Unknown', colorHex: 'FF000000', createdAt: DateTime.now()),
                  );
                  return [
                    Helpers.formatDate(e.date),
                    e.description,
                    Helpers.formatCurrency(e.amount),
                    payer.name,
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('00897B'),
                ),
                cellAlignment: pw.Alignment.centerLeft,
              ),
              pw.SizedBox(height: 8),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'Total: ${Helpers.formatCurrency(expenses.fold(0.0, (sum, e) => sum + e.amount))}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 20),
            ],

            // Contributions (for pool fund)
            if (contributions != null && contributions.isNotEmpty) ...[
              pw.Text(
                'Contributions',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: ['Date', 'Member', 'Amount', 'Note'],
                data: contributions.map((c) {
                  final member = members.firstWhere(
                    (m) => m.id == c.memberId,
                    orElse: () => MemberModel(
                        id: '', name: 'Unknown', colorHex: 'FF000000', createdAt: DateTime.now()),
                  );
                  return [
                    Helpers.formatDate(c.date),
                    member.name,
                    Helpers.formatCurrency(c.amount),
                    c.note,
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('00897B'),
                ),
              ),
              pw.SizedBox(height: 20),
            ],

            // Footer
            pw.Divider(),
            pw.Center(
              child: pw.Text(
                'Generated by FairShare Club App',
                style: const pw.TextStyle(color: PdfColors.grey, fontSize: 10),
              ),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  pw.TableRow _buildTableRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Text(label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Text(value),
        ),
      ],
    );
  }

  Future<void> shareGroupSummary({
    required GroupModel group,
    required List<MemberModel> members,
    required List<ExpenseModel> expenses,
    Map<String, double>? balances,
  }) async {
    final sb = StringBuffer();
    sb.writeln('📱 FairShare Club - Group Summary');
    sb.writeln('=' * 30);
    sb.writeln('Group: ${group.name}');
    sb.writeln('Type: ${AppConstants.groupTypeLabel(group.type)}');
    sb.writeln('Members: ${members.map((m) => m.name).join(', ')}');
    sb.writeln('');

    if (expenses.isNotEmpty) {
      sb.writeln('💸 Expenses (${expenses.length} total):');
      final total = expenses.fold(0.0, (sum, e) => sum + e.amount);
      for (final expense in expenses.take(10)) {
        final payer = members.firstWhere(
          (m) => m.id == expense.paidByMemberId,
          orElse: () => MemberModel(
              id: '', name: 'Unknown', colorHex: 'FF000000', createdAt: DateTime.now()),
        );
        sb.writeln(
            '  • ${expense.description}: ${Helpers.formatCurrency(expense.amount)} (paid by ${payer.name})');
      }
      if (expenses.length > 10) sb.writeln('  ... and ${expenses.length - 10} more');
      sb.writeln('Total Spent: ${Helpers.formatCurrency(total)}');
      sb.writeln('');
    }

    if (balances != null && balances.isNotEmpty) {
      sb.writeln('💰 Balances:');
      balances.forEach((memberId, balance) {
        final member = members.firstWhere(
          (m) => m.id == memberId,
          orElse: () => MemberModel(
              id: memberId, name: 'Unknown', colorHex: 'FF000000', createdAt: DateTime.now()),
        );
        final sign = balance >= 0 ? '+' : '';
        sb.writeln('  ${member.name}: $sign${Helpers.formatCurrency(balance)}');
      });
    }

    sb.writeln('');
    sb.writeln('Shared via FairShare Club App 🤝');

    await Share.share(sb.toString(), subject: 'FairShare Club - ${group.name} Summary');
  }
}

