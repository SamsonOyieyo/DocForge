import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/engines/engine_tool.dart';
import '../../core/jobs/job.dart';
import '../../core/pdf/commands.dart';
import '../../core/pdf/page_ranges.dart';
import 'tool_definition.dart';

const _indigo = Color(0xFF3B5BDB);
const _green = Color(0xFF0CA678);
const _amber = Color(0xFFE8A317);
const _orange = Color(0xFFE8590C);
const _purple = Color(0xFF9C36B5);
const _violet = Color(0xFF6741D9);
const _red = Color(0xFFE03131);
const _blue = Color(0xFF1971C2);
const _teal = Color(0xFF0C8599);
const _grey = Color(0xFF5C677D);
const _pink = Color(0xFFC2255C);

final List<ToolDefinition> toolRegistry = [
  ToolDefinition(
    id: 'merge',
    title: 'Merge PDF',
    tagline: 'Combine documents into one file',
    description:
        'Joins PDFs in the order you choose without re-rendering a single page, so vectors, fonts and links survive intact.',
    category: 'Organise',
    icon: Icons.merge_type_rounded,
    tint: _indigo,
    extensions: const ['pdf'],
    multi: true,
    minFiles: 2,
    selectLabel: 'Choose PDFs to merge',
    engineGroups: const [
      [EngineTool.qpdf],
    ],
    outputName: (files, values) => OutputNaming.withSuffix(files.first, '-merged'),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.merge,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
    ),
  ),
  ToolDefinition(
    id: 'split',
    title: 'Split PDF',
    tagline: 'Break a document into parts',
    description:
        'Split every N pages, or give each selected range its own file. Page content is copied structurally – no quality loss.',
    category: 'Organise',
    icon: Icons.call_split_rounded,
    tint: _green,
    extensions: const ['pdf'],
    selectLabel: 'Choose a PDF to split',
    needsPdfInfo: true,
    engineGroups: const [
      [EngineTool.qpdf],
    ],
    fields: [
      const ToolField.choice(
        key: 'mode',
        label: 'Split mode',
        value: 'every',
        choices: [
          ToolChoice('every', 'Every N pages'),
          ToolChoice('ranges', 'One file per range'),
        ],
      ),
      const ToolField.slider(
        key: 'every',
        label: 'Pages per file',
        value: 1,
        min: 1,
        max: 50,
        divisions: 49,
        visibleWhen: _everyMode,
      ),
      const ToolField.pageRanges(
        key: 'ranges',
        label: 'Ranges',
        helper: 'Each comma-separated range becomes its own PDF.',
        visibleWhen: _rangeMode,
      ),
    ],
    validate: (values, pageCount) => _validatePages(values, pageCount, 'ranges', when: _rangeMode(values)),
    outputName: (files, values) => OutputNaming.withSuffix(files.first, '-split'),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.split,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
      options: {'mode': values['mode'], 'every': values['every'], 'ranges': values['ranges']},
    ),
  ),
  ToolDefinition(
    id: 'extract',
    title: 'Extract pages',
    tagline: 'Keep only the pages you need',
    description: 'Pull specific pages (or reorder them) into a new PDF while leaving the original untouched.',
    category: 'Organise',
    icon: Icons.content_cut_rounded,
    tint: _teal,
    extensions: const ['pdf'],
    selectLabel: 'Choose a PDF',
    needsPdfInfo: true,
    engineGroups: const [
      [EngineTool.qpdf],
    ],
    fields: [
      const ToolField.pageRanges(key: 'pages', label: 'Pages to keep'),
    ],
    validate: (values, pageCount) => _validatePages(values, pageCount, 'pages'),
    outputName: (files, values) => OutputNaming.withSuffix(files.first, '-pages'),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.extract,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
      options: {'pages': values['pages']},
    ),
  ),
  ToolDefinition(
    id: 'rotate',
    title: 'Rotate PDF',
    tagline: 'Fix sideways scans',
    description: 'Rotates selected pages in 90° steps by updating page geometry rather than resampling content.',
    category: 'Organise',
    icon: Icons.rotate_right_rounded,
    tint: _amber,
    extensions: const ['pdf'],
    selectLabel: 'Choose a PDF',
    needsPdfInfo: true,
    engineGroups: const [
      [EngineTool.qpdf],
    ],
    fields: [
      const ToolField.choice(
        key: 'angle',
        label: 'Rotation',
        value: '90',
        choices: [
          ToolChoice('90', '90° clockwise'),
          ToolChoice('180', '180°'),
          ToolChoice('270', '90° counter-clockwise'),
        ],
      ),
      const ToolField.pageRanges(key: 'pages', label: 'Pages'),
    ],
    validate: (values, pageCount) => _validatePages(values, pageCount, 'pages'),
    outputName: (files, values) => OutputNaming.withSuffix(files.first, '-rotated'),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.rotate,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
      options: {
        'angle': int.tryParse('${values['angle']}') ?? 90,
        'pages': values['pages'],
      },
    ),
  ),
  ToolDefinition(
    id: 'watermark',
    title: 'Watermark',
    tagline: 'Stamp text across pages',
    description:
        'Generates an overlay PDF locally with the exact page geometry, then composites it with QPDF. Choose angle, opacity and tiling.',
    category: 'Organise',
    icon: Icons.branding_watermark_rounded,
    tint: _purple,
    extensions: const ['pdf'],
    selectLabel: 'Choose a PDF',
    needsPdfInfo: true,
    engineGroups: const [
      [EngineTool.qpdf],
    ],
    fields: [
      const ToolField.text(
        key: 'text',
        label: 'Watermark text',
        value: 'CONFIDENTIAL',
        hint: 'Draft, Confidential, your name…',
      ),
      const ToolField.slider(key: 'fontSize', label: 'Font size', value: 54, min: 12, max: 140, divisions: 64),
      const ToolField.slider(key: 'opacity', label: 'Opacity (%)', value: 18, min: 5, max: 60, divisions: 55),
      const ToolField.choice(
        key: 'angle',
        label: 'Angle',
        value: '45',
        choices: [
          ToolChoice('0', 'Horizontal'),
          ToolChoice('30', '30°'),
          ToolChoice('45', '45°'),
          ToolChoice('60', '60°'),
          ToolChoice('90', 'Vertical'),
        ],
      ),
      const ToolField.choice(
        key: 'color',
        label: 'Colour',
        value: 'grey',
        choices: [
          ToolChoice('grey', 'Grey'),
          ToolChoice('red', 'Red'),
          ToolChoice('blue', 'Blue'),
          ToolChoice('black', 'Black'),
          ToolChoice('white', 'White'),
        ],
      ),
      const ToolField.toggle(key: 'tile', label: 'Tile across the page'),
      const ToolField.pageRanges(key: 'pages', label: 'Pages'),
    ],
    validate: (values, pageCount) {
      if ('${values['text'] ?? ''}'.trim().isEmpty) return 'Enter watermark text.';
      return _validatePages(values, pageCount, 'pages');
    },
    outputName: (files, values) => OutputNaming.withSuffix(files.first, '-watermarked'),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.watermark,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
      options: {...values},
    ),
  ),
  ToolDefinition(
    id: 'page_numbers',
    title: 'Page numbers',
    tagline: 'Add clean pagination',
    description: 'Stamps page numbers with a custom format and position, using the same precise overlay pipeline as watermarks.',
    category: 'Organise',
    icon: Icons.format_list_numbered_rounded,
    tint: _violet,
    extensions: const ['pdf'],
    selectLabel: 'Choose a PDF',
    needsPdfInfo: true,
    engineGroups: const [
      [EngineTool.qpdf],
    ],
    fields: [
      const ToolField.text(
        key: 'template',
        label: 'Format',
        value: 'Page {n} of {total}',
        helper: '{n} is the page number, {total} the page count.',
      ),
      const ToolField.choice(
        key: 'position',
        label: 'Position',
        value: 'bottom-center',
        choices: [
          ToolChoice('bottom-center', 'Bottom centre'),
          ToolChoice('bottom-right', 'Bottom right'),
          ToolChoice('bottom-left', 'Bottom left'),
          ToolChoice('top-center', 'Top centre'),
          ToolChoice('top-right', 'Top right'),
        ],
      ),
      const ToolField.slider(key: 'fontSize', label: 'Font size', value: 11, min: 7, max: 24, divisions: 17),
      const ToolField.slider(key: 'startAt', label: 'Start numbering at', value: 1, min: 1, max: 50, divisions: 49),
      const ToolField.pageRanges(key: 'pages', label: 'Pages'),
    ],
    validate: (values, pageCount) {
      if ('${values['template'] ?? ''}'.trim().isEmpty) return 'Enter a page number format.';
      return _validatePages(values, pageCount, 'pages');
    },
    outputName: (files, values) => OutputNaming.withSuffix(files.first, '-numbered'),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.pageNumbers,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
      options: {...values},
    ),
  ),
  ToolDefinition(
    id: 'compress',
    title: 'Compress',
    tagline: 'Shrink files without wrecking text',
    description:
        'Ghostscript downsamples images, subsets fonts and recompresses streams. Text stays selectable; choose a quality preset.',
    category: 'Optimise',
    icon: Icons.compress_rounded,
    tint: _orange,
    extensions: const ['pdf'],
    selectLabel: 'Choose a PDF',
    engineGroups: const [
      [EngineTool.ghostscript],
    ],
    fields: [
      const ToolField.choice(
        key: 'quality',
        label: 'Quality preset',
        value: 'ebook',
        choices: [
          ToolChoice('screen', 'Screen – smallest (72 dpi)'),
          ToolChoice('ebook', 'Ebook – balanced (150 dpi)'),
          ToolChoice('printer', 'Printer – high (300 dpi)'),
          ToolChoice('prepress', 'Prepress – maximum'),
        ],
      ),
    ],
    outputName: (files, values) => OutputNaming.withSuffix(files.first, '-compressed'),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.compress,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
      options: {'quality': values['quality']},
    ),
  ),
  ToolDefinition(
    id: 'office_to_pdf',
    title: 'Office → PDF',
    tagline: 'DOCX, XLSX, PPTX and more',
    description:
        'Drives headless LibreOffice, the same engine behind Collabora. Layout, fonts and tables are kept faithful to the original.',
    category: 'Convert',
    icon: Icons.description_rounded,
    tint: _green,
    extensions: const ['docx', 'doc', 'xlsx', 'xls', 'pptx', 'ppt', 'odt', 'ods', 'odp', 'rtf', 'txt'],
    multi: true,
    selectLabel: 'Choose Office documents',
    engineGroups: const [
      [EngineTool.libreoffice],
    ],
    notice: 'Password-protected Office files are not supported by headless conversion.',
    outputName: (files, values) => OutputNaming.withSuffix(files.first, '-converted'),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.officeToPdf,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
    ),
  ),
  ToolDefinition(
    id: 'pdf_to_word',
    title: 'PDF → Word',
    tagline: 'Rebuild an editable DOCX',
    description:
        'Uses pdf2docx when it is installed, otherwise LibreOffice’s PDF import. Tables and spacing may need a quick cleanup.',
    category: 'Convert',
    icon: Icons.article_rounded,
    tint: _blue,
    extensions: const ['pdf'],
    selectLabel: 'Choose a PDF',
    engineGroups: const [
      [EngineTool.pdf2docx, EngineTool.libreoffice],
    ],
    notice: 'For the best reconstruction install pdf2docx (pip install pdf2docx).',
    outputName: (files, values) => OutputNaming.withSuffix(files.first, '', extension: '.docx'),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.pdfToWord,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
    ),
  ),
  ToolDefinition(
    id: 'pdf_to_images',
    title: 'PDF → Images',
    tagline: 'PNG or JPEG pages',
    description: 'Rasterises every page at the DPI you choose. Poppler is used when available, with Ghostscript as a fallback.',
    category: 'Convert',
    icon: Icons.image_rounded,
    tint: _pink,
    extensions: const ['pdf'],
    selectLabel: 'Choose a PDF',
    engineGroups: const [
      [EngineTool.pdftoppm, EngineTool.ghostscript],
    ],
    fields: [
      const ToolField.slider(key: 'dpi', label: 'Resolution (DPI)', value: 150, min: 72, max: 300, divisions: 19),
      const ToolField.choice(
        key: 'format',
        label: 'Format',
        value: 'png',
        choices: [ToolChoice('png', 'PNG (lossless)'), ToolChoice('jpeg', 'JPEG (smaller)')],
      ),
    ],
    outputName: (files, values) => p.basenameWithoutExtension(files.first),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.pdfToImages,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
      options: {'dpi': values['dpi'], 'format': values['format']},
    ),
  ),
  ToolDefinition(
    id: 'images_to_pdf',
    title: 'Images → PDF',
    tagline: 'Bundle photos and scans',
    description: 'Builds a clean PDF entirely in Dart – no engine required. Each image gets its own page, fitted with margins.',
    category: 'Convert',
    icon: Icons.collections_rounded,
    tint: _red,
    extensions: const ['png', 'jpg', 'jpeg'],
    multi: true,
    selectLabel: 'Choose images',
    engineGroups: const [],
    fields: [
      const ToolField.choice(
        key: 'pageSize',
        label: 'Page size',
        value: 'a4',
        choices: [ToolChoice('a4', 'A4'), ToolChoice('letter', 'US Letter')],
      ),
    ],
    outputName: (files, values) => OutputNaming.withSuffix(files.first, '-images'),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.imagesToPdf,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
      options: {'pageSize': values['pageSize']},
    ),
  ),
  ToolDefinition(
    id: 'ocr',
    title: 'OCR / searchable PDF',
    tagline: 'Make scans selectable',
    description:
        'Rasterises pages, runs Tesseract locally and merges the result into a PDF/A-style searchable file. Nothing leaves the device.',
    category: 'Scan',
    icon: Icons.document_scanner_rounded,
    tint: _amber,
    extensions: const ['pdf'],
    selectLabel: 'Choose a scanned PDF',
    engineGroups: const [
      [EngineTool.tesseract],
      [EngineTool.qpdf],
      [EngineTool.pdftoppm, EngineTool.ghostscript],
    ],
    fields: [
      const ToolField.text(
        key: 'language',
        label: 'Language',
        value: 'eng',
        hint: 'eng, deu, fra…',
        helper: 'Matches Tesseract language packs installed on this machine.',
      ),
      const ToolField.slider(key: 'dpi', label: 'OCR resolution', value: 300, min: 150, max: 600, divisions: 15),
    ],
    validate: (values, pageCount) =>
        '${values['language'] ?? ''}'.trim().isEmpty ? 'Enter an OCR language.' : null,
    outputName: (files, values) => OutputNaming.withSuffix(files.first, '-searchable'),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.ocr,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
      options: {'language': values['language'], 'dpi': values['dpi']},
    ),
  ),
  ToolDefinition(
    id: 'encrypt',
    title: 'Protect PDF',
    tagline: 'AES-256 password encryption',
    description: 'Adds a user password for opening the file plus optional restrictions on printing and copying.',
    category: 'Secure',
    icon: Icons.lock_rounded,
    tint: _red,
    extensions: const ['pdf'],
    selectLabel: 'Choose a PDF',
    engineGroups: const [
      [EngineTool.qpdf],
    ],
    fields: [
      const ToolField.password(
        key: 'userPassword',
        label: 'Open password',
        hint: 'Required to open the document',
      ),
      const ToolField.password(
        key: 'ownerPassword',
        label: 'Owner password',
        hint: 'Optional – controls permissions',
        helper: 'If left empty, the open password is reused.',
      ),
      const ToolField.toggle(key: 'allowPrinting', label: 'Allow printing', value: true),
      const ToolField.toggle(key: 'allowCopying', label: 'Allow text copying', value: true),
    ],
    validate: (values, pageCount) {
      final user = '${values['userPassword'] ?? ''}';
      final owner = '${values['ownerPassword'] ?? ''}';
      if (user.isEmpty && owner.isEmpty) return 'Choose at least one password.';
      return null;
    },
    outputName: (files, values) => OutputNaming.withSuffix(files.first, '-protected'),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.encrypt,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
      options: {...values},
    ),
  ),
  ToolDefinition(
    id: 'decrypt',
    title: 'Unlock PDF',
    tagline: 'Remove a password you know',
    description: 'Decrypts a document locally. You must know the password – DocForge never attempts to break encryption.',
    category: 'Secure',
    icon: Icons.lock_open_rounded,
    tint: _blue,
    extensions: const ['pdf'],
    selectLabel: 'Choose a protected PDF',
    engineGroups: const [
      [EngineTool.qpdf],
    ],
    fields: [
      const ToolField.password(key: 'password', label: 'Password', hint: 'Leave empty if there is no user password'),
    ],
    outputName: (files, values) => OutputNaming.withSuffix(files.first, '-unlocked'),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.decrypt,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
      options: {'password': values['password']},
    ),
  ),
  ToolDefinition(
    id: 'linearize',
    title: 'Fast web view',
    tagline: 'Linearize for streaming',
    description: 'Reorders the file so the first page can render before the download completes – useful for large shared PDFs.',
    category: 'Optimise',
    icon: Icons.bolt_rounded,
    tint: _teal,
    extensions: const ['pdf'],
    selectLabel: 'Choose a PDF',
    engineGroups: const [
      [EngineTool.qpdf],
    ],
    outputName: (files, values) => OutputNaming.withSuffix(files.first, '-linearized'),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.linearize,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
    ),
  ),
  ToolDefinition(
    id: 'repair',
    title: 'Repair PDF',
    tagline: 'Rebuild a damaged file',
    description: 'Reconstructs cross-reference tables, object streams and trailers so stubborn documents open again.',
    category: 'Optimise',
    icon: Icons.build_rounded,
    tint: _grey,
    extensions: const ['pdf'],
    selectLabel: 'Choose a damaged PDF',
    engineGroups: const [
      [EngineTool.qpdf],
    ],
    notice: 'Recovery depends on how much of the original file survived. Keep a backup of the source.',
    outputName: (files, values) => OutputNaming.withSuffix(files.first, '-repaired'),
    build: ({
      required List<String> files,
      required Map<String, Object?> values,
      required String outputDirectory,
      required String outputName,
      required Map<String, String> toolPaths,
    }) =>
        JobRequest(
      kind: JobKind.repair,
      inputs: files,
      outputDirectory: outputDirectory,
      outputName: outputName,
      toolPaths: toolPaths,
    ),
  ),
];

bool _everyMode(Map<String, Object?> values) => values['mode'] != 'ranges';
bool _rangeMode(Map<String, Object?> values) => values['mode'] == 'ranges';

String? _validatePages(
  Map<String, Object?> values,
  int? pageCount,
  String key, {
  bool when = true,
}) {
  if (!when) return null;
  if (pageCount == null) return 'Page information is not available yet.';
  try {
    PageRangeSelection.parse('${values[key] ?? ''}', pageCount: pageCount);
    return null;
  } on FormatException catch (error) {
    return error.message;
  }
}

List<String> get toolCategories => const ['Organise', 'Convert', 'Optimise', 'Secure', 'Scan'];

List<ToolDefinition> toolsInCategory(String category) =>
    [for (final tool in toolRegistry) if (tool.category == category) tool];
