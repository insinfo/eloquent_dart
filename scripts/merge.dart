import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;

/// Mescla arquivos Dart de diretórios fornecidos em um único arquivo.
///
/// [directories] Lista de diretórios para buscar arquivos.
/// [outputFile] Caminho do arquivo de saída.
/// [extensions] Extensões dos arquivos a serem mesclados (padrão: `.dart`).
Future<void> mergeFiles(List<String> directories, String outputFile,
    {List<String>? extensions}) async {
  final output = File(outputFile);
  final sink = output.openWrite();

  for (final directory in directories) {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      print('Diretório não encontrado: $directory');
      continue;
    }

    try {
      await for (FileSystemEntity entity in dir.list(recursive: true)) {
        if (entity is File) {
          final path = p.normalize(entity.path);
          final fileExtension = p.extension(path);

          if (extensions != null && !extensions.contains(fileExtension)) {
            continue;
          }

          try {
            List<String> contentLines = await File(entity.path).readAsLines();
            sink.writeln('// File: $path');
            for (var line in contentLines) {
              sink.writeln(line);
            }
            sink.writeln();
          } catch (e) {
            print('Erro ao ler o arquivo $path: $e');
          }
        }
      }
    } catch (e) {
      print('Erro ao acessar o diretório $directory: $e');
    }
  }

  await sink.close();
  print('Arquivos mesclados com sucesso em: $outputFile');
}

void main() async {
  List<String> directories = [
    r'C:\MyDartProjects\eloquent\lib',  
  ];

  String outputFile =
      r'C:\MyDartProjects\eloquent\scripts\merged_eloquent_code.dart.txt';

  try {
    await mergeFiles(directories, outputFile, extensions: ['.dart']);
  } catch (e) {
    print("Ocorreu um erro: $e");
  }
}
