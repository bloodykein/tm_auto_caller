// excel_service.dart - v4: includes retry count, grade, multi-result
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/tm_models.dart';

class ExcelService {
  Future<void> exportSession(TMSession session) async {
    final excel = Excel.createExcel();

    // ── Sheet 1: 상세 결과 ────────────────────────
    final sheet1 = excel['통화결과'];
    _addRow(sheet1, [
      '순번', '이름', '전화번호',
      '통화결과', '고객평가',
      '메모', '통화시작시간', '통화시간(초)',
      '완료여부', '재시도횟수',
    ]);

    for (var i = 0; i < session.contacts.length; i++) {
      final c = session.contacts[i];
      _addRow(sheet1, [
        i + 1,
        c.name,
        c.phone,
        c.resultCodes.map(ResultCode.label).join(', '),
        c.customerGrade != null ? '${c.customerGrade} · ${CustomerGrade.label(c.customerGrade!)}' : '',
        c.memo,
        c.callStartTime?.toString().substring(0, 19) ?? '',
        c.callDuration,
        c.isCompleted ? '완료' : (c.isSkipped ? '건너뜀' : '재시도대기'),
        c.retryCount,
      ]);
    }

    // ── Sheet 2: 요약 통계 ────────────────────────
    final sheet2 = excel['요약'];
    _addRow(sheet2, ['항목', '값']);
    _addRow(sheet2, ['세션명', session.name]);
    _addRow(sheet2, ['실시일시', session.createdAt.toString().substring(0, 19)]);
    _addRow(sheet2, ['총 연락처', session.totalContacts]);
    _addRow(sheet2, ['완료', session.completedCount]);
    _addRow(sheet2, ['재시도 대기', session.retryContacts.length]);
    _addRow(sheet2, ['건너뜀', session.contacts.where((c) => c.isSkipped).length]);
    _addRow(sheet2, ['', '']);
    _addRow(sheet2, ['결과코드', '건수']);

    final stats = session.resultStats;
    for (final e in stats.entries) {
      _addRow(sheet2, [ResultCode.label(e.key), e.value]);
    }

    _addRow(sheet2, ['', '']);
    _addRow(sheet2, ['고객평가', '건수']);
    final gradeStats = session.gradeStats;
    for (final g in ['A', 'B', 'C']) {
      _addRow(sheet2, ['$g · ${CustomerGrade.label(g)}', gradeStats[g] ?? 0]);
    }

    // 파일 저장
    final bytes = excel.encode()!;
    final dir = await _getDownloadDir();
    final fileName = 'TM_${session.name}_${_timestamp()}.xlsx';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);

    // 공유
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'TM 결과 - ${session.name}',
    );
  }

  void _addRow(Sheet sheet, List<dynamic> values) {
    final row = sheet.maxRows;
    for (var i = 0; i < values.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
          .value = TextCellValue(values[i].toString());
    }
  }

  Future<Directory> _getDownloadDir() async {
    Directory dir;
    try {
      dir = Directory('/storage/emulated/0/Download/TM앱');
    } catch (_) {
      dir = await getApplicationDocumentsDirectory();
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }
}
