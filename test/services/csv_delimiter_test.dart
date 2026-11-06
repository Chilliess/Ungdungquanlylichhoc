import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/services/csv_delimiter.dart';

void main() {
  test('detects comma delimiter and ignores semicolons in quoted fields', () {
    const csv = 'Code,Name,Notes\r\n'
        'CS101,"Algorithms; data structures","He said ""hello, world"""';

    expect(detectCsvDelimiter(csv), ',');
  });

  test('detects semicolon delimiter and ignores commas in quoted fields', () {
    const csv = '"Course, code";"Course; name";Room\r\n'
        '"CS,101";"Algorithms, data structures";"B;302"';

    expect(detectCsvDelimiter(csv), ';');
  });

  test('defaults to comma when the header has no delimiter', () {
    expect(detectCsvDelimiter('Course name\r\nAlgorithms'), ',');
  });
}
