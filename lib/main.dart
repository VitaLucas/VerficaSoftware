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
            seedColor: Colors.blue,
            primary: Colors.blue[700]!,
            secondary: Colors.amber[600]!,
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
            elevation: 1,
            useIndicator: true,
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
              decoration: InputDecoration(
                labelText: 'Pesquisar',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                context.read<MyAppState>().updateSearchQuery(value);
              },
            ),
            SizedBox(height: 10),
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: "Softwares"),
                Tab(text: "Extensões Browser"),
                Tab(text: "Plugins"),
              ],
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Colors.grey,
            ),
            SizedBox(height: 10),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Aba Softwares
                  _buildDataTable(appState.outputRows),

                  // Aba Extensões Browser
                  _buildDataTable([]), // Placeholder para os dados das extensões

                  // Aba Plugins
                  _buildDataTable([]), // Placeholder para os dados dos plugins
                ],
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
            _buildComplianceLegend(),
          ],
        ),
      ),
    );
  }

// Função para contar softwares não homologados em uma lista
int countNonHomologated(List<Map<String, String>> dataRows) {
  return dataRows.where((row) => row['status'] == 'not_found').length;
}

// Função para contar softwares não homologados em todas as abas
int countTotalNonHomologated(MyAppState appState) {
  final softwaresNonHomologated = countNonHomologated(appState.outputRows);
  final extensoesNonHomologated = countNonHomologated([]); // Placeholder
  final pluginsNonHomologated = countNonHomologated([]); // Placeholder
  return softwaresNonHomologated + extensoesNonHomologated + pluginsNonHomologated;
}

  Widget _buildDataTable(List<Map<String, String>> dataRows) {
  return SingleChildScrollView(
    scrollDirection: Axis.vertical,
    child: Padding(
      padding: const EdgeInsets.all(8.0),
      child: DataTable(
        columns: [
          DataColumn(label: Text('Compliance')),
          DataColumn(label: Text('Nome')),
          DataColumn(label: Text('Versão')),
        ],
        rows: dataRows.map((row) {
          Icon icon;
          switch (row['status']) {
            case 'homologated':
              icon = Icon(Icons.check_circle, color: Colors.green);
              break;
            case 'mismatch':
              icon = Icon(Icons.warning, color: Colors.yellow);
              break;
            default:
              icon = Icon(Icons.cancel, color: Colors.red);
          }
          return DataRow(
            cells: [
              DataCell(Row(mainAxisAlignment: MainAxisAlignment.center, children: [icon])),
              DataCell(Text(row['name']!)),
              DataCell(Text(row['version']!)),
            ],
          );
        }).toList(),
      ),
    ),
  );
}

Widget _buildComplianceLegend() {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[400]!),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Compliance:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 10),
                    Expanded(child: Text('Homologado pelo CC')),
                  ],
                ),
                Divider(color: Colors.grey[300]),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning, color: Colors.yellow),
                    SizedBox(width: 10),
                    Expanded(child: Text('Versão diferente da homologada')),
                  ],
                ),
                Divider(color: Colors.grey[300]),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cancel, color: Colors.red),
                    SizedBox(width: 10),
                    Expanded(child: Text('Software não homologado')),
                  ],
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: 40),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Total de softwares não homologados',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                  ),
                ),
                SizedBox(height: 8),
                // Aqui você precisa garantir que `countTotalNonHomologated` 
                // seja chamado no momento correto para obter o número atualizado.
                Text(
                  '${countTotalNonHomologated(context.read<MyAppState>())}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  Expanded(child: Text('Regularize', textAlign:TextAlign.center))
                  ]
                )
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
}

class HomologationPage extends StatefulWidget {
  @override
  _HomologationPageState createState() => _HomologationPageState();
}

class _HomologationPageState extends State<HomologationPage> with SingleTickerProviderStateMixin {
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
        title: Text('Homologados - Lista Geral'),
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
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: "Softwares"),
                Tab(text: "Extensões Browser"),
                Tab(text: "Plugins"),
              ],
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Colors.grey,
            ),
            SizedBox(height: 10),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Aba Softwares
                  _buildDataTable(appState.homologationRows),

                  // Aba Extensões Browser
                  _buildDataTable([]), // Placeholder para os dados das extensões

                  // Aba Plugins
                  _buildDataTable([]), // Placeholder para os dados dos plugins
                ],
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
    );
  }

  Widget _buildDataTable(List<List<dynamic>> dataRows) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: DataTable(
          columns: [
            DataColumn(label: Text('Nome')),
            DataColumn(label: Text('Versão')),
          ],
          rows: dataRows.map((row) {
            return DataRow(
              cells: [
                DataCell(Text(row[0].toString())),
                DataCell(Text(row[1].toString())),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}