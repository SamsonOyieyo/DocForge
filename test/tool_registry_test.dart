import 'package:docforge/core/jobs/job.dart';
import 'package:docforge/features/tool/tool_definition.dart';
import 'package:docforge/features/tool/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ToolDefinition definition(String id) =>
      toolRegistry.firstWhere((definition) => definition.id == id);

  JobRequest build(String id, Map<String, Object?> values) {
    return definition(id).build(
      files: const ['in.pdf'],
      values: values,
      outputDirectory: r'C:\out',
      outputName: 'out.pdf',
      toolPaths: const {},
    );
  }

  group('page-scoped tools forward the document page count', () {
    test('extract', () {
      final request = build('extract', {'pages': '1-2,5', 'pageCount': 5});

      expect(request.kind, JobKind.extract);
      expect(request.options['pages'], '1-2,5');
      expect(request.options['pageCount'], 5);
    });

    test('rotate', () {
      final request = build('rotate', {
        'angle': '270',
        'pages': '2-z',
        'pageCount': 6,
      });

      expect(request.kind, JobKind.rotate);
      expect(request.options['angle'], 270);
      expect(request.options['pages'], '2-z');
      expect(request.options['pageCount'], 6);
    });

    test('split', () {
      final request = build('split', {
        'mode': 'ranges',
        'every': 2,
        'ranges': '1-2,3-z',
        'pageCount': 5,
      });

      expect(request.kind, JobKind.split);
      expect(request.options['ranges'], '1-2,3-z');
      expect(request.options['pageCount'], 5);
    });
  });
}
