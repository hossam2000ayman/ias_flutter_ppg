import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:wakelock/wakelock.dart';
import 'dart:math';
import 'waveform.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:image/image.dart' as imglib;
import 'package:csv/csv.dart';



class HomePage extends StatefulWidget {
  @override
  HomePageView createState() {
    return HomePageView();
  }
}

class HomePageView extends State<HomePage> {
  bool _toggled = false;
  bool _processing = false;
  List<SensorValue> _data = [];
  List<SensorStats> _statdata = [];
  List<List<dynamic>> _reddata = [];
  List<List<dynamic>> _bluedata = [];
  CameraController ?_controller;
  double _std=0;
  double _alpha = 0.3;
  double _hr = 0;
  int ?_hrvar;
  List<SensorValue> _hrvlist = [];
  int ?_resprat;
  List<SensorValue> _resprlist = [];

    _toggle() {
      _initController().then((onValue) {
      setState(() {
        _toggled = true;
        _processing = false;
      });
      _updateBPM();
      /*_updateStdmean();*/
    });
  }

  _untoggle() {
    _disposeController();
    //_write(_reddata, 'red');
    //_write(_bluedata, 'blue');
    setState(() {
      _toggled = false;
      _processing = false;
    });
  }

  Future<void> _initController() async {
    try {
      List _cameras = await availableCameras();
      _controller = CameraController(_cameras.first, ResolutionPreset.low);
      await _controller!.initialize();
      Future.delayed(Duration(milliseconds: 500)).then((onValue) {
        _controller!.setFlashMode(FlashMode.always);
      });
      _controller!.startImageStream((CameraImage image) {
        if (!_processing) {
          setState(() {
            _processing = true;
          });
          _scanImage(image);
        }
      });
    } catch (Exception) {
      print(Exception);
    }
  }

  _disposeController() {
      _controller!.dispose();
      
  }

   _updateBPM() async {
    List<SensorValue> _values;
    List<SensorStats> _devs;
    double _avg;
    int _n;
    int _nstat;
    double _m;
    double _threshold;
    double _bpm;
    double _redSigMean;
    double _blueSigMean;
    double _redSigStd;
    double _blueSigStd;
    int _counter;
    int _previous;
    int _hrv;
    double _spo2val;
    while (_toggled) {
      _values = List.from(_data);
      _devs = List.from(_statdata);
      _avg = 0;
      _n = _values.length;
      _m = 0;
      _values.forEach((SensorValue value) {
        _avg += value.value / _n;
        if (value.value > _m) _m = value.value;
      });


      _threshold = (_m + _avg) / 2;
      _bpm = 0;
      _counter = 0;
      _previous = 0;
      _hrv = 0;
      for (int i = 1; i < _n; i++) {
        if (_values[i - 1].value < _threshold &&
            _values[i].value > _threshold) {
          if (_previous != 0) {
            _counter++;
            _bpm +=
                60000 / (_values[i].time.millisecondsSinceEpoch - _previous);
            _hrv = _values[i].time.millisecondsSinceEpoch - _previous;
          }
          _previous = _values[i].time.millisecondsSinceEpoch;
        }
      }

      

      _spo2val = 0;
      _redSigMean = 0;
      _blueSigMean = 0;
      _redSigStd = 0;
      _blueSigStd = 0;
      _nstat = _devs.length;
      _devs.forEach((SensorStats stat) {
        _redSigMean += stat.redmean / _nstat;
        _blueSigMean += stat.bluemean / _nstat;
      });
      _devs.forEach((SensorStats stat) {
        _redSigStd += sqrt(pow((stat.redmean -_redSigMean),2) /_nstat);
        _blueSigStd += sqrt(pow((stat.bluemean -_blueSigMean),2) /_nstat);
      });
      _spo2val = _redSigStd/_redSigMean/_blueSigStd/_blueSigMean;


      setState((){
          _hrvar = _hrv;
          _hrvlist.add(SensorValue(DateTime.now(), pow(_hrv,2).toDouble()));
        });
      if (_hrvlist.length > 20) {
        _hrvlist.removeAt(0);
        }
      

      if (_counter > 0) {
        _bpm = _bpm / _counter;
        setState(() {
          _hr = ((1 - _alpha) * _bpm + _alpha * _bpm);
        });
        setState((){
          _std = 100-100*_spo2val;
        });
      }
      await Future.delayed(Duration(milliseconds: (1000 * 50 / 30).round()));
    }
  }

  

  _scanImage(CameraImage image) {

        final int width = image.width;
        final int height = image.height;
        final int uvRowStride = image.planes[1].bytesPerRow;
        final int uvPixelStride = image.planes[1].bytesPerPixel!;
        List<int> _redCh = [];
        List<int> _greenCh = [];
        List<int> _blueCh = [];

        
        // imgLib -> Image package from https://pub.dartlang.org/packages/image
        var img = imglib.Image(width, height); // Create Image buffer

        // Fill image buffer with plane[0] from YUV420_888
        for(int x=0; x < width; x++) {
          for(int y=0; y < height; y++) {
            final int uvIndex = uvPixelStride * (x/2).floor() + uvRowStride*(y/2).floor();
            final int index = y * width + x;

            final yp = image.planes[0].bytes[index];
            final up = image.planes[1].bytes[uvIndex];
            final vp = image.planes[2].bytes[uvIndex];
            // Calculate pixel color
            int r = (yp + (vp-128) * 1.370705).round().clamp(0, 255);
            int g = (yp - (up-128) * 0.337633 - (vp-128) * 0.698001).round().clamp(0, 255);
            int b = (yp + (up-128) * 1.732446).round().clamp(0, 255);
            _redCh.add(255-r);
            _greenCh.add(255-g);
            _blueCh.add(255-b);
          }
        }
      
      _reddata.add(_redCh);
      _bluedata.add(_blueCh);

      int _nred = _redCh.length;

      double _avgred =
          _redCh.reduce((value, element) => value + element) / _nred;
      double _stdred = 0;
      _stdred = _redCh.fold(0,(value, element) => value + sqrt(pow((element-_avgred),2) / _nred));
      int _nblue = _blueCh.length;
      double _avgblue =
          _blueCh.reduce((value, element) => value + element) / _nblue;
      double _stdblue = 0;
      _stdblue = _blueCh.fold(0,(value, element) => value + sqrt(pow((element-_avgblue),2) / _nblue));
      
      double _spo2data = _avgred;

      if (_data.length >= 50) {
        _data.removeAt(0);
      }

      if(_statdata.length >= 50){
        _statdata.removeAt(0);
      }

      setState(() {
        _data.add(SensorValue(DateTime.now(), _spo2data));
        _statdata.add(SensorStats(DateTime.now(), _stdred, _avgred, _stdblue, _avgblue));
      });
      Future.delayed(Duration(milliseconds: 1000 ~/ 30)).then((onValue) {
        setState(() {
          _processing = false;
        });
      });
    }

  _write(List<List> text, String filename) async {
    String csv = const ListToCsvConverter().convert(text);
    final Directory directory = await getApplicationDocumentsDirectory();
    File file = File('${directory.path}/$filename.txt');
    await file.writeAsString(csv);
  }


  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            children: <Widget>[
                              Expanded(
                                child: Container(
                                  color: Colors.red,
                                  child: Center(
                                    child: Text('SpO2',
                                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  color: Colors.red,
                                  child: Center(
                                    child: Text(List.from(_statdata).length == 0 ? '--' : _std.floor().toString(),
                                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: <Widget>[
                              Expanded(
                                child: Container(
                                  color: Colors.red,
                                  child: Center(
                                    child: Text('HR',
                                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  color: Colors.red,
                                  child: Center(
                                  child: Text(_hr == null ? '--' : _hr.round().toString(),
                                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                            ]
                          )
                        ),
                      ]
                    )
                  ),
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            children: <Widget>[
                              Expanded(
                                child: Container(
                                  color: Colors.white,
                                  child: Center(
                                    child: Text('HRV',
                                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  color: Colors.white,
                                  child: Center(
                                    child: Text(_hrvar == null ? '--':_hrvar.toString(),
                                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                            ]
                          )
                        ),
                        Expanded(
                          child: Column(
                            children: <Widget>[
                              Expanded(
                                child: Container(
                                  color: Colors.white,
                                  child: Center(
                                    child: Text('Resp rate',
                                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  color: Colors.white,
                                  child: Center(
                                    child: Text(_hrvar == null ? '--': (13).toString(),
                                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                            ]
                          )
                        )
                      ]
                    )
                  )
                ]
              )
            ),

            Expanded(
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(
                            Radius.circular(18),
                          ),
                          color: Colors.black),
                      child: Chart(_data),
                  ),
                ),
                
              Expanded(
                  child: Container(
                    margin: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(
                          Radius.circular(18),
                        ),
                        color: Colors.black),
                    child: Chart(_hrvlist),
                ),
              ),
            ],
            ),
          ),

            Expanded(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Container(
                      child: _controller == null
                          ? Container()
                          : CameraPreview(_controller!),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child:IconButton(
                        icon: Icon(_toggled ? Icons.favorite : Icons.favorite_border),
                        color: Colors.red,
                        iconSize: 128,
                        onPressed: () {
                        if (_toggled) {
                          _untoggle();
                        } else {
                          _toggle();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              )
            ),
          ],
        )
      ),
    );
  }
}