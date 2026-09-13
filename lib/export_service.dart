import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models.dart';

class ExportService {
  Future<Directory> _exportDirectory(Trip trip, Directory root) async {
    final dir = Directory(
      '${root.path}${Platform.pathSeparator}exports${Platform.pathSeparator}${_safe(trip.title)}',
    );
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> exportPdf({
    required Trip trip,
    required List<Expense> expenses,
    required Directory root,
    bool includeReport = true,
    bool includeReceipts = true,
  }) async {
    final doc = pw.Document(title: trip.title, author: '我的报销');
    final font = await _loadChineseFont();
    final style = pw.TextStyle(font: font);
    if (includeReport) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: font),
          build: (context) => [
            pw.Text(
              '费用报销明细',
              style: style.copyWith(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text('出差批次：${trip.title}', style: style),
            pw.Text(
              '目的地：${trip.destination.isEmpty ? '未填写' : trip.destination}',
              style: style,
            ),
            pw.Text(
              '出差事由：${trip.reason.isEmpty ? '未填写' : trip.reason}',
              style: style,
            ),
            pw.SizedBox(height: 14),
            pw.TableHelper.fromTextArray(
              headers: ['编号', '日期', '类型', '用途', '申请金额'],
              data: [
                for (var index = 0; index < expenses.length; index++)
                  [
                    '${index + 1}'.padLeft(2, '0'),
                    _date(expenses[index].occurredAt),
                    expenses[index].category,
                    expenses[index].purpose,
                    _money(expenses[index].claimCents),
                  ],
              ],
              headerStyle: pw.TextStyle(
                font: font,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              cellStyle: pw.TextStyle(font: font, fontSize: 9),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey800,
              ),
              border: pw.TableBorder.all(color: PdfColors.grey500, width: .5),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(5),
            ),
            pw.SizedBox(height: 12),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                '申请合计：${_money(expenses.fold(0, (sum, item) => sum + item.claimCents))}',
                style: style.copyWith(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (includeReceipts) {
      for (var index = 0; index < expenses.length; index++) {
        final expense = expenses[index];
        final children = <pw.Widget>[
          pw.Text(
            '${(index + 1).toString().padLeft(2, '0')}  ${_date(expense.occurredAt)}  ${expense.category}',
            style: style.copyWith(fontSize: 17, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${expense.purpose}    ${_money(expense.claimCents)}',
            style: style,
          ),
          if (expense.merchant.isNotEmpty)
            pw.Text('商户：${expense.merchant}', style: style),
          pw.SizedBox(height: 10),
        ];
        for (final attachment in expense.attachments) {
          final file = File(attachment.path);
          if (!await file.exists()) continue;
          final bytes = await file.readAsBytes();
          children.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              alignment: pw.Alignment.center,
              child: pw.Image(
                pw.MemoryImage(bytes),
                fit: pw.BoxFit.contain,
                height: 620,
              ),
            ),
          );
        }
        if (expense.attachments.isEmpty) {
          children.add(
            pw.Text('未添加图片附件', style: style.copyWith(color: PdfColors.red)),
          );
        }
        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            theme: pw.ThemeData.withFont(base: font),
            build: (_) => children,
          ),
        );
      }
    }
    final directory = await _exportDirectory(trip, root);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${_safe(trip.title)}_${_stamp()}.pdf',
    );
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  Future<File> exportDocx({
    required Trip trip,
    required List<Expense> expenses,
    required Directory root,
  }) async {
    final archive = Archive();
    final media = <String>[];
    final relationships = StringBuffer(
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">''',
    );
    final body = StringBuffer(
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>''',
    );
    _paragraph(body, '费用报销图片凭证', bold: true, size: 32);
    _paragraph(body, '出差批次：${trip.title}');
    _paragraph(
      body,
      '目的地：${trip.destination.isEmpty ? '未填写' : trip.destination}',
    );
    for (var index = 0; index < expenses.length; index++) {
      final expense = expenses[index];
      _paragraph(
        body,
        '${(index + 1).toString().padLeft(2, '0')}  ${_date(expense.occurredAt)}  ${expense.category}  ${_money(expense.claimCents)}',
        bold: true,
      );
      _paragraph(body, expense.purpose);
      for (final attachment in expense.attachments) {
        final file = File(attachment.path);
        if (!await file.exists()) continue;
        final name = 'image${media.length + 1}.${_extension(file.path)}';
        final rid = 'rId${media.length + 1}';
        media.add(name);
        archive.addFile(
          ArchiveFile(
            'word/media/$name',
            (await file.length()),
            await file.readAsBytes(),
          ),
        );
        relationships.write(
          '<Relationship Id="$rid" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/$name"/>',
        );
        body.write(_imageParagraph(rid));
      }
      _pageBreak(body);
    }
    body.write(
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1000" w:right="1000" w:bottom="1000" w:left="1000"/></w:sectPr></w:body></w:document>',
    );
    relationships.write('</Relationships>');
    _addTextFile(
      archive,
      '[Content_Types].xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpg" ContentType="image/jpeg"/><Default Extension="png" ContentType="image/png"/><Default Extension="webp" ContentType="image/webp"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>''',
    );
    _addTextFile(
      archive,
      '_rels/.rels',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>''',
    );
    _addTextFile(archive, 'word/document.xml', body.toString());
    _addTextFile(
      archive,
      'word/_rels/document.xml.rels',
      relationships.toString(),
    );
    final bytes = ZipEncoder().encode(archive);
    final directory = await _exportDirectory(trip, root);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${_safe(trip.title)}_${_stamp()}.docx',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File> exportXlsx({
    required Trip trip,
    required List<Expense> expenses,
    required Directory root,
    String employeeName = '',
    String department = '',
  }) async {
    try {
      return await _exportTemplateXlsx(
        trip: trip,
        expenses: expenses,
        root: root,
        employeeName: employeeName,
        department: department,
      );
    } catch (_) {
      // A damaged or unavailable template should not block exporting the
      // user's data. The fallback is a standalone, valid workbook.
      return _exportSimpleXlsx(trip: trip, expenses: expenses, root: root);
    }
  }

  Future<File> _exportTemplateXlsx({
    required Trip trip,
    required List<Expense> expenses,
    required Directory root,
    required String employeeName,
    required String department,
  }) async {
    final source = await rootBundle.load('docs/博朗费用报销单.xlsx');
    final decoded = ZipDecoder().decodeBytes(source.buffer.asUint8List());
    final sheetFile = decoded.findFile('xl/worksheets/sheet1.xml');
    if (sheetFile == null) throw const FormatException('模板缺少明细工作表');
    var sheet = utf8.decode(sheetFile.content as List<int>);

    // The supplied workbook already contains the company's formatting,
    // merged cells and approval footer. Use inline strings for values so we
    // do not need to alter its shared-string table.
    sheet = _replaceCell(sheet, 'B2', employeeName);
    sheet = _replaceCell(sheet, 'E2', department);
    sheet = _replaceCell(sheet, 'I2', _date(DateTime.now()));
    for (var index = 0; index < 24; index++) {
      final row = index + 5;
      final expense = index < expenses.length ? expenses[index] : null;
      sheet = _replaceCell(
        sheet,
        'A$row',
        expense == null ? '' : _date(expense.occurredAt),
      );
      sheet = _replaceCell(
        sheet,
        'B$row',
        expense == null ? '' : expense.category,
      );
      sheet = _replaceCell(
        sheet,
        'C$row',
        expense == null ? '' : expense.purpose,
      );
      sheet = _replaceCell(
        sheet,
        'G$row',
        expense == null ? '' : expense.receiptType,
      );
      sheet = expense == null
          ? _replaceCell(sheet, 'H$row', '')
          : _replaceNumericCell(sheet, 'H$row', expense.claimCents / 100);
      sheet = _replaceCell(
        sheet,
        'I$row',
        expense == null ? '' : expense.notes,
      );
    }
    final total = expenses.fold(0, (sum, item) => sum + item.claimCents);
    sheet = _replaceNumericCell(sheet, 'H29', total / 100);

    final output = Archive();
    for (final file in decoded.files) {
      if (file.name == 'xl/worksheets/sheet1.xml') {
        final bytes = utf8.encode(sheet);
        output.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else {
        output.addFile(
          ArchiveFile(file.name, file.size, file.content as List<int>),
        );
      }
    }
    final directory = await _exportDirectory(trip, root);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${_safe(trip.title)}_${_stamp()}.xlsx',
    );
    await file.writeAsBytes(ZipEncoder().encode(output), flush: true);
    return file;
  }

  Future<File> _exportSimpleXlsx({
    required Trip trip,
    required List<Expense> expenses,
    required Directory root,
  }) async {
    final archive = Archive();
    final rows = <List<String>>[
      ['博朗费用报销单'],
      ['批次', trip.title, '目的地', trip.destination],
      ['发生时间', '费用类型', '用途明细', '票据类型', '金额', '备注'],
      ...expenses.map(
        (expense) => [
          _date(expense.occurredAt),
          expense.category,
          expense.purpose,
          expense.receiptType,
          _money(expense.claimCents),
          expense.notes,
        ],
      ),
      [
        '',
        '',
        '',
        '合计',
        _money(expenses.fold(0, (sum, item) => sum + item.claimCents)),
        '',
      ],
    ];
    final sheet = StringBuffer(
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols><col min="1" max="1" width="14"/><col min="2" max="2" width="14"/><col min="3" max="3" width="42"/><col min="4" max="4" width="14"/><col min="5" max="5" width="14"/><col min="6" max="6" width="24"/></cols><sheetData>''',
    );
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      sheet.write('<row r="${rowIndex + 1}">');
      for (var colIndex = 0; colIndex < rows[rowIndex].length; colIndex++) {
        final value = _xml(rows[rowIndex][colIndex]);
        if (value.isEmpty) continue;
        sheet.write(
          '<c r="${_cellName(colIndex + 1)}${rowIndex + 1}" t="inlineStr"><is><t xml:space="preserve">$value</t></is></c>',
        );
      }
      sheet.write('</row>');
    }
    sheet.write('</sheetData></worksheet>');
    _addTextFile(
      archive,
      '[Content_Types].xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>''',
    );
    _addTextFile(
      archive,
      '_rels/.rels',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>''',
    );
    _addTextFile(
      archive,
      'xl/workbook.xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="费用明细" sheetId="1" r:id="rId1"/></sheets></workbook>''',
    );
    _addTextFile(
      archive,
      'xl/_rels/workbook.xml.rels',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>''',
    );
    _addTextFile(archive, 'xl/worksheets/sheet1.xml', sheet.toString());
    final bytes = ZipEncoder().encode(archive);
    final directory = await _exportDirectory(trip, root);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${_safe(trip.title)}_${_stamp()}.xlsx',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<pw.Font?> _loadChineseFont() async {
    try {
      final data = await rootBundle.load('assets/fonts/SimHei.ttf');
      return pw.Font.ttf(data);
    } catch (_) {
      return null;
    }
  }

  void _addTextFile(Archive archive, String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  static void _paragraph(
    StringBuffer out,
    String text, {
    bool bold = false,
    int size = 22,
  }) {
    out.write(
      '<w:p><w:r><w:rPr>${bold ? '<w:b/>' : ''}<w:sz w:val="$size"/></w:rPr><w:t xml:space="preserve">${_xml(text)}</w:t></w:r></w:p>',
    );
  }

  static void _pageBreak(StringBuffer out) =>
      out.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');

  static String _imageParagraph(String rid) =>
      '<w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="5486400" cy="7000000"/><wp:docPr id="$rid" name="Picture $rid"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="$rid" name="image"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="$rid"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="5486400" cy="7000000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>';

  static String _money(int cents) => '￥${(cents / 100).toStringAsFixed(2)}';

  static String _replaceCell(String xml, String address, String value) {
    final pattern = RegExp(
      '<c r="$address"([^>]*)/>|<c r="$address"([^>]*)>.*?</c>',
      dotAll: true,
    );
    return xml.replaceFirstMapped(pattern, (match) {
      final attributes = _withoutCellType(
        match.group(1) ?? match.group(2) ?? '',
      );
      if (value.isEmpty) return '<c r="$address"$attributes/>';
      return '<c r="$address"$attributes t="inlineStr"><is><t xml:space="preserve">${_xml(value)}</t></is></c>';
    });
  }

  static String _replaceNumericCell(String xml, String address, num value) {
    final pattern = RegExp(
      '<c r="$address"([^>]*)/>|<c r="$address"([^>]*)>.*?</c>',
      dotAll: true,
    );
    return xml.replaceFirstMapped(pattern, (match) {
      final attributes = _withoutCellType(
        match.group(1) ?? match.group(2) ?? '',
      );
      return '<c r="$address"$attributes><v>${value.toStringAsFixed(2)}</v></c>';
    });
  }

  static String _withoutCellType(String attributes) => attributes
      .replaceAll(RegExp(r'\s+t="[^"]*"'), '')
      .replaceAll(RegExp(r'\s+'), ' ');

  static String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  static String _stamp() =>
      DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
  static String _safe(String input) =>
      input.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').isEmpty
      ? '报销'
      : input.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  static String _extension(String path) =>
      path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
  static String _xml(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
  static String _cellName(int column) {
    var n = column;
    var result = '';
    while (n > 0) {
      final rem = (n - 1) % 26;
      result = String.fromCharCode(65 + rem) + result;
      n = (n - 1) ~/ 26;
    }
    return result;
  }
}
