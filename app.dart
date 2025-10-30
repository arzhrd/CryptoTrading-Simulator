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
        
       
