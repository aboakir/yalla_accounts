import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Central print path for Yallah Accounts.
///
/// Saved/shared PDFs stay vector and searchable. Physical printing is rasterized
/// first so printer drivers never have to re-shape or remap embedded Arabic
/// glyph subsets.
class YallaPdfPrintService {
  static const double rasterDpi = 216;

  static Future<bool> layoutPdf({
    required LayoutCallback onLayout,
    String name = 'Document',
    PdfPageFormat format = PdfPageFormat.standard,
    bool usePrinterSettings = false,
    OutputType outputType = OutputType.generic,
    bool forceCustomPrintPaper = false,
  }) async {
    final source = await onLayout(format);
    final printSafe = await rasterizeForPrint(source);

    return Printing.layoutPdf(
      name: name,
      format: format,
      dynamicLayout: false,
      usePrinterSettings: usePrinterSettings,
      outputType: outputType,
      forceCustomPrintPaper: forceCustomPrintPaper,
      onLayout: (_) async => printSafe,
    );
  }

  static Future<Uint8List> rasterizeForPrint(
    Uint8List source, {
    double dpi = rasterDpi,
  }) async {
    if (dpi <= 0) {
      throw ArgumentError.value(dpi, 'dpi', 'يجب أن تكون دقة الطباعة موجبة');
    }

    final output = pw.Document(compress: true);
    var pageCount = 0;

    await for (final page in Printing.raster(source, dpi: dpi)) {
      pageCount += 1;
      final png = await page.toPng();
      final pageFormat = PdfPageFormat(
        page.width / dpi * PdfPageFormat.inch,
        page.height / dpi * PdfPageFormat.inch,
        marginAll: 0,
      );

      output.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Container(
            width: pageFormat.width,
            height: pageFormat.height,
            child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
          ),
        ),
      );
    }

    if (pageCount == 0) {
      throw StateError('تعذر تجهيز صفحات PDF للطباعة');
    }
    return output.save();
  }
}
