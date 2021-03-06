part of zart_prujohn;

/**
* A runtime debugger for Z-Machine.
*/
class Debugger {
  static bool enableVerbose = false;
  static bool enableTrace = false;
  static bool enableDebug = false;
  static bool enableStackTrace = false;
  static bool isUnitTestRun = false;

  static int debugStartAddr;

  static List<int> _breakPoints;

  static int instructionsCounter = 0;

  static void setMachine(Machine newMachine){
    Z.inInterrupt = true;
    if (Z.isLoaded){
      if (newMachine.version != Z._ver){
        throw new GameException('Machine/Story version mismatch.');
      }
    }

    Z.machine = newMachine;
    Z.machine.mem = new _MemoryMap(Z._rawBytes);
    Z.machine.visitHeader();
    debug('<<< New machine installed: v${newMachine.version} >>>');
    Z.inInterrupt = false;
  }

  static void startBreak(){
    Z.sendIO(
      IOCommands.PRINT_DEBUG,
    [
    '(break)>>> 0x${debugStartAddr.toRadixString(16)}:'
    ' opCode: ${Z.machine.mem.loadb(debugStartAddr)}'
    '\n'
    '    Locals ${dumpLocals()}\n'
    ])
    .then((_){
      Z.callAsync(_repl);
    });
  }

  static void _repl(){

    void parse(String command){
      var cl = command.toLowerCase().trim();
      var args = cl.split(' ');

      switch(args[0]){
        case 'dump':
          var addr = int.parse(args[1]);
          var howMany = int.parse(args[2]);
          debug('${Z.machine.mem.dump(addr, howMany)}');
          Z.callAsync(_repl);
          break;
        case 'move':
          var obj1 = new GameObject(int.parse(args[1]));
          var obj2 = new GameObject(int.parse(args[2]));
          obj1.insertTo(obj2.id);
          Z.callAsync(_repl);
          break;
        case 'enable':
          switch(args[1]){
            case 'trace':
              Debugger.enableTrace = true;
              debug('Trace Enabled.');
              break;
            case 'verbose':
              Debugger.enableVerbose = true;
              debug('Verbose Enabled.');
              break;
            case 'stacktrace':
              Debugger.enableStackTrace = true;
              debug('Stack Trace Enabled.');
              break;
          }
          Z.callAsync(_repl);
          break;
        case 'disable':
          switch(args[1]){
            case 'trace':
              Debugger.enableTrace = false;
              debug('Trace Disabled.');
              break;
            case 'verbose':
              Debugger.enableVerbose = false;
              debug('Verbose Disabled.');
              break;
            case 'stacktrace':
              Debugger.enableStackTrace = false;
              debug('Stack Trace Disabled.');
              break;
          }
          Z.callAsync(_repl);
          break;
        case '':
        case 'n':
          debugStartAddr = Z.machine.PC;
          Z.machine.visitInstruction();
          break;
        case 'q':
          Z.inBreak = false;
          Z.callAsync(Z.runIt);
          break;
        case 'dictionary':
          debug('${Z.machine.mem.dictionary.dump()}');
          Z.callAsync(Z.runIt);
          break;
        case 'globals':
          StringBuffer s = new StringBuffer();

          var col = args.length == 2 ? int.parse(args[1]) : 10;
          if (col < 1) col = 1;

          for(int i = 0x10; i < 0xff; i++){

            s.add('g${i - 16 < 10 ? "0" : ""}${i - 16}:'
            ' 0x${Z.machine.mem.readGlobal(i).toRadixString(16)}');

            if ((i - 15) % col != 0){
              s.add('\t');
            }else{
              s.add('\n');
            }
          }
          debug('$s');
          Z.callAsync(_repl);
          break;
        case 'locals':
          debug('${dumpLocals()}');
          Z.callAsync(_repl);
          break;
        case 'stacks':
          debug('call stack: ${Z.machine.callStack}');
          debug('eval stack: ${Z.machine.stack}');
          Z.callAsync(_repl);
          break;
        case 'object':
          var obj = new GameObject(int.parse(args[1]));
          obj.dump();
          Z.callAsync(_repl);
          break;
        case 'header':
          debug('${dumpHeader()}');
          Z.callAsync(_repl);
          break;
        default:
          debug('Unknown Command.');
          Z.callAsync(_repl);
          break;
      }
    }

    Z.sendIO(IOCommands.READ, [])
    .then((line){
      parse(line);
    });
  }

  static void enableAll(){
    Debugger.enableDebug = true;
    Debugger.enableStackTrace = true;
    Debugger.enableVerbose = true;
    Debugger.enableTrace = true;
  }

  static void disableAll(){
    Debugger.enableDebug = false;
    Debugger.enableStackTrace = false;
    Debugger.enableVerbose = false;
    Debugger.enableTrace = false;
  }

  static bool isBreakPoint(int addr){
    if (_breakPoints == null) return false;
    return _breakPoints.indexOf(addr) != -1;
  }

  static void setBreaks(List breakPoints) {
    if (_breakPoints == null){
      _breakPoints = new List<int>();
    }else{
      _breakPoints.clear();
    }
    _breakPoints.addAll(breakPoints);
  }

  static String crashReport(){
    var s = new StringBuffer();
    s.add('Call Stack: ${Z.machine.callStack}\n');
    s.add('Game Stack: ${Z.machine.stack}\n');
    s.add(dumpLocals());
    return s.toString();
  }

  static String dumpLocals(){
    var locals = Z.machine.callStack[2];
    StringBuffer s = new StringBuffer();

    for(int i = 0; i < locals; i++){
      s.add('(L${i}: 0x${Z.machine._readLocal(i + 1).toRadixString(16)}) ');
    }
    s.add('\n');
    return s.toString();
  }

  static String dumpHeader(){
    if (!Z.isLoaded) return '<<< Machine Not Loaded >>>\n';

    var s = new StringBuffer();

    s.add('(Story contains ${Z.machine.mem.size} bytes.)\n');
    s.add('\n');
    s.add('------- START HEADER -------\n');
    s.add('Z-Machine Version: ${Z.machine.version}\n');
    s.add('Flags1(binary): 0b${Z.machine.mem.loadw(Header.FLAGS1).toRadixString(2)}\n');
    // word after flags1 is used by Inform
    s.add('Abbreviations Location: 0x${Z.machine.mem.abbrAddress.toRadixString(16)}\n');
    s.add('Object Table Location: 0x${Z.machine.mem.objectsAddress.toRadixString(16)}\n');
    s.add('Global Variables Location: 0x${Z.machine.mem.globalVarsAddress.toRadixString(16)}\n');
    s.add('Static Memory Start: 0x${Z.machine.mem.staticMemAddress.toRadixString(16)}\n');
    s.add('Dictionary Location: 0x${Z.machine.mem.dictionaryAddress.toRadixString(16)}\n');
    s.add('High Memory Start: 0x${Z.machine.mem.highMemAddress.toRadixString(16)}\n');
    s.add('Program Counter Start: 0x${Z.machine.mem.programStart.toRadixString(16)}\n');
    s.add('Flags2(binary): 0b${Z.machine.mem.loadb(Header.FLAGS2).toRadixString(2)}\n');
    s.add('Length Of File: ${Z.machine.mem.loadw(Header.LENGTHOFFILE) * Z.machine.fileLengthMultiplier()}\n');
    s.add('Checksum Of File: ${Z.machine.mem.loadw(Header.CHECKSUMOFFILE)}\n');
    //TODO v4+ header stuff here
    s.add('Standard Revision: ${Z.machine.mem.loadw(Header.REVISION_NUMBER)}\n');
    s.add('-------- END HEADER ---------\n');

    //s.add('main Routine: ${Z.machine.mem.getRange(Z.pc - 4, 10)}');

    s.add('\n');
    return s.toString();
  }


  /// Verbose Channel (via Debug)
  static void verbose(String outString){
    //TODO support redirect to file.
    if (Debugger.enableDebug && Debugger.enableVerbose) {
      debug(outString);
    }
  }

  /// Debug Channel
  static void debug(String debugString) {
    Z.sendIO(IOCommands.PRINT_DEBUG, ['(Zart Debug) $debugString']);
  }


  static void todo([String message]){
    Z.sendIO(IOCommands.PRINT_DEBUG,
      [
        'Stopped At: 0x${Z.machine.PC.toRadixString(16)}\n\n'
        'Text Buffer:\n'
        '${Z.sbuff}\n'
        '${message != null ? "TODO: $message" : ""}\n'
      ])
      .then((_) {
        throw const NotImplementedException();
      });
  }
}
