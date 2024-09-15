import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:face6/camera_view.dart';
import 'package:face6/main.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'detector_view.dart';
import 'face_detector_painter.dart';

class FaceDetectorView extends StatefulWidget {
  @override
  State<FaceDetectorView> createState() => _FaceDetectorViewState();
}

class _FaceDetectorViewState extends State<FaceDetectorView> {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: false,
    ),
  );
  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  String? _text;
  bool _pictureTaken = false;
  CameraLensDirection _cameraLensDirection = CameraLensDirection.front;
  Timer? _timer;
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _cameraActive = false;
  bool anyFaceFullyInsideGuideline = false;

  @override
  void initState() {
    super.initState();
    _initializeCameraController();
  }

  @override
  void dispose() {
    _canProcess = false;
    _timer?.cancel();
    _faceDetector.close();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeCameraController() async {
    try {
      _cameras = await availableCameras();
      final selectedCamera = _cameras?.firstWhere(
        (camera) => camera.lensDirection == _cameraLensDirection,
        orElse: () => _cameras!.first, // Default to the first camera if none match
      );

      if (selectedCamera != null) {
        _controller = CameraController(
          selectedCamera,
          ResolutionPreset.medium, // Consider changing resolution if needed
          enableAudio: false,
        );

        await _controller?.initialize();
        if (mounted) {
          setState(() {
            _cameraActive = true;
            _pictureTaken = false; // Reset the picture taken status
          });
        }
      }
    } catch (e) {
      print("Error initializing camera: $e");
    }
  }

  Future<void> _restartCamera() async {
    if (_controller != null) {
      // Pastikan kamera berhenti sebelum memulai ulang
      await _controller!.stopImageStream();
      await _controller!.dispose();
      _controller = null;
    }

    setState(() {
      _cameraActive = false;
      _pictureTaken = false;
      _isBusy = false; // Set ulang status busy
    });

    // Inisialisasi ulang kamera
    await _initializeCameraController();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Stack(
        children: [
          CameraView(
            customPaint: _customPaint,
            onImage: (inputImage) {
              processImage(inputImage);
            },
            onCameraFeedReady: () {
              print("Camera feed is ready");
            },
            onCameraLensDirectionChanged: (direction) {
              setState(() {
                _cameraLensDirection = direction;
              });
              print("Camera lens direction changed to: $direction");
            },
            initialCameraLensDirection: _cameraLensDirection,
            hasNavigated: true,
          ),
          if (_text != null && _text!.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: EdgeInsets.all(16),
                color: Colors.black54,
                child: Text(
                  _text!,
                  style: TextStyle(color: Colors.white, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          if (!_cameraActive)
            Positioned(
              bottom: 20,
              right: 20,
              child: ElevatedButton(
                onPressed: _restartCamera,
                child: Text('Restart Camera'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _takePicture() async {
    if (_controller == null) {
      print("Camera controller is null");
      return;
    }

    try {
      final image = await _controller!.takePicture();
      setState(() {
        _pictureTaken = true;
      });
      print("Picture taken");

      if (!mounted) return;

      // Tunggu sampai pengguna kembali dari halaman DisplayPictureScreen
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DisplayPictureScreen(imagePath: image.path),
        ),
      );

      // Restart kamera setelah kembali dari DisplayPictureScreen
      _restartCamera();
    } catch (e) {
      print('Error taking picture: $e');
      setState(() {
        _pictureTaken = false;
      });
    }
  }

  Future<void> processImage(final InputImage inputImage) async {
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;

    setState(() {
      _text = "";
    });

    final faces = await _faceDetector.processImage(inputImage);

    if (inputImage.metadata?.size != null && inputImage.metadata?.rotation != null) {
      final guideBox = Rect.fromCenter(
        center: Offset(inputImage.metadata!.size.width / 8, inputImage.metadata!.size.height / 2.5),
        width: 200,
        height: 250,
      );

      final painter = FaceDetectorPainter(
        faces,
        inputImage.metadata!.size,
        inputImage.metadata!.rotation,
        guideBox,
        (faceInsideGuide) async {
          if (faceInsideGuide && _controller != null && !_pictureTaken) {
            _pictureTaken = true;
            _takePicture();

            // try {
            //   final image = await _controller!.takePicture();

            //   if (!mounted) return;
            //   Navigator.push(
            //     context,
            //     MaterialPageRoute(
            //       builder: (context) => DisplayPictureScreen(imagePath: image.path),
            //     ),
            //   );
            // } catch (e) {
            //   print('Error taking picture: $e');
            //   _pictureTaken = false;
            // }
          }
        },
      );
      _customPaint = CustomPaint(painter: painter);
    } else {
      String text = 'face found ${faces.length}\n\n';
      for (final face in faces) {
        text += 'face ${face.boundingBox}\n\n';
      }
      _text = text;
      _customPaint = null;
    }

    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }
}

class DisplayPictureScreen extends StatelessWidget {
  final String imagePath;

  const DisplayPictureScreen({Key? key, required this.imagePath}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _liveFeedBody(context), // Pass context to the body function
    );
  }

  Widget _liveFeedBody(BuildContext context) {
    // Add context parameter
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(
            child: Image.file(File(imagePath)),
          ),
          _backButton(context), // Pass context to back button
        ],
      ),
    );
  }

  Widget _backButton(BuildContext context) => Positioned(
        top: 40,
        left: 8,
        child: SizedBox(
          height: 50.0,
          width: 50.0,
          child: FloatingActionButton(
            heroTag: Object(),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => Home()),
              );
            },
            backgroundColor: Colors.black54,
            child: Icon(
              Icons.arrow_back_ios_outlined,
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      );
}
