String detectCsvDelimiter(String csv) {
  var commas = 0;
  var semicolons = 0;
  var inQuotes = false;

  for (var i = 0; i < csv.length; i++) {
    final character = csv[i];
    if (character == '"') {
      if (inQuotes && i + 1 < csv.length && csv[i + 1] == '"') {
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (!inQuotes && (character == '\n' || character == '\r')) {
      break;
    } else if (!inQuotes && character == ',') {
      commas++;
    } else if (!inQuotes && character == ';') {
      semicolons++;
    }
  }

  return semicolons > commas ? ';' : ',';
}
