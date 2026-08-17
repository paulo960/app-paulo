import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const DriverApp());

@pragma("vm:entry-point")
void overlayMain() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OverlayWidget(),
  ));
}

class Shift {
  String id;
  DateTime date;
  int duration;
  double km;
  double fuel;
  double gross;

  Shift({
    required this.id,
    required this.date,
    required this.duration,
    required this.km,
    required this.fuel,
    required this.gross,
  });

  double get net => gross - fuel;
  double get costPerKm => km > 0 ? fuel / km : 0.0;
  double get earningsPerHour => duration > 0 ? (net / (duration / 3600)) : 0.0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date.toIso8601String(),
        'duration': duration,
        'km': km,
        'fuel': fuel,
        'gross': gross,
      };

  factory Shift.fromMap(Map<String, dynamic> map) => Shift(
        id: map['id'],
        date: DateTime.parse(map['date']),
        duration: map['duration'],
        km: (map['km'] as num).toDouble(),
        fuel: (map['fuel'] as num).toDouble(),
        gross: (map['gross'] as num).toDouble(),
      );
}

class DriverApp extends StatefulWidget {
  const DriverApp({super.key});

  @override
  State<DriverApp> createState() => _DriverAppState();
}

class _DriverAppState extends State<DriverApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paulo Luna',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
        cardColor: Colors.white,
        primaryColor: const Color(0xFF00C853),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF00C853),
          secondary: Colors.amber,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        primaryColor: const Color(0xFF00E676),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Colors.amberAccent,
          surface: Color(0xFF1E1E1E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: DriverHomePage(
        onToggleTheme: _toggleTheme,
        isDark: _themeMode == ThemeMode.dark,
      ),
    );
  }
}

class DriverHomePage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDark;

  const DriverHomePage({
    super.key,
    required this.onToggleTheme,
    required this.isDark,
  });

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabs;
  Timer? _timer;
  int _seconds = 0;
  bool _running = false;
  List<Shift> _shifts = [];

  // Posição magnética fluida do balão
  double _pillX = 200.0;
  double _pillY = 150.0;
  bool _isDragging = false;

  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    end: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59),
  );
  String _filterLabel = 'Hoje';

  static const List<String> _meses = [
    '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
  ];

  static const List<String> _mesesAbbr = [
    '', 'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
    'jul', 'ago', 'set', 'out', 'nov', 'dez'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_running) {
      if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
        _showNativeOverlay();
      } else if (state == AppLifecycleState.resumed) {
        _closeNativeOverlay();
      }
    }
  }

  Future<bool> _checkOverlayPermission() async {
    try {
      bool isGranted = await FlutterOverlayWindow.isPermissionGranted();
      if (!isGranted) {
        bool? req = await FlutterOverlayWindow.requestPermission();
        return req ?? false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showNativeOverlay() async {
    try {
      if (await FlutterOverlayWindow.isActive()) return;
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: "Jornada Ativa - Paulo Luna",
        overlayContent: "Tempo: ${_formatTime(_seconds)}",
        flag: OverlayFlag.defaultFlag,
        alignment: OverlayAlignment.centerRight,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: PositionGravity.auto,
        height: 180,
        width: 180,
      );
    } catch (_) {}
  }

  Future<void> _closeNativeOverlay() async {
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? shiftsJson = prefs.getString('shifts_data');
    if (shiftsJson != null) {
      final List decoded = jsonDecode(shiftsJson);
      setState(() {
        _shifts.clear();
        _shifts.addAll(decoded.map((e) => Shift.fromMap(e)).toList());
      });
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_shifts.map((e) => e.toMap()).toList());
    await prefs.setString('shifts_data', encoded);
  }

  void _start() async {
    bool hasPerm = await _checkOverlayPermission();
    if (!hasPerm && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ative a opção "Aparecer sobre outros apps" para o botão flutuante funcionar!'),
          duration: Duration(seconds: 4),
        ),
      );
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _seconds++);
    });
    setState(() => _running = true);
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _running = false);
    _closeNativeOverlay();
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _seconds = 0;
      _running = false;
    });
    _closeNativeOverlay();
  }

  String _formatTime(int s) {
    final h = (s ~/ 3600).toString().padLeft(2, '0');
    final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$h:$m:$sec';
  }

  String _formatDatePt(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = _mesesAbbr[dt.month];
    final y = dt.year.toString();
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d de $m de $y às $h:$min';
  }

  void _openFinishModal() {
    _pause();
    final kmCtrl = TextEditingController();
    final fuelCtrl = TextEditingController();
    final grossCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Jornada'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tempo trabalhado: ${_formatTime(_seconds)}',
                  style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              TextField(
                controller: kmCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'KM Rodados', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: fuelCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Gasto Combustível (R\$)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: grossCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Faturamento Bruto (R\$)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _start();
            },
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final k = double.tryParse(kmCtrl.text.replaceAll(',', '.')) ?? 0.0;
              final f = double.tryParse(fuelCtrl.text.replaceAll(',', '.')) ?? 0.0;
              final g = double.tryParse(grossCtrl.text.replaceAll(',', '.')) ?? 0.0;

              final newShift = Shift(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                date: DateTime.now(),
                duration: _seconds,
                km: k,
                fuel: f,
                gross: g,
              );

              setState(() {
                _shifts.insert(0, newShift);
                _saveData();
              });

              Navigator.pop(ctx);
              _reset();
              _tabs.animateTo(1);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _openShiftFormModal({Shift? shiftToEdit}) {
    final isEditing = shiftToEdit != null;
    DateTime selectedDate = isEditing ? shiftToEdit.date : DateTime.now();
    int totalSecs = isEditing ? shiftToEdit.duration : 0;

    final hoursCtrl = TextEditingController(text: (totalSecs ~/ 3600).toString());
    final minsCtrl = TextEditingController(text: ((totalSecs % 3600) ~/ 60).toString());
    final kmCtrl = TextEditingController(text: isEditing ? shiftToEdit.km.toString() : '');
    final fuelCtrl = TextEditingController(text: isEditing ? shiftToEdit.fuel.toString() : '');
    final grossCtrl = TextEditingController(text: isEditing ? shiftToEdit.gross.toString() : '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text(isEditing ? 'Editar Jornada' : 'Adicionar Turno Passado'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Data: ${_formatDatePt(selectedDate)}'),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (pickedDate != null) {
                      final pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(selectedDate),
                      );
                      if (pickedTime != null) {
                        setModalState(() {
                          selectedDate = DateTime(
                            pickedDate.year,
                            pickedDate.month,
                            pickedDate.day,
                            pickedTime.hour,
                            pickedTime.minute,
                          );
                        });
                      }
                    }
                  },
                ),
                const SizedBox(height: 10),
                const Text('Tempo Trabalhado:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: hoursCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Horas', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: minsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Minutos', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: kmCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'KM Rodados', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: fuelCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Combustível (R\$)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: grossCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Faturamento Bruto (R\$)', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                final h = int.tryParse(hoursCtrl.text) ?? 0;
                final m = int.tryParse(minsCtrl.text) ?? 0;
                final totalDur = (h * 3600) + (m * 60);
                final k = double.tryParse(kmCtrl.text.replaceAll(',', '.')) ?? 0.0;
                final f = double.tryParse(fuelCtrl.text.replaceAll(',', '.')) ?? 0.0;
                final g = double.tryParse(grossCtrl.text.replaceAll(',', '.')) ?? 0.0;

                setState(() {
                  if (isEditing) {
                    final index = _shifts.indexWhere((s) => s.id == shiftToEdit.id);
                    if (index != -1) {
                      _shifts[index] = Shift(
                        id: shiftToEdit.id,
                        date: selectedDate,
                        duration: totalDur,
                        km: k,
                        fuel: f,
                        gross: g,
                      );
                    }
                  } else {
                    _shifts.insert(
                      0,
                      Shift(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        date: selectedDate,
                        duration: totalDur,
                        km: k,
                        fuel: f,
                        gross: g,
                      ),
                    );
                  }
                  _saveData();
                });

                Navigator.pop(ctx);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteShift(Shift shift) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Turno'),
        content: const Text('Deseja realmente remover este registro de jornada?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                _shifts.removeWhere((s) => s.id == shift.id);
                _saveData();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  // Calendário Customizado com Visual idêntico ao Print e 100% em Português
  void _openDateFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        DateTime displayedMonth = DateTime(_selectedRange.start.year, _selectedRange.start.month, 1);
        DateTime? tempStart = _selectedRange.start;
        DateTime? tempEnd = _selectedRange.end;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final now = DateTime.now();

            void applyShortcut(String label, DateTime start, DateTime end) {
              setState(() {
                _filterLabel = label;
                _selectedRange = DateTimeRange(
                  start: DateTime(start.year, start.month, start.day),
                  end: DateTime(end.year, end.month, end.day, 23, 59, 59),
                );
              });
              Navigator.pop(ctx);
            }

            int daysInMonth = DateTime(displayedMonth.year, displayedMonth.month + 1, 0).day;
            int firstWeekday = DateTime(displayedMonth.year, displayedMonth.month, 1).weekday % 7; // Dom = 0

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey[500], borderRadius: BorderRadius.circular(10)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Selecionar período', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Botões de Atalhos rápidos
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _shortcutChip('Hoje', () => applyShortcut('Hoje', now, now)),
                        _shortcutChip('Ontem', () {
                          final y = now.subtract(const Duration(days: 1));
                          applyShortcut('Ontem', y, y);
                        }),
                        _shortcutChip('7 dias', () {
                          final start = now.subtract(const Duration(days: 7));
                          applyShortcut('Últimos 7 dias', start, now);
                        }),
                        _shortcutChip('Este mês', () {
                          final start = DateTime(now.year, now.month, 1);
                          applyShortcut('${_meses[now.month]} de ${now.year}', start, now);
                        }),
                        _shortcutChip('Mês passado', () {
                          final prevMonth = DateTime(now.year, now.month - 1, 1);
                          final lastDay = DateTime(now.year, now.month, 0);
                          applyShortcut('${_meses[prevMonth.month]} de ${prevMonth.year}', prevMonth, lastDay);
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Cabeçalho de Navegação de Mês
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () {
                          setSheetState(() {
                            displayedMonth = DateTime(displayedMonth.year, displayedMonth.month - 1, 1);
                          });
                        },
                      ),
                      Text(
                        '${_meses[displayedMonth.month]} ${displayedMonth.year}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () {
                          setSheetState(() {
                            displayedMonth = DateTime(displayedMonth.year, displayedMonth.month + 1, 1);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Dias da Semana em Português (D S T Q Q S S)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text('D', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      Text('S', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      Text('T', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      Text('Q', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      Text('Q', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      Text('S', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      Text('S', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Grid dos dias
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: firstWeekday + daysInMonth,
                    itemBuilder: (context, index) {
                      if (index < firstWeekday) return const SizedBox.shrink();
                      final dayNumber = index - firstWeekday + 1;
                      final dayDate = DateTime(displayedMonth.year, displayedMonth.month, dayNumber);

                      bool isSelectedStart = tempStart != null &&
                          dayDate.year == tempStart!.year &&
                          dayDate.month == tempStart!.month &&
                          dayDate.day == tempStart!.day;

                      bool isSelectedEnd = tempEnd != null &&
                          dayDate.year == tempEnd!.year &&
                          dayDate.month == tempEnd!.month &&
                          dayDate.day == tempEnd!.day;

                      bool isInRange = tempStart != null &&
                          tempEnd != null &&
                          dayDate.isAfter(tempStart!) &&
                          dayDate.isBefore(tempEnd!);

                      return GestureDetector(
                        onTap: () {
                          setSheetState(() {
                            if (tempStart == null || (tempStart != null && tempEnd != null)) {
                              tempStart = dayDate;
                              tempEnd = null;
                            } else if (tempStart != null && tempEnd == null) {
                              if (dayDate.isBefore(tempStart!)) {
                                tempStart = dayDate;
                              } else {
                                tempEnd = dayDate;
                              }
                            }
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: (isSelectedStart || isSelectedEnd)
                                ? const Color(0xFF00C853)
                                : isInRange
                                    ? const Color(0xFF00C853).withOpacity(0.25)
                                    : Colors.transparent,
                            borderRadius: BorderRadius.circular((isSelectedStart || isSelectedEnd) ? 20 : 6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$dayNumber',
                            style: TextStyle(
                              color: (isSelectedStart || isSelectedEnd) ? Colors.white : null,
                              fontWeight: (isSelectedStart || isSelectedEnd) ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tempStart != null && tempEnd != null
                        ? '${tempStart!.day} ${_mesesAbbr[tempStart!.month]} – ${tempEnd!.day} ${_mesesAbbr[tempEnd!.month]}'
                        : tempStart != null
                            ? '${tempStart!.day} ${_mesesAbbr[tempStart!.month]} – ...'
                            : 'Selecione as datas',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C853),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        if (tempStart != null) {
                          final finalEnd = tempEnd ?? tempStart!;
                          setState(() {
                            _filterLabel = '${tempStart!.day}/${_mesesAbbr[tempStart!.month]} – ${finalEnd.day}/${_mesesAbbr[finalEnd.month]}';
                            _selectedRange = DateTimeRange(
                              start: DateTime(tempStart!.year, tempStart!.month, tempStart!.day),
                              end: DateTime(finalEnd.year, finalEnd.month, finalEnd.day, 23, 59, 59),
                            );
                          });
                        }
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Aplicar período', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _shortcutChip(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(
        label: Text(label),
        onPressed: onTap,
        backgroundColor: widget.isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE8E8E8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  List<Shift> get _filteredShifts {
    return _shifts.where((s) {
      return s.date.isAfter(_selectedRange.start.subtract(const Duration(seconds: 1))) &&
          s.date.isBefore(_selectedRange.end.add(const Duration(seconds: 1)));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paulo Luna', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: 'Alternar Tema',
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Filtrar Datas',
            onPressed: _openDateFilterBottomSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Theme.of(context).primaryColor,
          tabs: const [
            Tab(icon: Icon(Icons.timer), text: 'Jornada'),
            Tab(icon: Icon(Icons.analytics), text: 'Histórico & Lucros'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabs,
            children: [
              _buildTimerTab(),
              _buildHistoryTab(),
            ],
          ),

          // BALÃO COM ENCAIXE MAGNÉTICO NAS BORDAS LATERAIS
          if (_running)
            AnimatedPositioned(
              duration: _isDragging ? Duration.zero : const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              left: _pillX,
              top: _pillY,
              child: GestureDetector(
                onPanStart: (_) {
                  setState(() => _isDragging = true);
                },
                onPanUpdate: (details) {
                  setState(() {
                    _pillX += details.delta.dx;
                    _pillY += details.delta.dy;
                    _pillY = _pillY.clamp(80.0, screenSize.height - 180.0);
                  });
                },
                onPanEnd: (details) {
                  setState(() {
                    _isDragging = false;
                    // Efeito Magnético: Se estiver na metade esquerda, gruda na esquerda. Senão, na direita.
                    if (_pillX < (screenSize.width / 2) - 60) {
                      _pillX = 10.0;
                    } else {
                      _pillX = screenSize.width - 150.0;
                    }
                  });
                },
                onTap: () => _tabs.animateTo(0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF00E676), width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fiber_manual_record, color: Color(0xFF00E676), size: 10),
                      const SizedBox(width: 6),
                      Text(
                        _formatTime(_seconds),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _tabs.index == 1
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF00C853),
              foregroundColor: Colors.white,
              onPressed: () => _openShiftFormModal(),
              tooltip: 'Adicionar Turno Passado',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildTimerTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('TEMPO DE TRABALHO', style: TextStyle(color: Colors.grey, letterSpacing: 2, fontSize: 13)),
          const SizedBox(height: 15),
          Text(_formatTime(_seconds), style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_running)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C853),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('INICIAR', style: TextStyle(fontWeight: FontWeight.bold)),
                )
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _pause,
                  icon: const Icon(Icons.pause),
                  label: const Text('PAUSAR', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              const SizedBox(width: 15),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _seconds > 0 ? _openFinishModal : null,
                icon: const Icon(Icons.stop),
                label: const Text('TERMINAR', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    final list = _filteredShifts;
    final totalKm = list.fold(0.0, (sum, i) => sum + i.km);
    final totalFuel = list.fold(0.0, (sum, i) => sum + i.fuel);
    final totalNet = list.fold(0.0, (sum, i) => sum + i.net);
    final totalSec = list.fold(0, (sum, i) => sum + i.duration);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: InkWell(
            onTap: _openDateFilterBottomSheet,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: widget.isDark ? const Color(0xFF222222) : const Color(0xFFEAEAEA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Color(0xFF00C853)),
                      const SizedBox(width: 8),
                      Text('Período: $_filterLabel', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const Text('Alterar', style: TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _metricItem('Horas Trabalhadas', _formatTime(totalSec), Icons.access_time),
                    _metricItem('KM Rodados', '${totalKm.toStringAsFixed(1)} km', Icons.directions_car),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _metricItem('Gasto Combustível', 'R\$ ${totalFuel.toStringAsFixed(2)}', Icons.local_gas_station, color: Colors.redAccent),
                    _metricItem('Lucro Líquido', 'R\$ ${totalNet.toStringAsFixed(2)}', Icons.attach_money, color: const Color(0xFF00C853)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Turnos Registrados', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: () => _openShiftFormModal(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Novo Turno', style: TextStyle(fontSize: 12)),
              )
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('Nenhum turno para este período.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final item = list[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.black12,
                          child: Icon(Icons.drive_eta, color: Color(0xFF00C853)),
                        ),
                        title: Text(_formatDatePt(item.date), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(
                          '${_formatTime(item.duration)} • ${item.km} km • Gas: R\$ ${item.fuel.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'R\$ ${item.net.toStringAsFixed(2)}',
                              style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 20),
                              onSelected: (val) {
                                if (val == 'edit') {
                                  _openShiftFormModal(shiftToEdit: item);
                                } else if (val == 'delete') {
                                  _deleteShift(item);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Editar')]),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 18), SizedBox(width: 8), Text('Excluir', style: TextStyle(color: Colors.red))]),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _metricItem(String label, String value, IconData icon, {Color color = Colors.grey}) {
    return Row(
      children: [
        Icon(icon, size: 24, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color == Colors.grey ? null : color)),
          ],
        )
      ],
    );
  }
}

class OverlayWidget extends StatelessWidget {
  const OverlayWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () => FlutterOverlayWindow.shareData("open_app"),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.92),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF00E676), width: 3),
            boxShadow: const [
              BoxShadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 3)),
            ],
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer, color: Color(0xFF00E676), size: 26),
                SizedBox(height: 2),
                Text(
                  "EM ROTA",
                  style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
