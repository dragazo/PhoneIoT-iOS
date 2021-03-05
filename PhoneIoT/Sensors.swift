//
//  Sensors.swift
//  PhoneIoT
//
//  Created by Devin Jean on 3/5/21.
//

import CoreMotion

protocol BasicSensor {
    // returns nil if not available, otherwise (potentially computes) and returns the data
    func getData() -> [Double]?
}
let sensorUpdateInterval: Double = 1.0 / 10.0

let motion = CMMotionManager()

class AccelerometerSensor: BasicSensor {
    var data: [Double]?
    func getData() -> [Double]? {
        data
    }
    
    private init() {}
    static let global = AccelerometerSensor()
    
    func start() {
        if motion.isAccelerometerAvailable && !motion.isAccelerometerActive {
            motion.accelerometerUpdateInterval = sensorUpdateInterval
            motion.startAccelerometerUpdates()
        }
    }
}

struct Sensors {
    static let accelerometer = AccelerometerSensor.global
    
    static var updateTimer: Timer?
    
    static func start() {
        if updateTimer != nil { return }
        
        accelerometer.start()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: sensorUpdateInterval, repeats: true) { t in
            if let data = motion.accelerometerData {
                let x = data.acceleration.x
                let y = data.acceleration.y
                let z = data.acceleration.z
                Sensors.accelerometer.data = [x, y, z]
            }
        }
    }
}
