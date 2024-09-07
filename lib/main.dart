import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:process_run/process_run.dart';
import 'dart:io';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'Lista de Softwares Instalados',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00FF00)),
        ),
        home: MyHomePage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier { 
  List<List<String>> _outputRows = [];
  String _error = '';
  bool _isLoading = false;  // Adiciona um estado de carregamento

  List<List<String>> get outputRows => _outputRows;
  String get error => _error;
  bool get isLoading => _isLoading;  // Getter para o estado de carregamento

  Future<void> _runScript() async {
    _isLoading = true;  // Define o estado de carregamento como verdadeiro
    notifyListeners();

    try {
      String scriptPath;
      List<String> arguments;

      if (Platform.isWindows) {
        scriptPath = 'scripts\\list_installed_programs.ps1';
        arguments = ['-File', scriptPath];
      } else if (Platform.isMacOS || Platform.isLinux) {
        scriptPath = 'scripts/list_installed_programs.sh';
        arguments = [scriptPath];
      } else {
        _error = 'Sistema operacional não suportado.';
        _outputRows = [];  // Limpa as linhas de saída se o sistema não for suportado
        return;
      }

      final result = await runExecutableArguments(
        Platform.isWindows ? 'powershell' : 'bash',
        arguments,
      );

      _outputRows = parseCsv(result.stdout);
      _error = '';
    } catch (e) {
      _error = 'Erro ao executar o script: $e';
      _outputRows = [];
    } finally {
      _isLoading = false;  // Define o estado de carregamento como falso
      notifyListeners();
    }
  }

  List<List<String>> parseCsv(String csvData) {
    List<List<String>> rows = [];
    List<String> lines = csvData.split('\n');

    // Verifica se há pelo menos uma linha e remove a primeira linha (cabeçalhos)
    if (lines.isNotEmpty) {
      lines.removeAt(0);
    }

  for (String line in lines) {
      if (line.isNotEmpty) {
        // Remove as aspas dos dados
        List<String> columns = line.split(',')
          .map((column) => column.replaceAll('"', '')) // Remove as aspas
          .toList();
        rows.add(columns);
      }
    }

    return rows;
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    super.initState();
    // Executa o script quando o widget é inicializado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MyAppState>()._runScript();
    });
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Lista de Softwares Instalados'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),  // Adiciona padding ao redor do conteúdo
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: () {
                  context.read<MyAppState>()._runScript();
                },
                child: Text('Atualizar Lista'),
              ),
              SizedBox(height: 10),
              if (appState.isLoading) 
                Center(
                  child: CircularProgressIndicator(), // Mostra o indicador de carregamento
                ),
              if (!appState.isLoading) 
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),  // Adiciona padding ao redor da tabela
                      child: DataTable(
                        columns: [
                          DataColumn(label: Text('Nome')),
                          DataColumn(label: Text('Versão')),
                        ],
                        rows: appState.outputRows.map((row) {
                          return DataRow(
                            cells: row.map((cell) {
                              return DataCell(Text(cell));
                            }).toList(),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              if (appState.error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    appState.error,
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
