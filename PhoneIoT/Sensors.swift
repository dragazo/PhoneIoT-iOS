//
//  Sensors.swift
//  PhoneIoT
//
//  Created by Devin Jean on 3/5/21.
//

import CoreMotion
import CoreLocation
import AVFAudio
import AVFoundation

private class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
        
    static let global = LocationManager()
    private init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
    }
    
    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        
        manager.requestWhenInUseAuthorization()
        manager.requestAlwaysAuthorization()
        
        manager.startUpdatingLocation()
    }
    func stop() {
        manager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            Sensors.location = [loc.coordinate.latitude, loc.coordinate.longitude, loc.course, loc.altitude]
        }
    }
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            start()
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let error = error as? CLError, error.code == .denied {
            print("location permission denied")
            stop()
        }
    }
}

private class MicrophoneManager {
    var recorder: AVAudioRecorder?
    
    static let global = MicrophoneManager()
    private init() { }
    
    func start() {
        if self.recorder != nil { return }
        
        let session = AVAudioSession.sharedInstance()
        if session.recordPermission != .granted {
            session.requestRecordPermission() { accepted in
                if accepted { self.start() }
            }
            return
        }
        
        let target = URL(fileURLWithPath: "/dev/null", isDirectory: true)
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            self.recorder = try AVAudioRecorder(url: target, settings: settings)
            try session.setCategory(.playAndRecord)
            self.recorder!.isMeteringEnabled = true
            self.recorder!.record()
        }
        catch {
            stop()
        }
    }
    func stop() {
        if self.recorder == nil { return }
        self.recorder!.stop()
        self.recorder = nil
    }
}

class Sensors {
    private static let motion = CMMotionManager()
    
    private static let sensorUpdateInterval: Double = 1.0 / 10.0
    private static var updateTimer: Timer?
    
    private static let accelerometerScale: Double = -9.81
    
    static var accelerometer: [Double]?
    static var linearAcceleration: [Double]?
    static var gravity: [Double]?
    static var magnetometer: [Double]?
    static var gyroscope: [Double]?
    static var rotationVector: [Double]?
    
    // these aren't implemented yet
    static var gameRotationVector: [Double]?
    static var proximity: [Double]?
    static var stepCounter: [Double]?
    static var light: [Double]?
    static var orientation: [Double]?
    
    static var location: [Double]? // lat, long, bearing, altitude
    
    static var microphone: [Double]? // microphone level
    
    private static func update(accelerometer data: CMAcceleration) {
        accelerometer = [accelerometerScale * data.x, accelerometerScale * data.y, accelerometerScale * data.z]
    }
    private static func update(linearAcceleration data: CMAcceleration) {
        linearAcceleration = [accelerometerScale * data.x, accelerometerScale * data.y, accelerometerScale * data.z]
    }
    private static func update(gravity data: CMAcceleration) {
        gravity = [accelerometerScale * data.x, accelerometerScale * data.y, accelerometerScale * data.z]
    }
    private static func update(magnetometer data: CMMagneticField) {
        magnetometer = [data.x, data.y, data.z]
    }
    private static func update(gyroscope data: CMRotationRate) {
        gyroscope = [data.x, data.y, data.z]
    }
    private static func update(rotationVector data: CMAttitude) {
        rotationVector = [data.pitch, data.roll, data.yaw, 1]
    }
    
    private static func add(_ a: [Double], _ b: [Double]) -> [Double] {
        assert(a.count == b.count)
        var res = [Double]()
        for i in 0..<a.count {
            res.append(a[i] + b[i])
        }
        return res
    }
    
    static func start() {
        if updateTimer != nil { return }
        updateTimer = Timer.scheduledTimer(withTimeInterval: sensorUpdateInterval, repeats: true) { t in
            if motion.isDeviceMotionActive {
                if let data = motion.deviceMotion {
                    update(linearAcceleration: data.userAcceleration)
                    update(gravity: data.gravity)
                    accelerometer = add(linearAcceleration!, gravity!) // reconstruct accel from linear and gravity
                    update(gyroscope: data.rotationRate)
                    update(magnetometer: data.magneticField.field)
                    update(rotationVector: data.attitude)
                }
            }
            else {
                if let data = motion.accelerometerData { update(accelerometer: data.acceleration) }
                if let data = motion.gyroData { update(gyroscope: data.rotationRate) }
                if let data = motion.magnetometerData { update(magnetometer: data.magneticField) }
            }
            
            if let recorder = MicrophoneManager.global.recorder {
                recorder.updateMeters()
                let x = Double(recorder.averagePower(forChannel: 0))
                let fixed = pow(2, x / 10) / 1.5 // convert db to volume level (plus a little scaling to match Android tests)
                microphone = [min(1, fixed)]
            }
        }
        
        if motion.isDeviceMotionAvailable { // this is the cool one if it's available; has everything and does sensor fusion
            motion.deviceMotionUpdateInterval = sensorUpdateInterval
            motion.startDeviceMotionUpdates()
        }
        else {
            if motion.isAccelerometerAvailable {
                motion.accelerometerUpdateInterval = sensorUpdateInterval
                motion.startAccelerometerUpdates()
            }
            if motion.isGyroAvailable {
                motion.gyroUpdateInterval = sensorUpdateInterval
                motion.startGyroUpdates()
            }
            if motion.isMagnetometerAvailable {
                motion.magnetometerUpdateInterval = sensorUpdateInterval
                motion.startMagnetometerUpdates()
            }
        }
        
        LocationManager.global.start()
        MicrophoneManager.global.start()
    }
    static func stop() {
        if updateTimer == nil { return }
        updateTimer!.invalidate();
        updateTimer = nil
        
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
        if motion.isAccelerometerActive { motion.stopAccelerometerUpdates() }
        if motion.isGyroAvailable { motion.stopGyroUpdates() }
        if motion.isMagnetometerActive { motion.stopMagnetometerUpdates() }
        
        LocationManager.global.stop()
        MicrophoneManager.global.stop()
    }
}
