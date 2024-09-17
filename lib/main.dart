import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:process_run/process_run.dart';
import 'dart:io';
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
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 243, 33, 33),
            primary: const Color.fromARGB(255, 210, 25, 25)!,
            secondary: const Color.fromARGB(255, 255, 0, 43)!,
          ),
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
      final storageRef = FirebaseStorage.instance.ref().child('homologation.csv');
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/homologation.csv';
      final file = File(filePath);

      await storageRef.writeToFile(file);

      final csvData = await file.readAsString();
      _homologationRows = CsvToListConverter().convert(csvData);

      if (_homologationRows.isNotEmpty) {
        _homologationRows.removeAt(0);
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
      lines.removeAt(0);
    }

    for (String line in lines) {
      if (line.isNotEmpty) {
        List<String> columns = line.split(',')
            .map((column) => column.replaceAll('"', '').trim())
            .toList();

        if (columns.length >= 4) {
          String name = columns[0];
          String version = columns[1];
          String type = columns[2];
          String platform = columns[3];

          bool isHomologated = false;
          bool versionMismatch = false;

          for (var homologationRow in _homologationRows) {
            if (homologationRow.length >= 4) {
              String homologationName = homologationRow[0].toString();
              String homologationVersion = homologationRow[1].toString();
              String homologationType = homologationRow[2].toString();
              String homologationPlatform = homologationRow[3].toString();

              if (homologationName == name && homologationType == type && homologationPlatform == platform) {
                if (homologationVersion == version) {
                  isHomologated = true;
                  break;
                } else {
                  versionMismatch = true;
                }
              }
            }
          }

          rows.add({
            'name': name,
            'version': version,
            'type': type,
            'plataform': platform,
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
                label: Text('Nesta estação'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.verified),
                label: Text('Homologados'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.cancel),
                label: Text('Proibidos'),
              ),
            ],
            elevation: 1,
            useIndicator: true,
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                MyHomePageContent(),
                HomologationPage(),
                ForbiddenPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MyHomePageContent extends StatefulWidget {
  @override
  _MyHomePageContentState createState() => _MyHomePageContentState();
}

class _MyHomePageContentState extends State<MyHomePageContent> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Instalados nesta estação'),
        centerTitle: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(bottomLeft: Radius.circular(25), bottomRight: Radius.circular(25)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 10),
            TextField(
              onChanged: (value) {
                context.read<MyAppState>().updateSearchQuery(value);
              },
              decoration: InputDecoration(
                labelText: 'Buscar',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: 'Softwares'),
                Tab(text: 'Extensões Browser'),
                Tab(text: 'Plugins'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDataTable(appState.outputRows.where((row) => row['type'] == 'Software').toList()),
                  _buildDataTable(appState.outputRows.where((row) => row['type'] == 'Extension').toList()),
                  _buildDataTable(appState.outputRows.where((row) => row['type'] == 'Plug-in').toList()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataTable(List<Map<String, String>> rows) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: DataTable(
        columns: [
          DataColumn(label: Text('Compliance')),
          DataColumn(label: Text('Nome')),
          DataColumn(label: Text('Versão')),
          DataColumn(label: Text('Plataforma')),
        ],
        rows: rows.map((row) {
          Color statusColor;
          String tooltipMessage;
          switch (row['status']) {
            case 'homologated':
              statusColor = Colors.green;
              tooltipMessage = 'Homologado: versão correta';
              break;
            case 'mismatch':
              statusColor = Colors.yellow;
              tooltipMessage = 'Alerta: versão não homologada';
              break;
            case 'not_found':
              statusColor = Colors.red;
              tooltipMessage = 'Software não homologado';
              break;
            default:
              statusColor = Colors.grey;
              tooltipMessage = 'Status desconhecido';
          }

          return DataRow(cells: [
            DataCell(Center(child: Tooltip(message: tooltipMessage, child: Icon(Icons.circle, color: statusColor)))),
            DataCell(Text(row['name']!)),
            DataCell(Text(row['version']!)),
            DataCell(Text(row['plataform']!)),
          ]);
        }).toList(),
      ),
    );
  }
}

class HomologationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Softwares Homologados CC'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              onChanged: (value) {
                context.read<MyAppState>().updateSearchQuery(value);
              },
              decoration: InputDecoration(
                labelText: 'Buscar',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text('Nome')),
                    DataColumn(label: Text('Versão')),
                    DataColumn(label: Text('Plataforma')),
                  ],
                  rows: appState.homologationRows.map((row) {
                    return DataRow(cells: [
                      DataCell(Text(row[0].toString())),
                      DataCell(Text(row[1].toString())),
                      DataCell(Text(row[3].toString())),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class ForbiddenPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Softwares proibidos'),
      )
    );
  }
}
