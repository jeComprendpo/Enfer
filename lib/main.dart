import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:async';

void main() {
  runApp(const FogHillApp());
}

class FogHillApp extends StatelessWidget {
  const FogHillApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Fog Hill Village',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9C1E1E)),
        useMaterial3: true,
        fontFamily: 'NotoSerifSC',
      ),
      home: const GameScreen(),
    );
  }
}

// ===== Models =====
const double kTileBuilding = 72;
const double kTileRoad = 24;

enum BuildType { pavillon, riziere, theTemple, bambou, encens, autel, chemin }

extension BuildTypeX on BuildType {
  String get keyName => switch (this) {
        BuildType.pavillon => 'pavillon',
        BuildType.riziere => 'riziere',
        BuildType.theTemple => 'the',
        BuildType.bambou => 'bambou',
        BuildType.encens => 'encens',
        BuildType.autel => 'autel',
        BuildType.chemin => 'chemin',
      };

  String get asset => switch (this) {
        BuildType.pavillon => 'assets/Image/Maison.png',
        BuildType.riziere => 'assets/Image/Maison2.png',
        BuildType.theTemple => 'assets/Image/Temple.png',
        BuildType.bambou => 'assets/Image/Boutique.png',
        BuildType.encens => 'assets/Image/forge.png',
        BuildType.autel => 'assets/Image/templePetit.png',
        BuildType.chemin => 'assets/Image/chemin.png',
      };

  double get tileSize => this == BuildType.chemin ? kTileRoad : kTileBuilding;
  
  int get cost => switch (this) {
        BuildType.pavillon => 100,
        BuildType.riziere => 150,
        BuildType.theTemple => 300,
        BuildType.bambou => 200,
        BuildType.encens => 250,
        BuildType.autel => 400,
        BuildType.chemin => 25,
      };
}

enum Element { feu, eau, bois, metal, terre }

enum CorruptionPhase { serenity, fissure, oppression, horror }

extension ElementX on Element {
  String get icon => switch (this) {
        Element.feu => '🔥',
        Element.eau => '💧',
        Element.bois => '🌳',
        Element.metal => '⚔️',
        Element.terre => '🏔️',
      };
  
  Color get color => switch (this) {
        Element.feu => Colors.red,
        Element.eau => Colors.blue,
        Element.bois => Colors.green,
        Element.metal => Colors.grey,
        Element.terre => Colors.brown,
      };
}

class Building {
  final BuildType type;
  final int gx;
  final int gy;
  final String id;
  int level;
  bool isCorrupted;
  Element? assignedVillager;
  
  Building({
    required this.type, 
    required this.gx, 
    required this.gy,
    required this.id,
    this.level = 1,
    this.isCorrupted = false,
    this.assignedVillager,
  });

  double get px => gx * type.tileSize;
  double get py => gy * type.tileSize;
  
  int get production => switch (type) {
    BuildType.pavillon => 2 * level,
    BuildType.riziere => 3 * level,
    BuildType.bambou => 2 * level,
    BuildType.encens => 1 * level,
    _ => 0,
  };
}

class Villager {
  final String id;
  final String name;
  final Element affinity;
  String? assignedBuildingId;
  int sanity;
  bool isMutated;
  bool isDead;
  
  Villager({
    required this.id,
    required this.name,
    required this.affinity,
    this.assignedBuildingId,
    this.sanity = 100,
    this.isMutated = false,
    this.isDead = false,
  });
}

class GameEvent {
  final String title;
  final String description;
  final List<EventChoice> choices;
  final CorruptionPhase requiredPhase;
  
  GameEvent({
    required this.title,
    required this.description,
    required this.choices,
    required this.requiredPhase,
  });
}

class EventChoice {
  final String text;
  final Map<String, int> resourceEffects;
  final int corruptionEffect;
  final String consequence;
  
  EventChoice({
    required this.text,
    required this.resourceEffects,
    this.corruptionEffect = 0,
    required this.consequence,
  });
}

class G24 {
  final int x;
  final int y;
  const G24(this.x, this.y);
  @override
  bool operator ==(Object other) => other is G24 && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

// ===== Game Screen =====
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  // Resources
  int money = 1500;
  int rice = 45;
  int tea = 23;
  int bamboo = 18;
  int incense = 12;
  int spiritual = 7;
  int population = 3;
  
  // Elements (0-100)
  Map<Element, int> elements = {
    Element.feu: 20,
    Element.eau: 20,
    Element.bois: 20,
    Element.metal: 20,
    Element.terre: 20,
  };
  
  // Game state
  int corruption = 0;
  CorruptionPhase phase = CorruptionPhase.serenity;
  int day = 1;
  int season = 0; // 0=printemps, 1=été, 2=automne, 3=hiver
  
  // Selection & modes
  BuildType? selected;
  bool destroyMode = false;
  
  // World / transform control
  final TransformationController _tc = TransformationController();
  
  // Data
  final List<Building> _buildings = [];
  final Set<G24> _roads = {};
  final List<Villager> _villagers = [];
  
  // Ghost placement
  Offset? _ghostScenePos;
  
  // Timers
  Timer? _gameTimer;
  Timer? _eventTimer;
  
  // UI state
  GameEvent? _currentEvent;
  bool _showVillagerPanel = false;
  bool _showRitualPanel = false;
  
  // Animation controllers
  late AnimationController _corruptionAnimController;
  late AnimationController _elementAnimController;
  
  @override
  void initState() {
    super.initState();
    _corruptionAnimController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _elementAnimController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _initializeGame();
    _startGameTimer();
  }
  
  void _initializeGame() {
    // Créer les villageois initiaux
    _villagers.addAll([
      Villager(id: '1', name: 'Chen Wei', affinity: Element.eau),
      Villager(id: '2', name: 'Li Ming', affinity: Element.feu),
      Villager(id: '3', name: 'Wang Yu', affinity: Element.bois),
    ]);
    
    // Placer quelques bâtiments de départ
    _buildings.addAll([
      Building(type: BuildType.pavillon, gx: 2, gy: 2, id: 'house1'),
      Building(type: BuildType.riziere, gx: 4, gy: 2, id: 'rice1'),
    ]);
  }
  
  void _startGameTimer() {
    _gameTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _processTurn();
    });
    
    _eventTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_currentEvent == null && math.Random().nextBool()) {
        _triggerRandomEvent();
      }
    });
  }
  
  void _processTurn() {
    setState(() {
      day++;
      
      // Production de ressources
      _processProduction();
      
      // Évolution de la corruption
      _processCorruption();
      
      // Changement de saison
      if (day % 20 == 0) {
        season = (season + 1) % 4;
        _processSeasonChange();
      }
      
      // Mise à jour de la phase
      _updateCorruptionPhase();
      
      // Effets de la corruption sur les villageois
      _processVillagerSanity();
    });
  }
  
  void _processProduction() {
    for (final building in _buildings) {
      if (building.isCorrupted) continue;
      
      final villager = _villagers.firstWhere(
        (v) => v.assignedBuildingId == building.id,
        orElse: () => Villager(id: '', name: '', affinity: Element.feu),
      );
      
      final bonus = villager.id.isNotEmpty ? 1.5 : 1.0;
      final production = (building.production * bonus).round();
      
      switch (building.type) {
        case BuildType.riziere:
          rice += production;
          _modifyElement(Element.eau, 1);
          break;
        case BuildType.bambou:
          bamboo += production;
          _modifyElement(Element.bois, 1);
          break;
        case BuildType.encens:
          incense += production;
          spiritual += production;
          _modifyElement(Element.feu, 1);
          break;
        case BuildType.pavillon:
          if (population < _buildings.where((b) => b.type == BuildType.pavillon).length * 2) {
            population++;
          }
          break;
        default:
          break;
      }
    }
    
    // Consommation des villageois
    rice = math.max(0, rice - _villagers.length);
    money += population * 5;
  }
  
  void _processCorruption() {
    // Calcul du déséquilibre élémentaire
    final values = elements.values.toList();
    final avg = values.reduce((a, b) => a + b) / values.length;
    final imbalance = values.fold(0.0, (sum, val) => sum + (val - avg).abs()) / values.length;
    
    if (imbalance > 15) {
      corruption = math.min(100, corruption + 1);
    } else if (imbalance < 5) {
      corruption = math.max(0, corruption - 1);
    }
    
    // Effets de la corruption
    if (corruption > 25 && math.Random().nextDouble() < 0.1) {
      _corruptRandomBuilding();
    }
  }
  
  void _processSeasonChange() {
    switch (season) {
      case 0: // Printemps
        _modifyElement(Element.bois, 5);
        break;
      case 1: // Été
        _modifyElement(Element.feu, 5);
        break;
      case 2: // Automne
        _modifyElement(Element.metal, 5);
        break;
      case 3: // Hiver
        _modifyElement(Element.eau, 5);
        break;
    }
  }
  
  void _updateCorruptionPhase() {
    final oldPhase = phase;
    if (corruption < 25) {
      phase = CorruptionPhase.serenity;
    } else if (corruption < 50) {
      phase = CorruptionPhase.fissure;
    } else if (corruption < 75) {
      phase = CorruptionPhase.oppression;
    } else {
      phase = CorruptionPhase.horror;
    }
    
    if (oldPhase != phase) {
      _corruptionAnimController.forward(from: 0);
    }
  }
  
  void _processVillagerSanity() {
    for (final villager in _villagers) {
      if (villager.isDead) continue;
      
      // Perte de sanité due à la corruption
      if (corruption > 25) {
        villager.sanity = math.max(0, villager.sanity - (corruption ~/ 25));
      }
      
      // Mutation à haute corruption et faible sanité
      if (corruption > 50 && villager.sanity < 30 && !villager.isMutated) {
        if (math.Random().nextDouble() < 0.05) {
          villager.isMutated = true;
          _showMessage('${villager.name} a subi une mutation terrifiante...');
        }
      }
      
      // Mort à sanité 0
      if (villager.sanity <= 0 && !villager.isDead) {
        villager.isDead = true;
        population = math.max(0, population - 1);
        _showMessage('${villager.name} a succombé à la folie...');
      }
    }
  }
  
  void _corruptRandomBuilding() {
    final uncorrupted = _buildings.where((b) => !b.isCorrupted).toList();
    if (uncorrupted.isNotEmpty) {
      final building = uncorrupted[math.Random().nextInt(uncorrupted.length)];
      building.isCorrupted = true;
      _showMessage('${building.type.keyName} a été corrompue par les ténèbres...');
    }
  }
  
  void _modifyElement(Element element, int delta) {
    elements[element] = (elements[element]! + delta).clamp(0, 100);
    _elementAnimController.forward(from: 0);
  }
  
  void _triggerRandomEvent() {
    final events = _getEventsForPhase(phase);
    if (events.isNotEmpty) {
      setState(() {
        _currentEvent = events[math.Random().nextInt(events.length)];
      });
    }
  }
  
  List<GameEvent> _getEventsForPhase(CorruptionPhase phase) {
    switch (phase) {
      case CorruptionPhase.serenity:
        return [
          GameEvent(
            title: 'Récolte abondante',
            description: 'Les champs offrent une récolte exceptionnelle.',
            requiredPhase: phase,
            choices: [
              EventChoice(
                text: 'Célébrer avec un festival',
                resourceEffects: {'rice': 20, 'money': -50},
                consequence: 'Le moral des villageois s\'améliore',
              ),
              EventChoice(
                text: 'Stocker prudemment',
                resourceEffects: {'rice': 30},
                consequence: 'Réserves augmentées',
              ),
            ],
          ),
        ];
      case CorruptionPhase.fissure:
        return [
          GameEvent(
            title: 'Récoltes pourries',
            description: 'Certaines récoltes pourrissent sans raison apparente.',
            requiredPhase: phase,
            choices: [
              EventChoice(
                text: 'Brûler les récoltes infectées',
                resourceEffects: {'rice': -15},
                corruptionEffect: -2,
                consequence: 'Propagation stoppée',
              ),
              EventChoice(
                text: 'Ignorer le problème',
                resourceEffects: {},
                corruptionEffect: 5,
                consequence: 'La corruption se répand...',
              ),
            ],
          ),
        ];
      case CorruptionPhase.oppression:
        return [
          GameEvent(
            title: 'Ombres dans la brume',
            description: 'Des silhouettes inquiétantes rôdent dans le village.',
            requiredPhase: phase,
            choices: [
              EventChoice(
                text: 'Organiser des patrouilles',
                resourceEffects: {'money': -100},
                corruptionEffect: -3,
                consequence: 'Sécurité renforcée temporairement',
              ),
              EventChoice(
                text: 'Se barricader',
                resourceEffects: {'bamboo': -20},
                corruptionEffect: 2,
                consequence: 'Moral en baisse, peur grandissante',
              ),
            ],
          ),
        ];
      case CorruptionPhase.horror:
        return [
          GameEvent(
            title: 'Pacte des Ténèbres',
            description: 'Une entité propose un pacte pour sauver le village...',
            requiredPhase: phase,
            choices: [
              EventChoice(
                text: 'Accepter le pacte',
                resourceEffects: {'spiritual': -50, 'money': 500},
                corruptionEffect: 10,
                consequence: 'Puissance obtenue au prix de l\'âme',
              ),
              EventChoice(
                text: 'Refuser courageusement',
                resourceEffects: {'population': -1},
                corruptionEffect: -5,
                consequence: 'Sacrifice héroïque',
              ),
            ],
          ),
        ];
    }
  }
  
  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: phase == CorruptionPhase.horror ? Colors.red.shade900 : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Grid visibility
  bool get showBuildingGrid => selected != null && selected != BuildType.chemin && !destroyMode;
  bool get showRoadGrid => selected == BuildType.chemin && !destroyMode;

  @override
  void dispose() {
    _tc.dispose();
    _gameTimer?.cancel();
    _eventTimer?.cancel();
    _corruptionAnimController.dispose();
    _elementAnimController.dispose();
    super.dispose();
  }

  // ===== Helpers =====
  Offset toScene(Offset p) => _tc.toScene(p);

  Offset snapForSelected(Offset scenePoint) {
    final size = selected?.tileSize ?? kTileBuilding;
    final sx = (scenePoint.dx / size).floor() * size;
    final sy = (scenePoint.dy / size).floor() * size;
    return Offset(sx.toDouble(), sy.toDouble());
  }

  G24 _posToG24(Offset scenePoint) {
    final gx = (scenePoint.dx / kTileRoad).floor();
    final gy = (scenePoint.dy / kTileRoad).floor();
    return G24(gx, gy);
  }

  void _placeAt(Offset scenePoint) {
    if (selected == null) return;
    final type = selected!;
    
    // Vérifier si on a assez d'argent
    if (money < type.cost) {
      _showMessage('Pas assez d\'argent !');
      return;
    }

    if (type == BuildType.chemin) {
      final g = _posToG24(scenePoint);
      if (_roads.contains(g)) return;
      setState(() {
        _roads.add(g);
        money -= type.cost;
      });
      return;
    }

    final size = type.tileSize;
    final gx = (scenePoint.dx / size).floor();
    final gy = (scenePoint.dy / size).floor();
    final exists = _buildings.any((b) => b.type.tileSize == size && b.gx == gx && b.gy == gy);
    if (exists) return;

    setState(() {
      _buildings.add(Building(
        type: type, 
        gx: gx, 
        gy: gy, 
        id: 'building_${DateTime.now().millisecondsSinceEpoch}'
      ));
      money -= type.cost;
    });
  }

  void _destroyAt(Offset scenePoint) {
    final g = _posToG24(scenePoint);
    if (_roads.remove(g)) {
      setState(() {});
      return;
    }

    final idx = _buildings.indexWhere((b) {
      final size = b.type.tileSize;
      final left = b.gx * size;
      final top = b.gy * size;
      return scenePoint.dx >= left && scenePoint.dx < left + size && scenePoint.dy >= top && scenePoint.dy < top + size;
    });
    if (idx != -1) {
      setState(() {
        _buildings.removeAt(idx);
      });
    }
  }

  void _updateGhostFromLocal(Offset localPosition) {
    if (destroyMode || selected == null) {
      setState(() => _ghostScenePos = null);
      return;
    }
    final scene = toScene(localPosition);
    final snapped = snapForSelected(scene);
    setState(() => _ghostScenePos = snapped);
  }

  String _roadConnectionsOf(G24 g) {
    final hasN = _roads.contains(G24(g.x, g.y - 1));
    final hasS = _roads.contains(G24(g.x, g.y + 1));
    final hasE = _roads.contains(G24(g.x + 1, g.y));
    final hasW = _roads.contains(G24(g.x - 1, g.y));
    final buf = StringBuffer();
    if (hasN) buf.write('N');
    if (hasS) buf.write('S');
    if (hasE) buf.write('E');
    if (hasW) buf.write('W');
    return buf.toString();
  }

  double _rotationForConnections(String conn) {
    return switch (conn) {
      'NS' => 0,
      'EW' => math.pi / 2,
      'NE' => 0,
      'SE' => math.pi / 2,
      'SW' => math.pi,
      'NW' => 3 * math.pi / 2,
      'NEW' => 0,
      'NSE' => math.pi / 2,
      'SEW' => math.pi,
      'NSW' => 3 * math.pi / 2,
      'NSEW' => 0,
      'N' => 0,
      'E' => math.pi / 2,
      'S' => math.pi,
      'W' => 3 * math.pi / 2,
      '' => 0,
      _ => 0,
    };
  }

  Color _getBackgroundColor() {
    switch (phase) {
      case CorruptionPhase.serenity:
        return const Color(0xFFF5F1E6);
      case CorruptionPhase.fissure:
        return const Color(0xFFF0EDE0);
      case CorruptionPhase.oppression:
        return const Color(0xFFE8E4D7);
      case CorruptionPhase.horror:
        return const Color(0xFFDDD9CC);
    }
  }

  String _getSeasonName() {
    switch (season) {
      case 0: return '🌸 Printemps';
      case 1: return '☀️ Été';
      case 2: return '🍂 Automne';
      case 3: return '❄️ Hiver';
      default: return '';
    }
  }

  String _getPhaseName() {
    switch (phase) {
      case CorruptionPhase.serenity: return '平和 (Sérénité)';
      case CorruptionPhase.fissure: return '裂縫 (Fissure)';
      case CorruptionPhase.oppression: return '壓迫 (Oppression)';
      case CorruptionPhase.horror: return '恐怖 (Horreur)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final seal = Color.lerp(const Color(0xFF9C1E1E), Colors.black, corruption / 100) ?? const Color(0xFF9C1E1E);

    return Scaffold(
      backgroundColor: _getBackgroundColor(),
      appBar: AppBar(
        toolbarHeight: 100,
        elevation: 6,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                seal.withOpacity(.9), 
                Color.lerp(const Color(0xFFB8860B), Colors.red.shade900, corruption / 100)!.withOpacity(.9)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border(bottom: BorderSide(color: seal, width: 2)),
          ),
        ),
        titleSpacing: 12,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MoneyBadge(value: money),
            const SizedBox(height: 4),
            Text(
              'Jour $day - ${_getSeasonName()} - ${_getPhaseName()}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          Column(
            children: [
              _ResourceBar(
                rice: rice,
                tea: tea,
                bamboo: bamboo,
                incense: incense,
                spiritual: spiritual,
                population: population,
              ),
              const SizedBox(height: 8),
              _ElementBar(elements: elements, corruption: corruption),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Stack(
        children: [
          // Monde principal
          Listener(
            onPointerHover: (evt) => _updateGhostFromLocal(evt.localPosition),
            child: InteractiveViewer(
              transformationController: _tc,
              minScale: 1,
              maxScale: 3,
              panEnabled: true,
              scaleEnabled: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final scene = toScene(d.localPosition);
                  if (destroyMode) {
                    _destroyAt(scene);
                  } else {
                    _placeAt(scene);
                  }
                },
                onPanUpdate: (d) => _updateGhostFromLocal(d.localPosition),
                onPanStart: (d) => _updateGhostFromLocal(d.localPosition),
                onPanEnd: (_) => setState(() => _ghostScenePos = null),
                child: Stack(
                  children: [
                    // Arrière-plan avec effet de corruption
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _corruptionAnimController,
                        builder: (context, child) {
                          return Container(
                            decoration: BoxDecoration(
                              image: DecorationImage(
                                image: const AssetImage('assets/Image/here.png'),
                                fit: BoxFit.cover,
                                colorFilter: corruption > 0 ? ColorFilter.mode(
                                  Colors.black.withOpacity(corruption / 200),
                                  BlendMode.darken,
                                ) : null,
                              ),
                            ),
                            child: corruption > 50 ? CustomPaint(
                              painter: _CorruptionPainter(
                                corruption: corruption,
                                animation: _corruptionAnimController.value,
                              ),
                            ) : null,
                          );
                        },
                      ),
                    ),

                    // Grilles
                    if (showBuildingGrid)
                      const _GridOverlay(tile: kTileBuilding, color: Color(0x26000000)),
                    if (showRoadGrid)
                      const _GridOverlay(tile: kTileRoad, color: Color(0x26FF0000)),

                    // Bâtiments
                    ..._buildings.map((b) => Positioned(
                          left: b.px,
                          top: b.py,
                          width: b.type.tileSize,
                          height: b.type.tileSize,
                          child: GestureDetector(
                            onTap: () => _showBuildingInfo(b),
                            child: _Sprite(
                              asset: b.type.asset,
                              isCorrupted: b.isCorrupted,
                              corruptionLevel: corruption,
                            ),
                          ),
                        )),

                    // Routes
                    ..._roads.map((g) {
                      final left = g.x * kTileRoad;
                      final top = g.y * kTileRoad;
                      final conn = _roadConnectionsOf(g);
                      final rot = _rotationForConnections(conn);
                      return Positioned(
                        left: left.toDouble(),
                        top: top.toDouble(),
                        width: kTileRoad,
                        height: kTileRoad,
                        child: Transform.rotate(
                          angle: rot,
                          alignment: Alignment.center,
                          child: _Sprite(
                            asset: BuildType.chemin.asset,
                            isCorrupted: false,
                            corruptionLevel: corruption,
                          ),
                        ),
                      );
                    }).toList(),

                    // Villageois (points animés)
                    ..._villagers.where((v) => !v.isDead).map((v) {
                      final building = v.assignedBuildingId != null 
                        ? _buildings.firstWhere(
                            (b) => b.id == v.assignedBuildingId,
                            orElse: () => Building(type: BuildType.pavillon, gx: 0, gy: 0, id: ''),
                          )
                        : null;
                      
                      final x = building != null 
                        ? building.px + building.type.tileSize / 2
                        : math.Random().nextDouble() * 500;
                      final y = building != null 
                        ? building.py + building.type.tileSize / 2
                        : math.Random().nextDouble() * 500;
                      
                      return Positioned(
                        left: x - 12,
                        top: y - 12,
                        child: GestureDetector(
                          onTap: () => _showVillagerInfo(v),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: v.isMutated 
                                ? Colors.purple.shade900
                                : v.affinity.color.withOpacity(0.8),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: v.sanity < 50 ? Colors.red : Colors.white,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                v.affinity.icon,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),

                    // Fantôme de placement
                    if (_ghostScenePos != null && !destroyMode)
                      Positioned(
                        left: _ghostScenePos!.dx,
                        top: _ghostScenePos!.dy,
                        width: (selected?.tileSize ?? kTileBuilding),
                        height: (selected?.tileSize ?? kTileBuilding),
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: money >= (selected?.cost ?? 0) ? Colors.green : Colors.red,
                                width: 2,
                                style: BorderStyle.solid,
                              ),
                              color: (money >= (selected?.cost ?? 0) ? Colors.green : Colors.red).withOpacity(0.1),
                            ),
                            child: Center(
                              child: Text(
                                '${selected?.cost ?? 0} 金',
                                style: TextStyle(
                                  color: money >= (selected?.cost ?? 0) ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Interface utilisateur
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _getBackgroundColor().withOpacity(0.9),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.15),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _BuildCard(
                    label: '🏠 Maison',
                    cost: BuildType.pavillon.cost,
                    isSelected: selected == BuildType.pavillon,
                    canAfford: money >= BuildType.pavillon.cost,
                    onTap: () => setState(() {
                      selected = BuildType.pavillon;
                      destroyMode = false;
                    }),
                  ),
                  _BuildCard(
                    label: '🌾 Rizière',
                    cost: BuildType.riziere.cost,
                    isSelected: selected == BuildType.riziere,
                    canAfford: money >= BuildType.riziere.cost,
                    onTap: () => setState(() {
                      selected = BuildType.riziere;
                      destroyMode = false;
                    }),
                  ),
                  _BuildCard(
                    label: '⛩️ Temple',
                    cost: BuildType.theTemple.cost,
                    isSelected: selected == BuildType.theTemple,
                    canAfford: money >= BuildType.theTemple.cost,
                    onTap: () => setState(() {
                      selected = BuildType.theTemple;
                      destroyMode = false;
                    }),
                  ),
                  _BuildCard(
                    label: '🏪 Boutique',
                    cost: BuildType.bambou.cost,
                    isSelected: selected == BuildType.bambou,
                    canAfford: money >= BuildType.bambou.cost,
                    onTap: () => setState(() {
                      selected = BuildType.bambou;
                      destroyMode = false;
                    }),
                  ),
                  _BuildCard(
                    label: '⚒️ Forge',
                    cost: BuildType.encens.cost,
                    isSelected: selected == BuildType.encens,
                    canAfford: money >= BuildType.encens.cost,
                    onTap: () => setState(() {
                      selected = BuildType.encens;
                      destroyMode = false;
                    }),
                  ),
                  _BuildCard(
                    label: '🛕 Autel',
                    cost: BuildType.autel.cost,
                    isSelected: selected == BuildType.autel,
                    canAfford: money >= BuildType.autel.cost,
                    onTap: () => setState(() {
                      selected = BuildType.autel;
                      destroyMode = false;
                    }),
                  ),
                  _MenuBtn(
                    label: '🛣️',
                    isSelected: selected == BuildType.chemin,
                    onTap: () => setState(() {
                      selected = BuildType.chemin;
                      destroyMode = false;
                    }),
                  ),
                  _MenuBtn(
                    label: '🗑️',
                    isSelected: destroyMode,
                    onTap: () => setState(() {
                      selected = null;
                      destroyMode = true;
                      _ghostScenePos = null;
                    }),
                  ),
                  _MenuBtn(
                    label: '👥',
                    isSelected: _showVillagerPanel,
                    onTap: () => setState(() {
                      _showVillagerPanel = !_showVillagerPanel;
                    }),
                  ),
                  if (corruption > 25)
                    _MenuBtn(
                      label: '🕯️',
                      isSelected: _showRitualPanel,
                      onTap: () => setState(() {
                        _showRitualPanel = !_showRitualPanel;
                      }),
                    ),
                ],
              ),
            ),
          ),

          // Panneau des villageois
          if (_showVillagerPanel)
            Positioned(
              right: 16,
              bottom: 100,
              child: _VillagerPanel(
                villagers: _villagers,
                buildings: _buildings,
                onAssign: _assignVillager,
                onDismiss: () => setState(() => _showVillagerPanel = false),
              ),
            ),

          // Panneau des rituels
          if (_showRitualPanel)
            Positioned(
              left: 16,
              bottom: 100,
              child: _RitualPanel(
                corruption: corruption,
                phase: phase,
                resources: {
                  'rice': rice,
                  'tea': tea,
                  'bamboo': bamboo,
                  'incense': incense,
                  'spiritual': spiritual,
                },
                onPerformRitual: _performRitual,
                onDismiss: () => setState(() => _showRitualPanel = false),
              ),
            ),

          // Événement modal
          if (_currentEvent != null)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.7),
                child: Center(
                  child: _EventModal(
                    event: _currentEvent!,
                    onChoiceMade: _handleEventChoice,
                  ),
                ),
              ),
            ),

          // Barre de corruption
          Positioned(
            top: 16,
            left: 16,
            child: _CorruptionBar(corruption: corruption, phase: phase),
          ),
        ],
      ),
    );
  }

  void _showBuildingInfo(Building building) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${building.type.keyName} ${building.isCorrupted ? '(Corrompue)' : ''}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Niveau: ${building.level}'),
            Text('Production: ${building.production}/tour'),
            if (building.assignedVillager != null)
              Text('Assigné: ${building.assignedVillager!.icon}'),
            if (building.isCorrupted)
              const Text('⚠️ Bâtiment corrompu - Production arrêtée', 
                style: TextStyle(color: Colors.red)),
          ],
        ),
        actions: [
          if (!building.isCorrupted && spiritual >= 20)
            TextButton(
              onPressed: () {
                setState(() {
                  building.level++;
                  spiritual -= 20;
                });
                Navigator.pop(context);
              },
              child: const Text('Améliorer (20 🕯️)'),
            ),
          if (building.isCorrupted && spiritual >= 50)
            TextButton(
              onPressed: () {
                setState(() {
                  building.isCorrupted = false;
                  spiritual -= 50;
                });
                Navigator.pop(context);
              },
              child: const Text('Purifier (50 🕯️)'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  void _showVillagerInfo(Villager villager) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${villager.name} ${villager.affinity.icon}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Affinité: ${villager.affinity.icon}'),
            Text('Sanité: ${villager.sanity}/100'),
            if (villager.isMutated)
              const Text('🧬 Mutant', style: TextStyle(color: Colors.purple)),
            if (villager.assignedBuildingId != null)
              Text('Assigné au bâtiment: ${villager.assignedBuildingId}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  void _assignVillager(String villagerId, String? buildingId) {
    setState(() {
      final villager = _villagers.firstWhere((v) => v.id == villagerId);
      villager.assignedBuildingId = buildingId;
    });
  }

  void _performRitual(String ritualType, Map<String, int> cost) {
    // Vérifier si on peut payer
    bool canAfford = true;
    cost.forEach((resource, amount) {
      switch (resource) {
        case 'rice': if (rice < amount) canAfford = false; break;
        case 'tea': if (tea < amount) canAfford = false; break;
        case 'bamboo': if (bamboo < amount) canAfford = false; break;
        case 'incense': if (incense < amount) canAfford = false; break;
        case 'spiritual': if (spiritual < amount) canAfford = false; break;
        case 'population': if (population < amount) canAfford = false; break;
      }
    });

    if (!canAfford) {
      _showMessage('Ressources insuffisantes pour ce rituel');
      return;
    }

    // Payer le coût
    setState(() {
      cost.forEach((resource, amount) {
        switch (resource) {
          case 'rice': rice -= amount; break;
          case 'tea': tea -= amount; break;
          case 'bamboo': bamboo -= amount; break;
          case 'incense': incense -= amount; break;
          case 'spiritual': spiritual -= amount; break;
          case 'population': population -= amount; break;
        }
      });

      // Effets du rituel
      switch (ritualType) {
        case 'purification':
          corruption = math.max(0, corruption - 10);
          _showMessage('Rituel de purification accompli');
          break;
        case 'equilibrium':
          // Rééquilibrer les éléments
          final avg = elements.values.reduce((a, b) => a + b) ~/ elements.length;
          elements.forEach((element, value) {
            elements[element] = ((value + avg) / 2).round().clamp(0, 100);
          });
          _showMessage('L\'équilibre élémentaire est restauré');
          break;
        case 'sacrifice':
          corruption = math.max(0, corruption - 20);
          spiritual += 30;
          _showMessage('Le sacrifice a apaisé les forces obscures...');
          break;
      }
    });
  }

  void _handleEventChoice(EventChoice choice) {
    setState(() {
      // Appliquer les effets sur les ressources
      choice.resourceEffects.forEach((resource, delta) {
        switch (resource) {
          case 'rice': rice = math.max(0, rice + delta); break;
          case 'tea': tea = math.max(0, tea + delta); break;
          case 'bamboo': bamboo = math.max(0, bamboo + delta); break;
          case 'incense': incense = math.max(0, incense + delta); break;
          case 'spiritual': spiritual = math.max(0, spiritual + delta); break;
          case 'money': money = math.max(0, money + delta); break;
          case 'population': population = math.max(0, population + delta); break;
        }
      });

      // Appliquer l'effet de corruption
      corruption = (corruption + choice.corruptionEffect).clamp(0, 100);

      // Fermer l'événement
      _currentEvent = null;
    });

    _showMessage(choice.consequence);
  }
}

// ===== Composants UI =====

class _Sprite extends StatelessWidget {
  final String asset;
  final bool isCorrupted;
  final int corruptionLevel;
  
  const _Sprite({
    required this.asset, 
    required this.isCorrupted,
    required this.corruptionLevel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(asset), 
          fit: BoxFit.contain,
          colorFilter: isCorrupted 
            ? const ColorFilter.mode(Colors.red, BlendMode.modulate)
            : corruptionLevel > 50 
              ? ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.darken)
              : null,
        ),
        boxShadow: [
          BoxShadow(
            color: isCorrupted 
              ? Colors.red.withOpacity(0.5)
              : Colors.black.withOpacity(0.3),
            blurRadius: isCorrupted ? 8 : 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
    );
  }
}

class _GridOverlay extends StatelessWidget {
  final double tile;
  final Color color;
  const _GridOverlay({required this.tile, required this.color});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _GridPainter(tile: tile, color: color),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final double tile;
  final Color color;
  _GridPainter({required this.tile, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += tile) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += tile) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => 
    oldDelegate.tile != tile || oldDelegate.color != color;
}

class _CorruptionPainter extends CustomPainter {
  final int corruption;
  final double animation;

  _CorruptionPainter({required this.corruption, required this.animation});

  @override
  void paint(Canvas canvas, Size size) {
    if (corruption < 50) return;

    final paint = Paint()
      ..color = Colors.black.withOpacity((corruption - 50) / 100 * 0.5)
      ..style = PaintingStyle.fill;

    // Dessiner des "fissures" qui s'étendent avec l'animation
    final random = math.Random(42); // Seed fixe pour cohérence
    for (int i = 0; i < corruption ~/ 10; i++) {
      final startX = random.nextDouble() * size.width;
      final startY = random.nextDouble() * size.height;
      final length = 100 * animation;
      final angle = random.nextDouble() * 2 * math.pi;
      
      final endX = startX + math.cos(angle) * length;
      final endY = startY + math.sin(angle) * length;
      
      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, endY),
        Paint()
          ..color = Colors.red.withOpacity(0.3)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CorruptionPainter oldDelegate) =>
    oldDelegate.corruption != corruption || oldDelegate.animation != animation;
}

class _MoneyBadge extends StatelessWidget {
  final int value;
  const _MoneyBadge({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xF2F5F1E6),
        border: Border.all(color: const Color(0xFFB8860B), width: 2),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('💰', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text('$value', style: const TextStyle(
            fontSize: 18, 
            fontWeight: FontWeight.w700, 
            color: Color(0xFF9C1E1E),
          )),
          const SizedBox(width: 4),
          const Text('金', style: TextStyle(
            fontSize: 14, 
            color: Color(0xFF9C1E1E),
          )),
        ],
      ),
    );
  }
}

class _ResourceBar extends StatelessWidget {
  final int rice, tea, bamboo, incense, spiritual, population;
  
  const _ResourceBar({
    required this.rice,
    required this.tea,
    required this.bamboo,
    required this.incense,
    required this.spiritual,
    required this.population,
  });

  Widget _chip(String icon, int v) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xE6F5F1E6),
          border: Border.all(color: const Color(0x999C1E1E), width: 1),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.1),
              blurRadius: 4,
              offset: const Offset(0, 1),
            )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text('$v', style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
            )),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _chip('🌾', rice),
      _chip('🍃', tea),
      _chip('🎋', bamboo),
      _chip('🕯️', incense),
      _chip('⛩️', spiritual),
      _chip('👥', population),
    ]);
  }
}

class _ElementBar extends StatelessWidget {
  final Map<Element, int> elements;
  final int corruption;
  
  const _ElementBar({required this.elements, required this.corruption});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: Element.values.map((element) {
        final value = elements[element]!;
        final color = Color.lerp(
          element.color,
          Colors.black,
          corruption / 200,
        )!;
        
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 30,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            widthFactor: value / 100,
            alignment: Alignment.centerLeft,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CorruptionBar extends StatelessWidget {
  final int corruption;
  final CorruptionPhase phase;
  
  const _CorruptionBar({required this.corruption, required this.phase});

  @override
  Widget build(BuildContext context) {
    final phaseColor = switch (phase) {
      CorruptionPhase.serenity => Colors.green,
      CorruptionPhase.fissure => Colors.orange,
      CorruptionPhase.oppression => Colors.red,
      CorruptionPhase.horror => Colors.purple.shade900,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '腐敗 Corruption',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 200,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(6),
            ),
            child: FractionallySizedBox(
              widthFactor: corruption / 100,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  color: phaseColor,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$corruption/100 - ${_getPhaseName(phase)}',
            style: TextStyle(
              color: phaseColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _getPhaseName(CorruptionPhase phase) {
    switch (phase) {
      case CorruptionPhase.serenity: return 'Sérénité';
      case CorruptionPhase.fissure: return 'Fissure';
      case CorruptionPhase.oppression: return 'Oppression';
      case CorruptionPhase.horror: return 'Horreur';
    }
  }
}

class _BuildCard extends StatelessWidget {
  final String label;
  final int cost;
  final bool isSelected;
  final bool canAfford;
  final VoidCallback onTap;

  const _BuildCard({
    required this.label,
    required this.cost,
    required this.isSelected,
    required this.canAfford,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      child: InkWell(
        onTap: canAfford ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF9C1E1E) : const Color(0xFFF5F1E6),
            border: Border.all(
              color: canAfford ? const Color(0xFF9C1E1E) : Colors.grey,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected ? Colors.white : (canAfford ? Colors.black : Colors.grey),
                ),
              ),
              Text(
                '$cost金',
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? Colors.white70 : (canAfford ? Colors.black54 : Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuBtn extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  
  const _MenuBtn({
    required this.label, 
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF9C1E1E) : const Color(0xFFF5F1E6),
            border: Border.all(color: const Color(0xFF9C1E1E), width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: isSelected ? Colors.white : Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VillagerPanel extends StatelessWidget {
  final List<Villager> villagers;
  final List<Building> buildings;
  final Function(String, String?) onAssign;
  final VoidCallback onDismiss;

  const _VillagerPanel({
    required this.villagers,
    required this.buildings,
    required this.onAssign,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: 400,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F1E6),
        border: Border.all(color: const Color(0xFF9C1E1E), width: 2),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '👥 Villageois',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: villagers.length,
              itemBuilder: (context, index) {
                final villager = villagers[index];
                if (villager.isDead) return const SizedBox.shrink();
                
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              villager.affinity.icon,
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    villager.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: villager.isMutated ? Colors.purple : Colors.black,
                                    ),
                                  ),
                                  Text(
                                    'Sanité: ${villager.sanity}/100',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: villager.sanity < 50 ? Colors.red : Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButton<String?>(
                          isExpanded: true,
                          value: villager.assignedBuildingId,
                          hint: const Text('Assigner à un bâtiment'),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Aucune assignation'),
                            ),
                            ...buildings
                                .where((b) => !b.isCorrupted)
                                .map((b) => DropdownMenuItem(
                                      value: b.id,
                                      child: Text('${b.type.keyName} (${b.gx},${b.gy})'),
                                    )),
                          ],
                          onChanged: (value) => onAssign(villager.id, value),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RitualPanel extends StatelessWidget {
  final int corruption;
  final CorruptionPhase phase;
  final Map<String, int> resources;
  final Function(String, Map<String, int>) onPerformRitual;
  final VoidCallback onDismiss;

  const _RitualPanel({
    required this.corruption,
    required this.phase,
    required this.resources,
    required this.onPerformRitual,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: 400,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F1E6),
        border: Border.all(color: const Color(0xFF9C1E1E), width: 2),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '🕯️ Rituels',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: ListView(
              children: [
                _RitualCard(
                  title: 'Purification Mineure',
                  description: 'Réduit la corruption de 10 points',
                  cost: {'spiritual': 20, 'incense': 10},
                  resources: resources,
                  onPerform: () => onPerformRitual('purification', {'spiritual': 20, 'incense': 10}),
                ),
                if (corruption > 40)
                  _RitualCard(
                    title: 'Équilibre Élémentaire',
                    description: 'Rééquilibre tous les éléments',
                    cost: {'spiritual': 30, 'tea': 15, 'bamboo': 10},
                    resources: resources,
                    onPerform: () => onPerformRitual('equilibrium', {'spiritual': 30, 'tea': 15, 'bamboo': 10}),
                  ),
                if (phase == CorruptionPhase.horror)
                  _RitualCard(
                    title: 'Sacrifice Sanglant',
                    description: 'Sacrifice un villageois pour apaiser les ténèbres',
                    cost: {'population': 1, 'spiritual': 10},
                    resources: resources,
                    onPerform: () => onPerformRitual('sacrifice', {'population': 1, 'spiritual': 10}),
                    isDangerous: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RitualCard extends StatelessWidget {
  final String title;
  final String description;
  final Map<String, int> cost;
  final Map<String, int> resources;
  final VoidCallback onPerform;
  final bool isDangerous;

  const _RitualCard({
    required this.title,
    required this.description,
    required this.cost,
    required this.resources,
    required this.onPerform,
    this.isDangerous = false,
  });

  bool get canAfford {
    return cost.entries.every((entry) {
      final resource = entry.key;
      final amount = entry.value;
      return (resources[resource] ?? 0) >= amount;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isDangerous ? Colors.red.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDangerous ? Colors.red.shade800 : Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: cost.entries.map((entry) {
                final resourceIcon = _getResourceIcon(entry.key);
                final hasEnough = (resources[entry.key] ?? 0) >= entry.value;
                return Chip(
                  label: Text(
                    '$resourceIcon ${entry.value}',
                    style: TextStyle(
                      fontSize: 12,
                      color: hasEnough ? Colors.green.shade800 : Colors.red.shade800,
                    ),
                  ),
                  backgroundColor: hasEnough ? Colors.green.shade100 : Colors.red.shade100,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: canAfford ? onPerform : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDangerous ? Colors.red.shade700 : null,
                foregroundColor: isDangerous ? Colors.white : null,
              ),
              child: Text(isDangerous ? 'Accomplir le sacrifice' : 'Effectuer le rituel'),
            ),
          ],
        ),
      ),
    );
  }

  String _getResourceIcon(String resource) {
    switch (resource) {
      case 'rice': return '🌾';
      case 'tea': return '🍃';
      case 'bamboo': return '🎋';
      case 'incense': return '🕯️';
      case 'spiritual': return '⛩️';
      case 'population': return '👥';
      default: return '❓';
    }
  }
}

class _EventModal extends StatelessWidget {
  final GameEvent event;
  final Function(EventChoice) onChoiceMade;

  const _EventModal({
    required this.event,
    required this.onChoiceMade,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      margin: const EdgeInsets.all(32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F1E6),
        border: Border.all(color: const Color(0xFF9C1E1E), width: 3),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF9C1E1E),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            event.description,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 24),
          ...event.choices.map((choice) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => onChoiceMade(choice),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: choice.corruptionEffect > 0 
                        ? Colors.red.shade100 
                        : choice.corruptionEffect < 0 
                          ? Colors.green.shade100 
                          : null,
                      foregroundColor: const Color(0xFF9C1E1E),
                      padding: const EdgeInsets.all(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          choice.text,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (choice.resourceEffects.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            children: choice.resourceEffects.entries
                                .map((e) => Text(
                                      '${_getResourceIcon(e.key)} ${e.value > 0 ? '+' : ''}${e.value}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: e.value > 0 ? Colors.green : Colors.red,
                                      ),
                                    ))
                                .toList(),
                          ),
                        ],
                        if (choice.corruptionEffect != 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Corruption: ${choice.corruptionEffect > 0 ? '+' : ''}${choice.corruptionEffect}',
                            style: TextStyle(
                              fontSize: 12,
                              color: choice.corruptionEffect > 0 ? Colors.red : Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  String _getResourceIcon(String resource) {
    switch (resource) {
      case 'rice': return '🌾';
      case 'tea': return '🍃';
      case 'bamboo': return '🎋';
      case 'incense': return '🕯️';
      case 'spiritual': return '⛩️';
      case 'money': return '💰';
      case 'population': return '👥';
      default: return '❓';
    }
  }
}
