import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CryptoEMA(),
    );
  }
}

class CoinData {
  final String symbol;
  final String name;
  double price;
  double ema50;
  double ema200;
  String latestSignal;
  String signalTime;
  Trade? activeTrade;
  List<Trade> tradeHistory;
  List<Map<String, String>> signalHistory;

  CoinData({
    required this.symbol,
    required this.name,
    this.price = 0.0,
    this.ema50 = 0.0,
    this.ema200 = 0.0,
    this.latestSignal = '',
    this.signalTime = '',
    this.activeTrade,
    List<Trade>? tradeHistory,
    List<Map<String, String>>? signalHistory,
  }) : tradeHistory = tradeHistory ?? [],
       signalHistory = signalHistory ?? [];
  
  String get position {
    if (activeTrade == null) return 'Neutral';
    return activeTrade!.type == 'long' ? 'Long' : 'Short';
  }
}

class Trade {
  final String symbol;
  final String type; // 'long' or 'short'
  final double entryPrice;
  final double stopLoss;
  final double takeProfit;
  final double margin;
  final double leverage;
  final double quantity;
  final String entryTime;
  String? exitTime;
  double? exitPrice;
  String? exitReason; // 'stop_loss', 'take_profit', 'new_signal'
  double? pnl;
  bool isActive;

  Trade({
    required this.symbol,
    required this.type,
    required this.entryPrice,
    required this.stopLoss,
    required this.takeProfit,
    required this.margin,
    required this.leverage,
    required this.quantity,
    required this.entryTime,
    this.exitTime,
    this.exitPrice,
    this.exitReason,
    this.pnl,
    this.isActive = true,
  });
}

class CryptoEMA extends StatefulWidget {
  @override
  _CryptoEMAState createState() => _CryptoEMAState();
}

class _CryptoEMAState extends State<CryptoEMA> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  final TextEditingController _fastLengthController = TextEditingController(text: '12');
  final TextEditingController _slowLengthController = TextEditingController(text: '26');
  final TextEditingController _signalLengthController = TextEditingController(text: '9');
  final TextEditingController _stopLossController = TextEditingController(text: '10');
  final TextEditingController _takeProfitController = TextEditingController(text: '0.01');
  final TextEditingController _marginController = TextEditingController(text: '10');
  final TextEditingController _leverageController = TextEditingController(text: '10');
  
  String _timeframe = '5m';
  Timer? _priceTimer;
  Timer? _dataTimer;
  
  // Trading variables
  bool _isTrading = false;
  DateTime? _tradeStartTime;
  double _totalPnL = 0.0;
  double _totalProfit = 0.0;
  double _totalLoss = 0.0;
  int _winningTrades = 0;
  int _losingTrades = 0;
  
  // Signal confirmation variables
  Map<String, String> _signalConfirmationStatus = {};
  Map<String, String> _pendingSignals = {};
  
  // Available coins
  final Map<String, String> _availableCoins = {
    'BTC': 'Bitcoin (BTC)',
    'ETH': 'Ethereum (ETH)',
    'BNB': 'Binance Coin (BNB)',
    'XRP': 'Ripple (XRP)',
    'SOL': 'Solana (SOL)',
    'DOGE': 'Dogecoin (DOGE)',
    'HBAR': 'Hedera (HBAR)',
    'SUI': 'Sui (SUI)',
    'DOGS': 'Dogs (DOGS)',
    'CATI': 'Cati (CATI)',
    'FUN': 'FunToken (FUN)',
    'GNS': 'Gains Network (GNS)',
    'DATA': 'Streamr (DATA)',
    'TUT': 'Tutellus (TUT)',
    'FORM': 'Formation Fi (FORM)',
    'MUBARAK': 'Mubarak (MUBARAK)',
    'KAIA': 'Kaia (KAIA)',
    'S': 'S Token (S)',
    'PARTI': 'Parti (PARTI)',
    'NEIRO': 'Neiro (NEIRO)',
    'PHA': 'Phala Network (PHA)',
    'ZRO': 'LayerZero (ZRO)',
    'SHELL': 'Shell (SHELL)',
    'AR': 'Arweave (AR)',
    'AWE': 'Awe (AWE)',
    'FLM': 'Flamingo (FLM)',
    'ICX': 'ICON (ICX)',
    'MKR': 'Maker (MKR)',
    'SPK': 'SparkPoint (SPK)',
    'SLF': 'Self Chain (SLF)',
  };
  
  // Selected coins and their data
  Set<String> _selectedCoins = {'BTC'};
  Map<String, CoinData> _coinDataMap = {};

  final List<String> _timeframes = ['1m', '3m', '5m', '15m', '1h'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initializeSelectedCoins();
    _fetchAllData();
    _dataTimer = Timer.periodic(Duration(seconds: 10), (timer) => _fetchAllData());
    _priceTimer = Timer.periodic(Duration(seconds: 3), (timer) => _fetchAllPrices());
  }

  void _initializeSelectedCoins() {
    for (String symbol in _selectedCoins) {
      _coinDataMap[symbol] = CoinData(
        symbol: symbol,
        name: _availableCoins[symbol]!,
      );
      _signalConfirmationStatus[symbol] = '';
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _priceTimer?.cancel();
    _dataTimer?.cancel();
    _fastLengthController.dispose();
    _slowLengthController.dispose();
    _signalLengthController.dispose();
    _stopLossController.dispose();
    _takeProfitController.dispose();
    _marginController.dispose();
    _leverageController.dispose();
    super.dispose();
  }

  Future<void> _fetchAllPrices() async {
    for (String symbol in _selectedCoins) {
      await _fetchPrice(symbol);
    }
  }

  Future<void> _fetchAllData() async {
    for (String symbol in _selectedCoins) {
      await _fetchData(symbol);
    }
  }

  Future<void> _fetchPrice(String symbol) async {
    try {
      final coinPair = symbol + 'USDT';
      final response = await http.get(Uri.parse(
          'https://fapi.binance.com/fapi/v1/klines?symbol=$coinPair&interval=$_timeframe&limit=1'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          final latestPrice = double.parse(data[0][4].toString());
          setState(() {
            _coinDataMap[symbol]?.price = latestPrice;
          });
          
          // Check for trade exit conditions
          if (_isTrading && _coinDataMap[symbol]?.activeTrade != null) {
            _checkTradeExit(symbol, latestPrice);
          }
        }
      }
    } catch (e) {
      print('Error fetching price for $symbol: $e');
    }
  }

  Future<void> _fetchData(String symbol) async {
    try {
      final coinPair = symbol + 'USDT';
      final response = await http.get(Uri.parse(
          'https://fapi.binance.com/fapi/v1/klines?symbol=$coinPair&interval=$_timeframe&limit=1000'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        final closes = data.map<double>((item) => double.parse(item[4].toString())).toList();
        final ema50 = _calculateEMA(closes, 50);
        final ema200 = _calculateEMA(closes, 200);
        final macdSignals = _calculateMACDSignals(data, symbol);
        
        setState(() {
          final coinData = _coinDataMap[symbol]!;
          coinData.price = closes.last;
          coinData.ema50 = ema50.last;
          coinData.ema200 = ema200.last;
          
          if (_isTrading &&
              macdSignals['signal'] != null &&
              macdSignals['signal']!.isNotEmpty &&
              macdSignals['time'] != null &&
              _tradeStartTime != null &&
              DateTime.parse(macdSignals['time']!).isAfter(_tradeStartTime!) &&
              (coinData.latestSignal != macdSignals['signal'] || coinData.signalTime.isEmpty)) {
            
            if (coinData.activeTrade != null) {
              // Check if new signal is opposite or same as current position
              final currentPosition = coinData.activeTrade!.type == 'long' ? 'Buy' : 'Sell';
              if (macdSignals['signal'] == currentPosition) {
                // Same signal, stay in position
                _signalConfirmationStatus[symbol] = 'Same Signal (${macdSignals['signal']})';
                return;
              } else {
                // Opposite signal, close current trade
                _closeTrade(symbol, coinData.activeTrade!, coinData.price, 'new_signal');
              }
            }
            
            // Store the pending signal and wait 5 seconds
            _pendingSignals[symbol] = macdSignals['signal']!;
            _signalConfirmationStatus[symbol] = 'Pending (${macdSignals['signal']})';
            
            // Schedule signal recheck
            Future.delayed(Duration(seconds: 5), () async {
              await _recheckSignal(symbol, macdSignals['signal']!, data);
            });
          } else if (!_isTrading) {
            _signalConfirmationStatus[symbol] = '';
          }
        });
      }
    } catch (e) {
      print('Error fetching data for $symbol: $e');
      setState(() {
        _signalConfirmationStatus[symbol] = 'Error';
      });
    }
  }

  Future<void> _recheckSignal(String symbol, String originalSignal, List originalData) async {
    try {
      final coinPair = symbol + 'USDT';
      final response = await http.get(Uri.parse(
          'https://fapi.binance.com/fapi/v1/klines?symbol=$coinPair&interval=$_timeframe&limit=1000'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final macdSignals = _calculateMACDSignals(data, symbol);
        
        setState(() {
          final coinData = _coinDataMap[symbol]!;
          if (macdSignals['signal'] == originalSignal && _isTrading) {
            // Signal confirmed, update coin data and execute trade
            coinData.latestSignal = macdSignals['signal']!;
            coinData.signalTime = macdSignals['time']!;
            coinData.signalHistory.add({'signal': coinData.latestSignal, 'time': coinData.signalTime});
            _signalConfirmationStatus[symbol] = 'Confirmed (${originalSignal})';
            
            _executeTrade(symbol, coinData.latestSignal, data);
          } else {
            // Signal not confirmed or trading stopped
            _signalConfirmationStatus[symbol] = 'Not Confirmed (${originalSignal})';
          }
          _pendingSignals.remove(symbol);
        });
      } else {
        setState(() {
          _signalConfirmationStatus[symbol] = 'Error';
          _pendingSignals.remove(symbol);
        });
      }
    } catch (e) {
      print('Error rechecking signal for $symbol: $e');
      setState(() {
        _signalConfirmationStatus[symbol] = 'Error';
        _pendingSignals.remove(symbol);
      });
    }
  }

  void _executeTrade(String symbol, String signal, List data) {
    final coinData = _coinDataMap[symbol]!;
    
    if (coinData.activeTrade != null) {
      // Close existing trade before opening new one (should be handled already in _fetchData for opposite signals)
      _closeTrade(symbol, coinData.activeTrade!, coinData.price, 'new_signal');
    }

    final margin = double.tryParse(_marginController.text) ?? 10.0;
    final leverage = double.tryParse(_leverageController.text) ?? 10.0;
    final takeProfitAmount = double.tryParse(_takeProfitController.text) ?? 0.01;
    final stopLossAmount = double.tryParse(_stopLossController.text) ?? 10.0;
    final quantity = (margin * leverage) / coinData.price;
    
    double stopLossPrice;
    double takeProfitPrice;

    if (signal == 'Buy') {
      // For long: set stop-loss price based on loss in USDT
      stopLossPrice = coinData.price - (stopLossAmount / quantity);
      takeProfitPrice = coinData.price + (takeProfitAmount / quantity);
      
      coinData.activeTrade = Trade(
        symbol: symbol,
        type: 'long',
        entryPrice: coinData.price,
        stopLoss: stopLossPrice,
        takeProfit: takeProfitPrice,
        margin: margin,
        leverage: leverage,
        quantity: quantity,
        entryTime: DateTime.now().toString(),
      );
    } else if (signal == 'Sell') {
      // For short: set stop-loss price based on loss in USDT
      stopLossPrice = coinData.price + (stopLossAmount / quantity);
      takeProfitPrice = coinData.price - (takeProfitAmount / quantity);
      
      coinData.activeTrade = Trade(
        symbol: symbol,
        type: 'short',
        entryPrice: coinData.price,
        stopLoss: stopLossPrice,
        takeProfit: takeProfitPrice,
        margin: margin,
        leverage: leverage,
        quantity: quantity,
        entryTime: DateTime.now().toString(),
      );
    }
  }

  void _checkTradeExit(String symbol, double currentPrice) {
    final coinData = _coinDataMap[symbol]!;
    final activeTrade = coinData.activeTrade;
    if (activeTrade == null) return;

    bool shouldClose = false;
    String exitReason = '';
    final stopLossAmount = double.tryParse(_stopLossController.text) ?? 10.0;

    // Calculate current P&L to check against stop-loss in USDT
    double currentPnL = _calculateCurrentPnL(coinData);

    if (activeTrade.type == 'long') {
      if (currentPrice <= activeTrade.stopLoss || currentPnL <= -stopLossAmount) {
        shouldClose = true;
        exitReason = 'stop_loss';
      } else if (currentPrice >= activeTrade.takeProfit) {
        shouldClose = true;
        exitReason = 'take_profit';
      }
    } else if (activeTrade.type == 'short') {
      if (currentPrice >= activeTrade.stopLoss || currentPnL <= -stopLossAmount) {
        shouldClose = true;
        exitReason = 'stop_loss';
      } else if (currentPrice <= activeTrade.takeProfit) {
        shouldClose = true;
        exitReason = 'take_profit';
      }
    }

    if (shouldClose) {
      _closeTrade(symbol, activeTrade, currentPrice, exitReason);
      setState(() {
        coinData.latestSignal = ''; // Clear signal to wait for new one
        coinData.signalTime = '';
        _signalConfirmationStatus[symbol] = '';
      });
    }
  }

  void _closeTrade(String symbol, Trade trade, double exitPrice, String exitReason) {
    double pnl = 0.0;
    
    if (trade.type == 'long') {
      pnl = (exitPrice - trade.entryPrice) * trade.quantity;
    } else {
      pnl = (trade.entryPrice - exitPrice) * trade.quantity;
    }

    trade.exitPrice = exitPrice;
    trade.exitReason = exitReason;
    trade.exitTime = DateTime.now().toString();
    trade.pnl = pnl;
    trade.isActive = false;

    setState(() {
      final coinData = _coinDataMap[symbol]!;
      coinData.tradeHistory.add(trade);
      coinData.activeTrade = null;
      _totalPnL += pnl;
      if (pnl > 0) {
        _winningTrades++;
        _totalProfit += pnl;
      } else {
        _losingTrades++;
        _totalLoss += pnl.abs();
      }
    });
  }

  List<double> _calculateEMA(List<double> data, int period) {
    List<double> ema = List<double>.filled(data.length, 0.0);
    double multiplier = 2.0 / (period + 1);

    for (int i = 0; i < data.length; i++) {
      if (i == 0) {
        ema[i] = data[i];
      } else {
        ema[i] = data[i] * multiplier + ema[i - 1] * (1 - multiplier);
      }
    }
    return ema;
  }

  Map<String, String?> _calculateMACDSignals(List data, String symbol) {
    if (data.length < 2) return {'signal': null, 'time': null};

    final coinData = _coinDataMap[symbol]!;
    final closes = data.map<double>((item) => double.parse(item[4].toString())).toList();
    final timestamps = data.map<int>((item) => item[0] as int).toList();

    // MACD parameters
    final fastLength = int.tryParse(_fastLengthController.text) ?? 12;
    final slowLength = int.tryParse(_slowLengthController.text) ?? 26;
    final signalLength = int.tryParse(_signalLengthController.text) ?? 9;

    // Calculate MACD components
    final fastEMA = _calculateEMA(closes, fastLength);
    final slowEMA = _calculateEMA(closes, slowLength);
    final macd = List<double>.generate(closes.length, (i) => fastEMA[i] - slowEMA[i]);
    final signalLine = _calculateEMA(macd, signalLength);

    String? signal = coinData.latestSignal;
    String? signalTime = coinData.signalTime;

    // Check for crossover signals
    for (int i = 1; i < closes.length; i++) {
      bool bullishCrossover = macd[i] > signalLine[i] && macd[i - 1] <= signalLine[i - 1];
      bool bearishCrossover = macd[i] < signalLine[i] && macd[i - 1] >= signalLine[i - 1];

      // Buy signal: MACD crosses above Signal line AND both are below zero
      if (bullishCrossover && macd[i] < 0 && signalLine[i] < 0) {
        signal = 'Buy';
        signalTime = DateTime.fromMillisecondsSinceEpoch(timestamps[i]).toString();
      }
      // Sell signal: Signal crosses above MACD line AND both are above zero
      else if (bearishCrossover && macd[i] > 0 && signalLine[i] > 0) {
        signal = 'Sell';
        signalTime = DateTime.fromMillisecondsSinceEpoch(timestamps[i]).toString();
      }
    }

    return {'signal': signal, 'time': signalTime};
  }

  void _updateTimeframe(String? newTimeframe) {
    if (newTimeframe != null && newTimeframe != _timeframe) {
      setState(() {
        _timeframe = newTimeframe;
        _signalConfirmationStatus.clear();
        _pendingSignals.clear();
        for (String symbol in _selectedCoins) {
          _signalConfirmationStatus[symbol] = '';
          _coinDataMap[symbol]?.latestSignal = '';
          _coinDataMap[symbol]?.signalTime = '';
        }
        _fetchAllData();
      });
    }
  }

  void _startTrading() {
    setState(() {
      _isTrading = true;
      _tradeStartTime = DateTime.now();
      // Clear all trade histories, signals, and signal statuses
      for (String symbol in _selectedCoins) {
        _coinDataMap[symbol]?.tradeHistory.clear();
        _coinDataMap[symbol]?.activeTrade = null;
        _coinDataMap[symbol]?.latestSignal = '';
        _coinDataMap[symbol]?.signalTime = '';
        _signalConfirmationStatus[symbol] = '';
        _pendingSignals.remove(symbol);
      }
      _totalPnL = 0.0;
      _totalProfit = 0.0;
      _totalLoss = 0.0;
      _winningTrades = 0;
      _losingTrades = 0;
    });
  }

  void _stopTrading() {
    setState(() {
      _isTrading = false;
      _tradeStartTime = null;
      // Close all active trades and clear signal statuses
      for (String symbol in _selectedCoins) {
        final coinData = _coinDataMap[symbol];
        if (coinData?.activeTrade != null) {
          _closeTrade(symbol, coinData!.activeTrade!, coinData.price, 'manual_stop');
        }
        coinData?.latestSignal = '';
        coinData?.signalTime = '';
        _signalConfirmationStatus[symbol] = '';
        _pendingSignals.remove(symbol);
      }
    });
  }

  Widget _buildCoinSelectionTab() {
    return Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select Coins to Trade (Max 30)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Text('Selected: ${_selectedCoins.length}/30', style: TextStyle(fontSize: 16)),
          SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: _availableCoins.length,
              itemBuilder: (context, index) {
                final symbol = _availableCoins.keys.elementAt(index);
                final name = _availableCoins[symbol]!;
                final isSelected = _selectedCoins.contains(symbol);
                
                return CheckboxListTile(
                  title: Text(name),
                  subtitle: Text('Symbol: $symbol'),
                  value: isSelected,
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true && _selectedCoins.length < 30) {
                        _selectedCoins.add(symbol);
                        _coinDataMap[symbol] = CoinData(symbol: symbol, name: name);
                        _signalConfirmationStatus[symbol] = '';
                      } else if (value == false) {
                        _selectedCoins.remove(symbol);
                        _coinDataMap.remove(symbol);
                        _signalConfirmationStatus.remove(symbol);
                        _pendingSignals.remove(symbol);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainTab() {
    return Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Trading Parameters
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _fastLengthController,
                  decoration: InputDecoration(labelText: 'Fast Length'),
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _fetchAllData(),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _slowLengthController,
                  decoration: InputDecoration(labelText: 'Slow Length'),
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _fetchAllData(),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _signalLengthController,
                  decoration: InputDecoration(labelText: 'Signal Length'),
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _fetchAllData(),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _stopLossController,
                  decoration: InputDecoration(labelText: 'Stop Loss (USDT)'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _marginController,
                  decoration: InputDecoration(labelText: 'Margin (USDT)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _leverageController,
                  decoration: InputDecoration(labelText: 'Leverage'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _takeProfitController,
                  decoration: InputDecoration(labelText: 'Take Profit (USDT)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: DropdownButton<String>(
                  value: _timeframe,
                  items: _timeframes.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: _updateTimeframe,
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isTrading ? _stopTrading : _startTrading,
            child: Text(_isTrading ? 'Stop Trading' : 'Start Trading'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isTrading ? Colors.red : Colors.green,
            ),
          ),
          SizedBox(height: 20),
          Text('Trading Status: ${_isTrading ? "Active" : "Inactive"}', 
               style: TextStyle(fontSize: 16, color: _isTrading ? Colors.green : Colors.red)),
          Text('Timeframe: $_timeframe', style: TextStyle(fontSize: 16)),
          SizedBox(height: 20),
          // Coins Overview
          Text('Coins Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: _selectedCoins.length,
              itemBuilder: (context, index) {
                final symbol = _selectedCoins.elementAt(index);
                final coinData = _coinDataMap[symbol]!;
                final confirmationStatus = _signalConfirmationStatus[symbol] ?? '';
                
                return Card(
                  child: ListTile(
                    title: Text('${coinData.name}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Price: \$${coinData.price.toStringAsFixed(10)}'),
                        Text('Position: ${coinData.position}', 
                             style: TextStyle(
                               color: coinData.position == 'Long' ? Colors.green 
                                     : coinData.position == 'Short' ? Colors.red 
                                     : Colors.grey)),
                        if (coinData.activeTrade != null) ...[
                          Text('Entry: \$${coinData.activeTrade!.entryPrice.toStringAsFixed(10)}'),
                          Text('P&L: \$${_calculateCurrentPnL(coinData).toStringAsFixed(10)}',
                               style: TextStyle(color: _calculateCurrentPnL(coinData) >= 0 ? Colors.green : Colors.red)),
                        ],
                        if (coinData.latestSignal.isNotEmpty)
                          Text('Last Signal: ${coinData.latestSignal}',
                               style: TextStyle(color: coinData.latestSignal == 'Buy' ? Colors.green : Colors.red)),
                        if (confirmationStatus.isNotEmpty)
                          Text('Signal Status: $confirmationStatus',
                               style: TextStyle(
                                 color: confirmationStatus.contains('Confirmed') ? Colors.green
                                       : confirmationStatus.contains('Pending') ? Colors.orange
                                       : confirmationStatus.contains('Not Confirmed') ? Colors.red
                                       : confirmationStatus.contains('Same Signal') ? Colors.blue
                                       : Colors.grey)),
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

  double _calculateCurrentPnL(CoinData coinData) {
    if (coinData.activeTrade == null) return 0.0;
    
    final trade = coinData.activeTrade!;
    if (trade.type == 'long') {
      return (coinData.price - trade.entryPrice) * trade.quantity;
    } else {
      return (trade.entryPrice - coinData.price) * trade.quantity;
    }
  }

  Widget _buildTradesTab() {
    List<Trade> allTrades = [];
    for (String symbol in _selectedCoins) {
      allTrades.addAll(_coinDataMap[symbol]?.tradeHistory ?? []);
    }
    // Sort by entry time (most recent first)
    allTrades.sort((a, b) => b.entryTime.compareTo(a.entryTime));

    return Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        children: [
          Text('All Trade History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: allTrades.length,
              itemBuilder: (context, index) {
                final trade = allTrades[index];
                return Card(
                  child: ListTile(
                    title: Text('${trade.symbol} - ${trade.type.toUpperCase()} - ${trade.exitReason?.toUpperCase() ?? "ACTIVE"}',
                                style: TextStyle(color: trade.pnl != null && trade.pnl! >= 0 ? Colors.green : Colors.red)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Entry: \$${trade.entryPrice.toStringAsFixed(10)} | Exit: \$${trade.exitPrice?.toStringAsFixed(10) ?? "N/A"}'),
                        Text('SL: \$${trade.stopLoss.toStringAsFixed(10)} | TP: \$${trade.takeProfit.toStringAsFixed(10)}'),
                        Text('Margin: \$${trade.margin.toStringAsFixed(2)} | Leverage: ${trade.leverage}x | Qty: ${trade.quantity.toStringAsFixed(10)}'),
                        Text('P&L: \$${trade.pnl?.toStringAsFixed(10) ?? "N/A"}'),
                        Text('Entry Time: ${trade.entryTime}'),
                        if (trade.exitTime != null) Text('Exit Time: ${trade.exitTime}'),
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

  Widget _buildSummaryTab() {
    final totalTrades = _winningTrades + _losingTrades;
    final winRate = totalTrades > 0 ? (_winningTrades / totalTrades * 100) : 0.0;
    final activeTrades = _selectedCoins.where((symbol) => _coinDataMap[symbol]?.activeTrade != null).length;
    
    return Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trading Summary', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 20),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total P&L: \$${_totalPnL.toStringAsFixed(10)}', 
                       style: TextStyle(fontSize: 18, color: _totalPnL >= 0 ? Colors.green : Colors.red)),
                  SizedBox(height: 10),
                  Text('Total Profit: \$${_totalProfit.toStringAsFixed(10)}', 
                       style: TextStyle(fontSize: 16, color: Colors.green)),
                  Text('Total Loss: \$${_totalLoss.toStringAsFixed(10)}', 
                       style: TextStyle(fontSize: 16, color: Colors.red)),
                  SizedBox(height: 10),
                  Text('Total Trades: $totalTrades', style: TextStyle(fontSize: 16)),
                  Text('Winning Trades: $_winningTrades', style: TextStyle(fontSize: 16, color: Colors.green)),
                  Text('Losing Trades: $_losingTrades', style: TextStyle(fontSize: 16, color: Colors.red)),
                  Text('Win Rate: ${winRate.toStringAsFixed(1)}%', style: TextStyle(fontSize: 16)),
                  Text('Active Trades: $activeTrades', style: TextStyle(fontSize: 16, color: Colors.blue)),
                  Text('Selected Coins: ${_selectedCoins.length}', style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ),
          SizedBox(height: 20),
          Text('Active Positions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: _selectedCoins.length,
              itemBuilder: (context, index) {
                final symbol = _selectedCoins.elementAt(index);
                final coinData = _coinDataMap[symbol]!;
                
                if (coinData.activeTrade == null) return SizedBox.shrink();
                
                final trade = coinData.activeTrade!;
                final currentPnL = _calculateCurrentPnL(coinData);
                
                return Card(
                  child: ListTile(
                    title: Text('${symbol} - ${trade.type.toUpperCase()}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Entry: \$${trade.entryPrice.toStringAsFixed(10)} | Current: \$${coinData.price.toStringAsFixed(10)}'),
                        Text('SL: \$${trade.stopLoss.toStringAsFixed(10)} | TP: \$${trade.takeProfit.toStringAsFixed(10)}'),
                        Text('Margin: \$${trade.margin} | Leverage: ${trade.leverage}x'),
                        Text('Current P&L: \$${currentPnL.toStringAsFixed(10)}',
                             style: TextStyle(color: currentPnL >= 0 ? Colors.green : Colors.red)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Multi-Coin Trading Simulator'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Coins'),
            Tab(text: 'Trading'),
            Tab(text: 'Trades'),
            Tab(text: 'Summary'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCoinSelectionTab(),
          _buildMainTab(),
          _buildTradesTab(),
          _buildSummaryTab(),
        ],
      ),
    );
  }
}
