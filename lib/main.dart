import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:process_run/process_run.dart';
import 'dart:io';
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
  List<Map<String, String>> _outputRows = [];
  List<List<dynamic>> _homologationRows = [];
  String _error = '';
  bool _isLoading = false;
  String _searchQuery = '';

  List<Map<String, String>> get outputRows => _outputRows
      .where((row) => row['name']!.toLowerCase().contains(_searchQuery.toLowerCase()))
      .toList();
  List<List<dynamic>> get homologationRows => _homologationRows
      .where((row) => row[0].toString().toLowerCase().contains(_searchQuery.toLowerCase()))
      .toList();
  String get error => _error;
  bool get isLoading => _isLoading;

  Future<void> runScript() async {
    _isLoading = true;
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
        _outputRows = [];
        notifyListeners();
        return;
      }

      final result = await runExecutableArguments(
        Platform.isWindows ? 'powershell' : 'bash',
        arguments,
      );

      // Após obter os dados do script, faça o processamento do CSV de homologação
      await fetchAndProcessCsv(result.stdout);

      _error = '';
    } catch (e) {
      _error = 'Erro ao executar o script: $e';
      _outputRows = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchAndProcessCsv(String scriptOutput) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Referência ao arquivo no Firebase Storage
      final storageRef = FirebaseStorage.instance.ref().child('homologation.csv');

      // Baixar o arquivo para um diretório temporário local
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/homologation.csv';
      final file = File(filePath);

      await storageRef.writeToFile(file);

      // Ler e processar o arquivo CSV
      final csvData = await file.readAsString();
      _homologationRows = CsvToListConverter().convert(csvData);

      if (_homologationRows.isNotEmpty) {
        _homologationRows.removeAt(0); // Remove cabeçalhos
      }

      _outputRows = await parseAndCompareCsv(scriptOutput);
      _error = '';
    } catch (e) {
      _error = 'Erro ao buscar o arquivo CSV: $e';
      _outputRows = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, String>>> parseAndCompareCsv(String scriptOutput) async {
    List<Map<String, String>> rows = [];
    List<String> lines = scriptOutput.split('\n');

    if (lines.isNotEmpty) {
      lines.removeAt(0); // Remove cabeçalhos
    }

    for (String line in lines) {
      if (line.isNotEmpty) {
        List<String> columns = line.split(',')
            .map((column) => column.replaceAll('"', '').trim())
            .toList();

        if (columns.length >= 2) {
          String name = columns[0];
          String version = columns[1];

          // Comparação com o arquivo de homologação
          bool isHomologated = false;
          bool versionMismatch = false;

          for (var homologationRow in _homologationRows) {
            if (homologationRow.length >= 2) {
              String homologationName = homologationRow[0].toString();
              String homologationVersion = homologationRow[1].toString();

              if (homologationName == name) {
                if (homologationVersion == version) {
                  isHomologated = true;
                  break; // Encontrou uma correspondência exata, pode sair do loop
                } else {
                  versionMismatch = true;
                }
              }
            }
          }

          // Adiciona o resultado da comparação
          rows.add({
            'name': name,
            'version': version,
            'status': isHomologated ? 'homologated' : (versionMismatch ? 'mismatch' : 'not_found')
          });
        }
      }
    }

    return rows;
  }

  void updateSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MyAppState>().runScript();
    });
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: [
              NavigationRailDestination(
                icon: Icon(Icons.home),
                label: Text('Softwares desta estação'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.check),
                label: Text('Softwares homologados CC'),
              ),
            ],
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                MyHomePageContent(), // Página Principal
                HomologationPage(),  // Softwares Homologados
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MyHomePageContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Softwares Instalados'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 10),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Pesquisar',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  context.read<MyAppState>().updateSearchQuery(value);
                },
              ),
              SizedBox(height: 10),
              if (appState.isLoading)
                Center(
                  child: CircularProgressIndicator(),
                ),
              if (!appState.isLoading)
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: DataTable(
                        columns: [
                          DataColumn(label: Text('Nome')),
                          DataColumn(label: Text('Versão')),
                          DataColumn(label: Text('Compliance')),
                        ],
                        rows: appState.outputRows.map((row) {
                          Color color;
                          switch (row['status']) {
                            case 'homologated':
                              color = Colors.green;
                              break;
                            case 'mismatch':
                              color = Colors.yellow;
                              break;
                            default:
                              color = Colors.red;
                          }
                          return DataRow(
                            cells: [
                              DataCell(Text(row['name']!)),
                              DataCell(Text(row['version']!)),
                              DataCell(Container(
                                width: 20,
                                height: 20,
                                color: color,
                              )),
                            ],
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
              // Legenda das cores
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            context.read<MyAppState>().runScript();
                          },
                          child: Text('Atualizar Lista'),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(width: 20, height: 20, color: Colors.green),
                        SizedBox(width: 10),
                        Text('Homologado'),
                      ],
                    ),
                    Row(
                      children: [
                        Container(width: 20, height: 20, color: Colors.yellow),
                        SizedBox(width: 10),
                        Text('Versão Diferente'),
                      ],
                    ),
                    Row(
                      children: [
                        Container(width: 20, height: 20, color: Colors.red),
                        SizedBox(width: 10),
                        Text('Não Homologado'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomologationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<MyAppState>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Softwares Homologados CC - Lista Geral'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: 'Pesquisar',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  context.read<MyAppState>().updateSearchQuery(value);
                },
              ),
              SizedBox(height: 10),
              if (appState.isLoading)
                Center(
                  child: CircularProgressIndicator(),
                ),
              if (!appState.isLoading)
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: DataTable(
                        columns: [
                          DataColumn(label: Text('Nome')),
                          DataColumn(label: Text('Versão')),
                        ],
                        rows: appState.homologationRows.map((row) {
                          return DataRow(
                            cells: [
                              DataCell(Text(row[0].toString())),
                              DataCell(Text(row[1].toString())),
                            ],
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
            ],
          ),
        ),
      ),
    );
  }
}

